#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  compose_service_usage "$0"
  exit 0
fi

require_docker

service="${1:-advanced}"

cores="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1)"
if [[ ! "${cores}" =~ ^[0-9]+$ || "${cores}" -lt 1 ]]; then
  cores=1
fi

jobs=$((cores - 1))
if [[ "${jobs}" -lt 1 ]]; then
  jobs=1
fi

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

docker compose up -d "${service}"
