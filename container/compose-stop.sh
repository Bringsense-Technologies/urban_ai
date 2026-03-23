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

cd "${REPO_ROOT}"

echo "Stopping compose service '${service}'"
docker compose stop "${service}"
