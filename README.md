# AI DevBox (Docker + NVIDIA + VS Code)

This repository provides a GPU-enabled C++ development stack based on NVIDIA DeepStream, with:

- Two build targets (`stable` and `advanced`), with `stable` currently commented out in `docker-compose.yml`
- Project root mapped from host <project> to container `/root/project`
- C++ source folder mapped from host `<project>/source` to container `/root/project/source`
- VS Code Dev Container support (`.devcontainer/devcontainer.json`)
- Build system support for both CMake and Qbs projects
- C++ debugging support (`gdb`, `gdbserver`, `SYS_PTRACE`, `seccomp:unconfined`)
- C++ symbol demangling enabled by default in GDB
- Shared `ccache` volume across containers

## Table of contents

- [Workflow diagram](#workflow-diagram)
- [1. Prerequisites](#1-prerequisites)
- [2. Project layout expectation](#2-project-layout-expectation)
- [3. Build images](#3-build-images)
- [4. Launch container](#4-launch-container)
- [4.1 Compose (recommended)](#41-compose-recommended)
- [4.2 Equivalent `docker run`](#42-equivalent-docker-run)
- [4.3 Numbered project launcher script](#43-numbered-project-launcher-script)
- [5. Use from VS Code](#5-use-from-vs-code)
- [6. Debugging notes](#6-debugging-notes)
- [7. Build systems (CMake + Qbs)](#7-build-systems-cmake--qbs)
- [8. ccache (shared across containers)](#8-ccache-shared-across-containers)
- [9. Common commands](#9-common-commands)
- [10. Container runtime info helper](#10-container-runtime-info-helper)
- [11. Notes](#11-notes)

---

## Workflow diagram

```mermaid
flowchart LR
  A[Host prerequisites<br/>NVIDIA driver + Docker + Toolkit] --> B[Run setup scripts<br/>./setup/run.sh]
  B --> C[Build image<br/>docker compose build advanced]
  C --> D[Start container<br/>docker compose up -d advanced]
  D --> E[Open in VS Code Dev Container]
  E --> F[Build C++ project<br/>CMake or Qbs]
```

---

## 1. Prerequisites

- Linux host with NVIDIA GPU
- Docker Engine + Docker Compose plugin
- NVIDIA driver installed on host
- NVIDIA Container Toolkit installed and configured for Docker

### Optional helper scripts

You can run the scripts in `setup/`:

- `setup/01_nvidia_drivers.sh`
- `setup/02_docker.sh`
- `setup/03_nvidia_container_toolkit.sh`
- `setup/04_vscode_extensions.sh`

Or run them in order via the root helper:

- `./setup/run.sh`

Example:

```bash
chmod +x setup/run.sh setup/*.sh
./setup/run.sh
./setup/run.sh --dry-run

# or run steps manually
chmod +x setup/*.sh
./setup/01_nvidia_drivers.sh
# reboot if you installed/updated drivers
./setup/02_docker.sh
./setup/03_nvidia_container_toolkit.sh
./setup/04_vscode_extensions.sh
```

Verify GPU inside Docker:

```bash
docker run --rm --gpus all ubuntu:22.04 nvidia-smi
```

---

## 2. Project layout expectation

Your repository root should be:

```text
./
```

It is mounted into the container at:

```text
/root/project
```

Your C++ sources should typically be placed in:

```text
./source
```

Inside the container, this path is:

```text
/root/project/source
```

---

## 3. Build images

Build `advanced` (current active/default dev target):

```bash
docker compose build advanced
```

`stable` is currently commented out in `docker-compose.yml`.
To use it again, uncomment the `stable` service block first, then build:

```bash
docker compose build stable
```

---

## 4. Launch container

### 4.1 Compose (recommended)

Use the helper script (recommended):

```bash
bash ./container/compose-up.sh
```

It computes `(cores - 1)` (minimum `1`) and exports:

- `CMAKE_BUILD_PARALLEL_LEVEL`
- `AI_DEVBOX_BUILD_JOBS`

Then it runs `docker compose up -d advanced`.

You can select another service:

```bash
bash ./container/compose-up.sh advanced
```

Manual equivalent:

Compute conservative build parallelism (cores minus one, minimum one), then launch:

```bash
CORES="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1)"
CMAKE_BUILD_PARALLEL_LEVEL=$((CORES - 1))
if [[ "${CMAKE_BUILD_PARALLEL_LEVEL}" -lt 1 ]]; then CMAKE_BUILD_PARALLEL_LEVEL=1; fi
AI_DEVBOX_BUILD_JOBS="${CMAKE_BUILD_PARALLEL_LEVEL}"

export CMAKE_BUILD_PARALLEL_LEVEL AI_DEVBOX_BUILD_JOBS
docker compose up -d advanced
```

Quick override example:

```bash
CMAKE_BUILD_PARALLEL_LEVEL=6 AI_DEVBOX_BUILD_JOBS=6 docker compose up -d advanced
```

Open shell in running container:

```bash
docker exec -it ai-devbox-advanced /bin/bash
```

Stop it:

```bash
bash ./container/compose-stop.sh
```

Remove it:

```bash
bash ./container/compose-rm.sh
```

### 4.2 Equivalent `docker run`

If you prefer direct `docker run`, equivalent behavior is:

```bash
docker run -d \
  --name ai-devbox-advanced \
  --restart unless-stopped \
  --gpus all \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e CMAKE_BUILD_PARALLEL_LEVEL="${CMAKE_BUILD_PARALLEL_LEVEL:-1}" \
  -e AI_DEVBOX_BUILD_JOBS="${AI_DEVBOX_BUILD_JOBS:-1}" \
  -v "$PWD:/root/project" \
  -v ai-devbox-ccache:/root/.ccache \
  ai-devbox:advanced
```

Run this command from the repository root.

### 4.3 Numbered project launcher script

Use `container/start.sh` when you want multiple parallel checkouts of the same repo
like `~/Development/MyProject1`, `~/Development/MyProject2`, etc.

Make it executable:

```bash
chmod +x ./container/start.sh
```

Run it with `PROJECT_PREFIX` and an optional numeric suffix:

```bash
PROJECT_PREFIX=~/Development/MyProject ./container/start.sh 10
```

If no number is provided, it defaults to `1`:

```bash
PROJECT_PREFIX=~/Development/MyProject ./container/start.sh
```

This starts container `MyProject10` and maps:

- host: `~/Development/MyProject10`
- container: `/root/project`

If `PROJECT_PREFIX` is not set, the script uses your current directory as host path.

- Container name base is the current folder name.
- If the folder name ends with digits (for example `MyProject12`), that suffix is used.
- If the folder name has no trailing digits, suffix `1` is used.

Examples:

```bash
cd ~/Development/MyProject12
./container/start.sh
# starts container MyProject12 and maps ~/Development/MyProject12 -> /root/project

cd ~/Development/MyProject
./container/start.sh
# starts container MyProject1 and maps ~/Development/MyProject -> /root/project
```

Inside that container, C++ sources in the host checkout's `source/` folder are available at `/root/project/source`.

The launcher also sets conservative defaults for build parallelism to keep GUI hosts responsive:

- `CMAKE_BUILD_PARALLEL_LEVEL=(host cores - 1)`
- `AI_DEVBOX_BUILD_JOBS=(host cores - 1)`

Both values are clamped to a minimum of `1`, and can be overridden before launching:

```bash
CMAKE_BUILD_PARALLEL_LEVEL=6 AI_DEVBOX_BUILD_JOBS=6 PROJECT_PREFIX=~/Development/MyProject ./container/start.sh 10
```

---

## 5. Use from VS Code

1. Open this repository in VS Code.
2. Run: **Dev Containers: Rebuild and Reopen in Container**.
3. VS Code attaches to service `advanced` with workspace folder `/root/project`.

Dev Containers also loads `.devcontainer/docker-compose.devcontainer.yml`, which disables
container restart policy and healthcheck for the `advanced` service during editor attach.
This avoids reconnect loops and extension-install stalls in the remote container session.

Recommended extensions are configured automatically:

- `ms-vscode.cpptools`
- `ms-vscode.cmake-tools`
- `bierner.markdown-mermaid`

---

## 6. Debugging notes

This stack is preconfigured for container debugging:

- `gdb` and `gdbserver` installed in image
- `SYS_PTRACE` capability enabled
- `seccomp:unconfined` enabled
- GDB demangling defaults configured in `/root/.gdbinit`

So C++ symbols appear demangled during debugging sessions.

---

## 7. Build systems (CMake + Qbs)

This image supports both CMake- and Qbs-based C++ projects.

For interactive desktop use, prefer one less than total cores:

```bash
CORES="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1)"
JOBS=$((CORES - 1))
if [[ "${JOBS}" -lt 1 ]]; then JOBS=1; fi
```

If you start the container with `./container/start.sh`, this is already preconfigured via
`CMAKE_BUILD_PARALLEL_LEVEL` and `AI_DEVBOX_BUILD_JOBS`.

Check tool versions:

```bash
cmake --version
qbs --version
clang-format --version
```

### CMake quick start

Configure and build a Debug target:

```bash
cd /root/project
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build --parallel "${CMAKE_BUILD_PARALLEL_LEVEL:-$JOBS}"
```

Release build:

```bash
cmake -S . -B build-release -DCMAKE_BUILD_TYPE=Release
cmake --build build-release --parallel "${CMAKE_BUILD_PARALLEL_LEVEL:-$JOBS}"
```

### Qbs quick start

Create/update a profile (example using GCC):

```bash
qbs setup-toolchains --type gcc /usr/bin/g++ gcc
```

Configure and build a Debug target:

```bash
cd /root/project
qbs config defaultProfile gcc
qbs build -f your-project.qbs profile:gcc config:debug --jobs "${AI_DEVBOX_BUILD_JOBS:-$JOBS}"
```

Release build:

```bash
qbs build -f your-project.qbs profile:gcc config:release --jobs "${AI_DEVBOX_BUILD_JOBS:-$JOBS}"
```

---

## 8. ccache (shared across containers)

A named Docker volume is used:

- Volume name: `ai-devbox-ccache`
- Mounted at `/root/.ccache`

This means cache survives container recreation and is shared by services using the same volume.

Check cache stats:

```bash
ccache -s
```

Clear cache if needed:

```bash
ccache -C
```

---

## 9. Common commands

Bring up advanced service:

```bash
bash ./container/compose-up.sh
```

Rebuild advanced image:

```bash
docker compose build --no-cache advanced
```

View logs:

```bash
docker compose logs -f advanced
```

Stop advanced service:

```bash
bash ./container/compose-stop.sh
```

Remove advanced service:

```bash
bash ./container/compose-rm.sh
```

Stop all services:

```bash
docker compose down
```

Note: `stable` commands apply only after re-enabling the commented `stable` service in `docker-compose.yml`.

Stop services and remove shared cache volume:

```bash
docker compose down -v
```

---

## 10. Container runtime info helper

A helper script is available to detect container runtime and print container/image metadata:

```bash
./container/info.sh
```

Output includes:

- container name
- image name
- image SHA

By default, SHA is `unknown`. To provide it for compose launches:

Create `.env` from `.env.example` and set the values:

```bash
cp .env.example .env
```

Or export values directly in your shell:

```bash
export AI_DEVBOX_ADVANCED_SHA="$(docker image inspect ai-devbox:advanced --format '{{.Id}}')"
CORES="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1)"
export CMAKE_BUILD_PARALLEL_LEVEL=$((CORES - 1))
if [[ "${CMAKE_BUILD_PARALLEL_LEVEL}" -lt 1 ]]; then export CMAKE_BUILD_PARALLEL_LEVEL=1; fi
export AI_DEVBOX_BUILD_JOBS="${CMAKE_BUILD_PARALLEL_LEVEL}"
docker compose up -d advanced
```

You can do the same for `stable` using `AI_DEVBOX_STABLE_SHA`.

---

## 11. Notes

- Container working directory is `/root/project`.
- If NVIDIA runtime fails, recheck driver/toolkit installation and restart Docker.
- If image tags (DeepStream/LibTorch) change upstream, update build args in `docker-compose.yml`.
