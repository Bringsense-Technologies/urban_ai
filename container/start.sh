#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: PROJECT_PREFIX=~/Development/MyProject $0 <number>"
  echo "Example: PROJECT_PREFIX=~/Development/MyProject $0 10"
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

number="$1"
if [[ ! "$number" =~ ^[0-9]+$ ]]; then
  echo "Error: <number> must be numeric (got: $number)" >&2
  exit 1
fi

if [[ -z "${PROJECT_PREFIX:-}" ]]; then
  echo "Error: PROJECT_PREFIX is not set" >&2
  usage
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker CLI not found in PATH" >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Error: cannot reach Docker daemon. Is Docker running and is your user in the docker group?" >&2
  exit 1
fi

if ! docker run --help 2>/dev/null | grep -q -- '--gpus'; then
  echo "Error: docker CLI does not support --gpus. Install/update NVIDIA Container Toolkit and Docker." >&2
  exit 1
fi

if ! docker image inspect ai-devbox:advanced >/dev/null 2>&1; then
  echo "Error: image 'ai-devbox:advanced' not found. Build it first: docker compose build advanced" >&2
  exit 1
fi

prefix_expanded="${PROJECT_PREFIX/#\~/$HOME}"
project_path="${prefix_expanded}${number}"
project_name_base="$(basename "$prefix_expanded")"
container_name="${project_name_base}${number}"

mkdir -p "$project_path"

if docker ps -a --format '{{.Names}}' | grep -Fxq "$container_name"; then
  echo "Error: container '$container_name' already exists" >&2
  echo "Remove it first (e.g. docker rm -f $container_name) or use another number." >&2
  exit 1
fi

docker run -d \
  --name "$container_name" \
  --restart unless-stopped \
  --gpus all \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -v "$project_path:/root/project" \
  -v ai-devbox-ccache:/root/.ccache \
  ai-devbox:advanced

echo "Started container: $container_name"
echo "Host path mapped to /root/project: $project_path"