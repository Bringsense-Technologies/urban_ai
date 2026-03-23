#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: ./source/format-code.sh [--changed]

Options:
	--changed   Format only changed and untracked files under source/.
EOF
}

mode="all"
if [[ ${1:-} == "--changed" ]]; then
	mode="changed"
	shift
fi

if [[ $# -gt 0 ]]; then
	usage >&2
	exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_DIR="${REPO_ROOT}/source"
STYLE_FILE=""

if [[ "$PWD" != "${REPO_ROOT}" && "$PWD" != "${SOURCE_DIR}" ]]; then
	echo "Run this script from ${REPO_ROOT} or ${SOURCE_DIR}." >&2
	exit 1
fi

if ! command -v clang-format >/dev/null 2>&1; then
	echo "clang-format is not installed or not available in PATH." >&2
	exit 1
fi

if [[ -f "${REPO_ROOT}/.clang-format" ]]; then
	STYLE_FILE="${REPO_ROOT}/.clang-format"
elif [[ -f "${SOURCE_DIR}/.clang-format" ]]; then
	STYLE_FILE="${SOURCE_DIR}/.clang-format"
else
	echo "Missing .clang-format in ${REPO_ROOT} or ${SOURCE_DIR}" >&2
	exit 1
fi

declare -a files=()

if [[ "${mode}" == "changed" ]]; then
	if ! command -v git >/dev/null 2>&1; then
		echo "git is required for --changed mode." >&2
		exit 1
	fi

	git_diff_target="HEAD"
	if ! git -C "${REPO_ROOT}" rev-parse --verify HEAD >/dev/null 2>&1; then
		git_diff_target="$(git hash-object -t tree /dev/null)"
	fi

	mapfile -t candidates < <(
		{
			git -C "${REPO_ROOT}" diff --name-only --diff-filter=ACMR "${git_diff_target}" -- source
			git -C "${REPO_ROOT}" ls-files --others --exclude-standard -- source
		} | awk '!seen[$0]++'
	)

	for candidate in "${candidates[@]}"; do
		case "${candidate}" in
			source/*.c|source/*.cc|source/*.cpp|source/*.cxx|source/*.h|source/*.hh|source/*.hpp|source/*.hxx)
				if [[ -f "${REPO_ROOT}/${candidate}" ]]; then
					files+=("${REPO_ROOT}/${candidate}")
				fi
				;;
		esac
	done
else
	mapfile -t files < <(find "${SOURCE_DIR}" -type f \( -name "*.c" -o -name "*.cc" -o -name "*.cpp" -o -name "*.cxx" -o -name "*.h" -o -name "*.hh" -o -name "*.hpp" -o -name "*.hxx" \) | LC_ALL=C sort)
fi

if [[ ${#files[@]} -eq 0 ]]; then
	echo "No source files matched for formatting."
	exit 0
fi

echo "Using style file: ${STYLE_FILE}"
clang-format -i -style=file "${files[@]}"
echo "Formatted ${#files[@]} file(s)."

