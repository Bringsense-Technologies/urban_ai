#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=container/lib.sh
source "${SCRIPT_DIR}/lib.sh"

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  compose_service_usage "$0"
  exit 0
fi

require_docker

service="${1:-advanced}"
jobs="$(resolve_default_build_jobs)"

if [[ -z "${CMAKE_BUILD_PARALLEL_LEVEL:-}" ]]; then
  export CMAKE_BUILD_PARALLEL_LEVEL="${jobs}"
fi

if [[ -z "${AI_DEVBOX_BUILD_JOBS:-}" ]]; then
  export AI_DEVBOX_BUILD_JOBS="${jobs}"
fi

cd "${REPO_ROOT}"

echo "Starting compose service '${service}'"
echo "CMAKE_BUILD_PARALLEL_LEVEL=${CMAKE_BUILD_PARALLEL_LEVEL}"
echo "AI_DEVBOX_BUILD_JOBS=${AI_DEVBOX_BUILD_JOBS}"
echo "CCACHE_MAXSIZE=${CCACHE_MAXSIZE:-20G}"

docker compose up -d "${service}"
