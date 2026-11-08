#!/usr/bin/env bash
# Functional test: apply the module on this machine and compare the rendered
# configuration file, byte for byte, with the fixture for this release. Three
# cases run in order, each with mgmt started, converged and exited:
#
#   1. params:   fixtures/deploy-params.mcl   -> fixtures/chrony.conf-<release>-params
#   2. server:   fixtures/deploy-server.mcl   -> fixtures/chrony.conf-<release>-server
#                then an NTP query against 127.0.0.1 must be answered
#   3. defaults: fixtures/deploy-defaults.mcl -> fixtures/chrony.conf-<release>
#                then the same query must be refused (no allow directive)
#
# The stored stock file, fixtures/defaults/chrony.conf-<release>, is then
# checked byte for byte against the chrony.conf extracted from this release's
# chrony package, and the rendered defaults must have exactly its directives,
# order aside (the module writes them in the manual's order). That is the
# guarantee that the module's defaults are the vanilla distribution config,
# and running defaults last leaves the machine in that state.
#
# <release> is <ID>-<VERSION_ID> from /etc/os-release, for example fedora-44.
#
# This rewrites /etc/chrony.conf and restarts chronyd. Run it as root on a
# machine you do not mind reconfiguring. It uses etcd ports 12379/12380 so it
# does not collide with an mgmt already running.
#
# Usage: sudo ci/functional.sh
set -euo pipefail
. "$(dirname "$0")/lib.sh"

[[ ${EUID} -eq 0 ]] || fail "run as root: this applies the module to this machine"
. /etc/os-release
release="${ID}-${VERSION_ID}"
stock="${FIXTURES}/defaults/chrony.conf-${release}"
for f in "${FIXTURES}/chrony.conf-${release}" "${FIXTURES}/chrony.conf-${release}-params" \
	"${FIXTURES}/chrony.conf-${release}-server" "${stock}"; do
	[[ -f "${f}" ]] || fail "no fixture for ${release}: ${f}"
done
for cmd in "${MGMT}" dnf rpm2cpio cpio chronyc chronyd; do
	command -v "${cmd}" > /dev/null || fail "missing command: ${cmd}"
done

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

mp="$(module_path)"
CONF=/etc/chrony.conf

# Run a deploy until converged. The state directory (etcd data included) is
# --prefix inside $TMP, so the trap removes it; --tmp-prefix would leave
# 60-120 MB under /tmp per run, and a full /tmp makes etcd fail to start or
# makes mgmt converge on an empty graph before any resource runs. A run that
# does not converge within the timeout usually means chronyd rejects the
# rendered file and the service resource is retrying; see the log.
apply() {
	rm -rf "${TMP}/prefix"
	timeout 60 "${MGMT}" run --prefix "${TMP}/prefix" --converger-timeout=15 --converged-exit \
		--client-urls http://127.0.0.1:12379 --server-urls http://127.0.0.1:12380 \
		lang --module-path "${mp}" "$1" > "${TMP}/run.log" 2>&1 \
		|| { tail -30 "${TMP}/run.log"; journalctl -u chronyd --no-pager -n 5 -o cat; fail "mgmt run did not converge"; }
	grep -q -E "engine: [a-z]+\[" "${TMP}/run.log" \
		|| fail "mgmt converged without running any resource; check free space where ${TMP} lives"
}

# Apply the deploy fixture $1 and compare $CONF with fixtures/$2.
case_() {
	local name="$1" expected="${FIXTURES}/$2"
	echo "== ${name}"
	make_deploy "${TMP}/${name}" "${name}"
	apply "${TMP}/${name}/"
	diff "${expected}" "${CONF}" || {
		grep -E "engine: |error|converged" "${TMP}/run.log" | tail -15
		fail "${name}: ${CONF} differs from fixtures/$2 (see diff and log above)"
	}
	echo "ok: ${CONF} is byte-identical to fixtures/$2"
	systemctl is-active --quiet chronyd || fail "${name}: chronyd is not active"
}

# One-shot NTP query against our own chronyd, as the invoking user would run
# it: prints the measured offset and exits 0 if a server answered.
query_self() {
	timeout 20 chronyd -Q -t 5 "server 127.0.0.1 iburst" > "${TMP}/query.log" 2>&1
}

case_ params "chrony.conf-${release}-params"

case_ server "chrony.conf-${release}-server"
query_self || { cat "${TMP}/query.log"; fail "server: chronyd did not answer an NTP query from 127.0.0.1"; }
echo "ok: chronyd answers NTP queries from 127.0.0.1: $(grep -o 'System clock wrong by.*' "${TMP}/query.log")"

case_ defaults "chrony.conf-${release}"
if query_self; then cat "${TMP}/query.log"; fail "defaults: chronyd answered an NTP query although no allow directive is set"; fi
echo "ok: without allow, chronyd refuses NTP queries"

echo "== stored stock file against the package"
dnf -q download chrony --destdir "${TMP}" > /dev/null 2>&1 || fail "could not download the chrony rpm"
(cd "${TMP}" && rpm2cpio chrony-*.rpm | cpio -idm --quiet ./etc/chrony.conf)
diff "${stock}" "${TMP}/etc/chrony.conf" \
	|| fail "fixtures/defaults/$(basename "${stock}") is not the file shipped in $(rpm -q chrony); update it and the module's data (see diff above)"
echo "ok: fixtures/defaults/$(basename "${stock}") is byte-identical to the file in $(rpm -q chrony)"
diff <(directives "${stock}" | sort) <(directives "${CONF}" | sort) \
	|| fail "the rendered defaults do not have the directives of the stock file (see diff above)"
echo "ok: rendered defaults have exactly the stock file's directives (order aside)"

chronyc sources > /dev/null || fail "chronyc sources failed"
echo "ok: chronyd active and answering chronyc"

echo PASS
