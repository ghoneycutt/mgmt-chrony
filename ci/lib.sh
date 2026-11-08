# Shared helpers for the ci/ scripts. Source, do not run.

# The import URL consumers use, and the directory mgmt derives from it under a
# module path.
MODULE_URL="https://github.com/ghoneycutt/mgmt-chrony/"
MODULE_DIR="github.com/ghoneycutt/mgmt-chrony"

MGMT="${MGMT:-mgmt}"
CI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "${CI}")"
FIXTURES="${CI}/fixtures"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

# Strip comments and blank lines from a chrony.conf: what chrony actually reads.
directives() {
	grep -v -e '^#' -e '^$' "$1"
}

# Print a module path that resolves $MODULE_URL to this working tree. If
# MGMT_MODULE_PATH is set, it is used as is and must already hold this working
# tree at $MODULE_DIR (a checkout or a mount at that location). Otherwise a
# temporary module path is built with a copy of the working tree, so the test
# sees uncommitted changes and nothing outside the temp dir is touched.
module_path() {
	if [[ -n "${MGMT_MODULE_PATH:-}" ]]; then
		[[ -f "${MGMT_MODULE_PATH}${MODULE_DIR}/metadata.yaml" ]] \
			|| fail "MGMT_MODULE_PATH=${MGMT_MODULE_PATH} does not contain ${MODULE_DIR}/"
		echo "${MGMT_MODULE_PATH}"
		return
	fi
	# mgmt requires the last component to be named modules/.
	local mp="${TMP}/modules/"
	mkdir -p "${mp}$(dirname "${MODULE_DIR}")"
	cp -R "${REPO}" "${mp}${MODULE_DIR}"
	echo "${mp}"
}

# Build the deploy directory $1 from the fixture fixtures/deploy-$2.mcl: an
# empty metadata.yaml next to the fixture as main.mcl.
make_deploy() {
	local dir="$1" name="$2"
	mkdir -p "${dir}"
	: > "${dir}/metadata.yaml"
	cp "${FIXTURES}/deploy-${name}.mcl" "${dir}/main.mcl"
}
