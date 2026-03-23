#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  compose_service_usage "$0"
  exit 0
fi

require_docker_compose

service="${1:-advanced}"

cd "${REPO_ROOT}"

echo "Stopping compose service '${service}'"
docker compose stop "${service}"
