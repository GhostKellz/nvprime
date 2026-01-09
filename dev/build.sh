#!/bin/bash
# NV* Stack Build Script - Run inside container
set -e

echo "=== NV* Stack Builder ==="

build_project() {
    local name=$1
    local dir=$2
    local cmd=${3:-"zig build -Doptimize=ReleaseFast"}

    echo ">>> Building $name..."
    cd /workspace/$dir
    eval $cmd
    echo "    $name OK"
}

case "${1:-all}" in
    nvvk)
        build_project "nvvk" "nvvk"
        ;;
    nvshader)
        build_project "nvshader" "nvshader" "zig build -Doptimize=ReleaseFast -Dlinkage=dynamic"
        ;;
    nvlatency)
        build_project "nvlatency" "nvlatency" "zig build -Doptimize=ReleaseFast -Dlinkage=dynamic"
        ;;
    nvsync)
        build_project "nvsync" "nvsync" "zig build -Doptimize=ReleaseFast -Dlinkage=dynamic"
        ;;
    nvhud)
        build_project "nvhud" "nvhud"
        ;;
    nvfury)
        build_project "nvfury" "nvfury"
        ;;
    nvprime)
        build_project "nvprime" "nvprime"
        ;;
    venom)
        build_project "venom" "venom"
        ;;
    nvproton)
        build_project "nvproton" "nvproton" "cargo build --release"
        ;;
    proton-nv)
        echo ">>> Building proton-NV (this takes hours)..."
        cd /workspace/proton-NV
        ./configure.sh
        make
        ;;
    all)
        build_project "nvvk" "nvvk"
        build_project "nvshader" "nvshader" "zig build -Doptimize=ReleaseFast -Dlinkage=dynamic"
        build_project "nvlatency" "nvlatency" "zig build -Doptimize=ReleaseFast -Dlinkage=dynamic"
        build_project "nvsync" "nvsync" "zig build -Doptimize=ReleaseFast -Dlinkage=dynamic"
        build_project "nvhud" "nvhud"
        build_project "nvfury" "nvfury"
        build_project "nvprime" "nvprime"
        build_project "venom" "venom"
        build_project "nvproton" "nvproton" "cargo build --release"
        echo ""
        echo "=== All builds complete ==="
        ;;
    *)
        echo "Usage: $0 [nvvk|nvshader|nvlatency|nvsync|nvhud|nvfury|nvprime|venom|nvproton|proton-nv|all]"
        exit 1
        ;;
esac
