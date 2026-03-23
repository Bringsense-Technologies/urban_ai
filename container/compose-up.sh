#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [compose-service]"
  echo "Example: $0 advanced"
  echo "If no service is provided, 'advanced' is used."
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker CLI not found in PATH" >&2
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "Error: Docker Compose plugin is not available." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

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
