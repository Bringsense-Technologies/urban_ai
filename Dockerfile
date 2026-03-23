# =============================================================================
# ARGUMENTS (Global Scope – available in FROM lines)
# =============================================================================
ARG BASE_IMAGE_URL=ubuntu:24.04

# =============================================================================
# STAGE 1: Downloader
# Downloads and verifies binary artifacts in a minimal layer, keeping wget/git
# out of the final runtime image.
# =============================================================================
FROM ubuntu:24.04 AS downloader
ARG CMAKE_VERSION
ARG TORCH_URL
# Optional SHA256 for LibTorch; if set, the download is verified.
ARG TORCH_SHA256=""
ARG REQUIRE_TORCH_SHA256=0
ARG EIGEN_VERSION
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    unzip \
    wget \
    && rm -rf /var/lib/apt/lists/*

# --- CMake: download and verify checksum from Kitware's own .sha256 file ---
WORKDIR /downloads
RUN wget -q "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.sh" \
    && wget -q "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.sh.sha256" \
    && sha256sum -c "cmake-${CMAKE_VERSION}-linux-x86_64.sh.sha256" \
    && bash "cmake-${CMAKE_VERSION}-linux-x86_64.sh" --skip-license --prefix=/opt/cmake \
    && rm "cmake-${CMAKE_VERSION}-linux-x86_64.sh" "cmake-${CMAKE_VERSION}-linux-x86_64.sh.sha256"

# --- LibTorch: download, verify if TORCH_SHA256 provided ---
RUN wget -q "${TORCH_URL}" -O libtorch.zip \
    && if [ -n "${TORCH_SHA256}" ]; then \
         echo "${TORCH_SHA256}  libtorch.zip" | sha256sum -c -; \
             elif [ "${REQUIRE_TORCH_SHA256}" = "1" ]; then \
                 echo "Error: TORCH_SHA256 is required but was not provided." >&2; \
                 exit 1; \
       else \
         echo "Warning: TORCH_SHA256 not set; skipping LibTorch checksum verification."; \
       fi \
    && unzip -q libtorch.zip -d /opt \
    && rm libtorch.zip

# --- Eigen: clone specific tag ---
RUN git clone --branch "${EIGEN_VERSION}" --depth 1 \
    https://gitlab.com/libeigen/eigen.git /opt/eigen \
    && rm -rf /opt/eigen/.git

# =============================================================================
# STAGE 2: Runtime image
# =============================================================================
FROM ${BASE_IMAGE_URL}
# Re-declare global ARG so it is visible in RUN commands of this stage.
ARG BASE_IMAGE_URL
ARG GCC_VERSION
ARG CMAKE_VERSION
ARG TORCH_URL
ARG TORCH_SHA256=""
ARG REQUIRE_TORCH_SHA256=0
ARG EIGEN_VERSION
ARG CCACHE_MAXSIZE="20G"
ARG SKIP_OS_UPGRADE=0
ARG DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.title="AI DevBox" \
    org.opencontainers.image.description="GPU-enabled C++ development stack based on NVIDIA DeepStream" \
    ai.devbox.base_image="${BASE_IMAGE_URL}" \
    ai.devbox.gcc_version="${GCC_VERSION}" \
    ai.devbox.cmake_version="${CMAKE_VERSION}" \
    ai.devbox.torch_url="${TORCH_URL}" \
    ai.devbox.torch_sha256="${TORCH_SHA256}" \
    ai.devbox.require_torch_sha256="${REQUIRE_TORCH_SHA256}" \
    ai.devbox.eigen_version="${EIGEN_VERSION}" \
    ai.devbox.ccache_maxsize="${CCACHE_MAXSIZE}"

RUN echo "Building AI Stack with:" && \
    echo "  Base: ${BASE_IMAGE_URL}" && \
    echo "  GCC:  ${GCC_VERSION}"

# -----------------------------------------------------------------------------
# 1. STABLE SYSTEM PACKAGES
# This layer rarely changes; it is cached across GCC/CMake/Torch bumps.
# Set SKIP_OS_UPGRADE=1 to bypass full-upgrade during build.
# -----------------------------------------------------------------------------
RUN apt-get update \
    && if [ "${SKIP_OS_UPGRADE}" != "1" ]; then apt-get -y full-upgrade; fi \
    && apt-get install -y --no-install-recommends \
    binutils \
    ccache \
    clang-format \
    gdb \
    gdbserver \
    gpg-agent \
    libopencv-dev \
    ninja-build \
    pkg-config \
    qbs \
    software-properties-common \
    wget \
    curl \
    ca-certificates \
    git \
    unzip \
    tar \
    && rm -rf /var/lib/apt/lists/*

RUN echo "Installed Qbs version: $(qbs --version | head -n 1)"

# -----------------------------------------------------------------------------
# 2. GCC (volatile layer – invalidates only when GCC_VERSION changes)
# -----------------------------------------------------------------------------
RUN add-apt-repository ppa:ubuntu-toolchain-r/test -y \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    gcc-${GCC_VERSION} \
    g++-${GCC_VERSION} \
    && rm -rf /var/lib/apt/lists/*

RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-${GCC_VERSION} 100 \
    && update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-${GCC_VERSION} 100

# ccache defaults (shared cache dir is mounted from docker-compose)
ENV CCACHE_DIR=/root/.ccache
ENV CCACHE_MAXSIZE=${CCACHE_MAXSIZE}
ENV PATH=/usr/lib/ccache:$PATH

# -----------------------------------------------------------------------------
# 3. COPY PRE-BUILT ARTIFACTS FROM DOWNLOADER STAGE
# Invalidates only when the corresponding ARG (CMAKE_VERSION / TORCH_URL /
# EIGEN_VERSION) changes, not on every image rebuild.
# -----------------------------------------------------------------------------
COPY --from=downloader /opt/cmake /usr/local
COPY --from=downloader /opt/libtorch /opt/libtorch
COPY --from=downloader /opt/eigen /opt/eigen

# Environment variables for C++ tooling
ENV Torch_DIR=/opt/libtorch
ENV LD_LIBRARY_PATH=/opt/libtorch/lib:$LD_LIBRARY_PATH

RUN printf '%s\n' \
    "AI_DEVBOX_BASE_IMAGE=${BASE_IMAGE_URL}" \
    "AI_DEVBOX_GCC_VERSION=${GCC_VERSION}" \
    "AI_DEVBOX_CMAKE_VERSION=${CMAKE_VERSION}" \
    "AI_DEVBOX_TORCH_URL=${TORCH_URL}" \
    "AI_DEVBOX_TORCH_SHA256=${TORCH_SHA256}" \
    "AI_DEVBOX_REQUIRE_TORCH_SHA256=${REQUIRE_TORCH_SHA256}" \
    "AI_DEVBOX_EIGEN_VERSION=${EIGEN_VERSION}" \
    "AI_DEVBOX_CCACHE_MAXSIZE=${CCACHE_MAXSIZE}" \
    > /etc/ai-devbox-release

# -----------------------------------------------------------------------------
# 4. ENTRYPOINT
# -----------------------------------------------------------------------------
RUN printf '%s\n' \
    'set print demangle on' \
    'set print asm-demangle on' \
    'set demangle-style gnu-v3' \
    > /root/.gdbinit

WORKDIR /root/project
# sleep infinity is more robust than tail -f /dev/null; it ignores signals
# that would otherwise terminate the container.
CMD ["sleep", "infinity"]

