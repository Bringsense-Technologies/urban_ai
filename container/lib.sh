#!/usr/bin/env bash
# Shared helpers for AI DevBox container scripts.
# Source this file; do not execute it directly.
#
# After sourcing, the following are available:
#   CONTAINER_DIR  – absolute path to the container/ directory
#   REPO_ROOT      – absolute path to the repository root
#   require_docker – validates docker CLI and compose plugin are available
#   compose_service_usage – prints standard service-selection usage

CONTAINER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${CONTAINER_DIR}/.." && pwd)"

require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "Error: docker CLI not found in PATH" >&2
    exit 1
  fi
  if ! docker compose version >/dev/null 2>&1; then
    echo "Error: Docker Compose plugin is not available." >&2
    exit 1
  fi
}

compose_service_usage() {
  local script="${1:-$0}"
  echo "Usage: ${script} [compose-service]"
  echo "Example: ${script} advanced"
  echo "If no service is provided, 'advanced' is used."
}
