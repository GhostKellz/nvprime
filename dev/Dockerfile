FROM archlinux:latest

# Update and install base development tools
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
    base-devel \
    git \
    rust \
    clang \
    llvm \
    cmake \
    meson \
    ninja \
    pkg-config \
    vulkan-devel \
    vulkan-tools \
    vulkan-validation-layers \
    shaderc \
    glslang \
    spirv-tools \
    libdrm \
    libxkbcommon \
    wayland \
    wayland-protocols \
    python \
    jq \
    ripgrep \
    fd \
    htop \
    xz \
    # NVIDIA userspace libraries and CUDA SDK (for nvml.h)
    nvidia-utils \
    cuda \
    && pacman -Scc --noconfirm

# Zig is mounted from host at /opt/zig
ENV PATH="/opt/zig:${PATH}"

WORKDIR /workspace
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

CMD ["/bin/bash"]
