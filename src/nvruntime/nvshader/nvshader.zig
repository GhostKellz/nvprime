//! nvruntime/nvshader - Shader Cache Management
//!
//! Re-exports the nvshader library for managing DXVK, vkd3d-proton,
//! and NVIDIA driver shader caches. Eliminates shader stutter.
//!
//! ## Features
//!
//! - **Cache Detection** - Auto-detect DXVK, vkd3d, Mesa, NVIDIA caches
//! - **Game Integration** - Steam, Lutris, Heroic game library support
//! - **Pre-warming** - Compile shaders before game launch
//! - **Cache Sharing** - Export/import shader caches between systems
//! - **Real-time Monitoring** - Watch shader compilation in real-time

const nvshader_lib = @import("nvshader");

// Re-export version
pub const version = nvshader_lib.version;

// Re-export sub-modules
pub const cache = nvshader_lib.cache;
pub const paths = nvshader_lib.paths;
pub const steam = nvshader_lib.steam;
pub const stats = nvshader_lib.stats;
pub const games = nvshader_lib.games;
pub const types = nvshader_lib.types;
pub const archive = nvshader_lib.archive;
pub const prewarm = nvshader_lib.prewarm;
pub const watch = nvshader_lib.watch;
pub const sharing = nvshader_lib.sharing;
pub const ipc = nvshader_lib.ipc;

// Re-export key types
pub const CacheType = nvshader_lib.CacheType;
pub const CacheStats = nvshader_lib.CacheStats;
pub const GpuInfo = nvshader_lib.GpuInfo;

/// Shader cache presets for different use cases
pub const CachePreset = enum {
    /// Default - standard cache behavior
    default,
    /// Gaming - aggressive caching, pre-warm enabled
    gaming,
    /// Minimal - small cache, frequent cleanup
    minimal,
    /// Performance - maximum caching, no size limits
    performance,

    pub fn description(self: CachePreset) []const u8 {
        return switch (self) {
            .default => "Standard cache behavior",
            .gaming => "Aggressive caching with pre-warming",
            .minimal => "Small cache with frequent cleanup",
            .performance => "Maximum caching, no limits",
        };
    }
};

/// Quick check: are there any shader caches on the system?
pub fn hasCaches() bool {
    // TODO: Check common cache locations like:
    // ~/.cache/dxvk/
    // ~/.cache/vkd3d-proton/
    // ~/.nv/ComputeCache/
    // ~/.cache/mesa_shader_cache/
    return true; // Optimistic default
}
