#!/usr/bin/env bash
# Compile check: lex, parse, resolve imports and run type unification over
# every way this module is used. Catches a type mismatch or a broken import
# before anything runs. Needs mgmt, no root.
#
# Note: a misspelled field (server instead of servers) is NOT a compile error
# on mgmt 1.1.0, because the class parameter's type is inferred from the
# argument. It is silently ignored, so there is nothing to assert for it.
#
# Usage: ci/check.sh
set -euo pipefail
. "$(dirname "$0")/lib.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

mp="$(module_path)"

check() {
	"${MGMT}" check --tmp-prefix lang --module-path "${mp}" "$@" > "${TMP}/out" 2>&1
}

for name in defaults params server; do
	make_deploy "${TMP}/${name}" "${name}"
	check "${TMP}/${name}/" || { cat "${TMP}/out"; fail "fixtures/deploy-${name}.mcl: does not compile"; }
	echo "ok: fixtures/deploy-${name}.mcl"
done

for f in "${REPO}"/examples/*.mcl; do
	check "${f}" || { cat "${TMP}/out"; fail "$(basename "${f}"): does not compile"; }
	echo "ok: examples/$(basename "${f}")"
done

# The module's expected default output for each release must have exactly the
# directives of that release's stock file in fixtures/defaults/, order aside:
# the module writes them in the manual's order, the distribution in its own,
# and chrony does not care. Pure text, so it runs everywhere; functional.sh
# proves the stock file against the package.
for stock in "${FIXTURES}"/defaults/chrony.conf-*; do
	release="${stock##*/chrony.conf-}"
	expected="${FIXTURES}/chrony.conf-${release}"
	[[ -f "${expected}" ]] || fail "fixtures/defaults/chrony.conf-${release} has no fixtures/chrony.conf-${release}"
	diff <(directives "${stock}" | sort) <(directives "${expected}" | sort) \
		|| fail "fixtures/chrony.conf-${release} does not render the directives of the stock file (see diff above)"
	echo "ok: ${release} defaults match fixtures/defaults/chrony.conf-${release}"
done

echo PASS
