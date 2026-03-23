#!/usr/bin/env bash
set -euo pipefail

TARGET_VERSION="590"

# Skip installation if an NVIDIA driver at the target version or newer is already present.
if command -v nvidia-smi >/dev/null 2>&1; then
  installed="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null \
    | head -n 1 | cut -d. -f1 || true)"
  if [[ "${installed}" =~ ^[0-9]+$ && "${installed}" -ge "${TARGET_VERSION}" ]]; then
    echo "NVIDIA driver ${installed}.x already installed (target: ${TARGET_VERSION}). Skipping."
    exit 0
  fi
fi

# Refresh only Ubuntu default sources first (ignores broken third-party lists)
sudo apt-get update \
	-o Dir::Etc::sourcelist="sources.list" \
	-o Dir::Etc::sourceparts="-" \
	-o APT::Get::List-Cleanup="0"
sudo apt install -y "nvidia-driver-${TARGET_VERSION}-open" "nvidia-utils-${TARGET_VERSION}"
# REBOOT NOW
# sudo reboot

