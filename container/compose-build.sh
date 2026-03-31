#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=container/lib.sh
source "${SCRIPT_DIR}/lib.sh"

usage() {
  cat <<'EOF'
Usage: ./container/compose-build.sh [compose-service] [--no-cache] [--pull]

Examples:
  ./container/compose-build.sh
  ./container/compose-build.sh advanced --pull
  ./container/compose-build.sh advanced --no-cache
EOF
}

service=""
declare -a build_args=()

for arg in "$@"; do
  case "${arg}" in
    -h|--help)
      usage
      exit 0
      ;;
    --no-cache|--pull)
      build_args+=("${arg}")
      ;;
    -* )
      echo "Error: unsupported option '${arg}'" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -n "${service}" ]]; then
        echo "Error: only one compose service can be provided" >&2
        usage >&2
        exit 1
      fi
      service="${arg}"
      ;;
  esac
done

if [[ -z "${service}" ]]; then
  service="advanced"
fi

require_docker_compose

cd "${REPO_ROOT}"

echo "Building compose service '${service}'"
if [[ ${#build_args[@]} -gt 0 ]]; then
  echo "Build options: ${build_args[*]}"
fi
echo "CCACHE_MAXSIZE=${CCACHE_MAXSIZE:-20G}"
echo "REQUIRE_TORCH_SHA256=${REQUIRE_TORCH_SHA256:-0}"

docker compose build "${build_args[@]}" "${service}"