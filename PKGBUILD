# Maintainer: GhostKellz <ghost@ghostkellz.sh>
pkgname=nvprime
pkgver=1.0.0
pkgrel=1
pkgdesc="NVIDIA Platform Hub - Unified GPU control integrating nvvk/nvhud/nvlatency/nvsync"
arch=('x86_64')
url="https://github.com/ghostkellz/nvprime"
license=('MIT')
depends=('glibc' 'vulkan-icd-loader')
makedepends=('zig>=0.14')
optdepends=(
    'nvidia-utils: NVML GPU control and metrics'
    'nvvk: VK_NV_low_latency2 support'
    'nvhud: Performance overlay'
    'nvlatency: Reflex integration'
    'nvsync: VRR/G-Sync control'
    'nvshader: Shader cache management'
)
source=("$pkgname-$pkgver.tar.gz::$url/archive/v$pkgver.tar.gz")
sha256sums=('SKIP')

build() {
    cd "$pkgname-$pkgver"
    # Build without NVML if headers not available
    zig build -Doptimize=ReleaseFast -Dnvml=false
}

package() {
    cd "$pkgname-$pkgver"

    # CLI binary
    install -Dm755 zig-out/bin/nvprime "$pkgdir/usr/bin/nvprime"

    # Documentation
    install -Dm644 README.md "$pkgdir/usr/share/doc/$pkgname/README.md"
    install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
