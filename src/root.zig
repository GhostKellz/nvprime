//! NVPrime - Unified NVIDIA Linux Platform
//!
//! This is the root module that exports all NVPrime subsystems.
//! Each subsystem provides specific NVIDIA GPU functionality.
//!
//! ## Integrated Dependencies
//!
//! NVPrime integrates several standalone libraries:
//! - **nvvk** - Vulkan extension wrappers (via nvruntime.nvvulkan)
//! - **nvhud** - Performance overlay (via nvhud)
//! - **nvlatency** - Reflex/latency tools (via nvruntime.nvlatency)
//! - **nvsync** - VRR/G-Sync management (via nvdisplay.nvsync)
//! - **nvshader** - Shader cache management (via nvruntime.nvshader)
//! - **zeus** - GPU text rendering (via nvhud.text)
//! - **ghostvk** - High-performance Vulkan runtime (available via deps)

const std = @import("std");

// Core subsystems
pub const nvcaps = @import("nvcaps/nvcaps.zig");
pub const nvcore = @import("nvcore/nvcore.zig");
pub const nvpower = @import("nvpower/nvpower.zig");
pub const nvdisplay = @import("nvdisplay/nvdisplay.zig");

// Runtime subsystems (gaming stack)
pub const nvruntime = struct {
    /// NVIDIA Vulkan extensions (re-exports nvvk)
    pub const nvvulkan = @import("nvruntime/nvvulkan/nvvulkan.zig");
    /// NVIDIA Reflex & latency tools (re-exports nvlatency)
    pub const nvlatency = @import("nvruntime/nvlatency/nvlatency.zig");
    /// Shader cache management (re-exports nvshader)
    pub const nvshader = @import("nvruntime/nvshader/nvshader.zig");
    /// DXVK integration patches (uses nvvk)
    pub const nvdxvk = @import("nvruntime/nvdxvk/nvdxvk.zig");
    /// Wine/Proton integration
    pub const nvwine = @import("nvruntime/nvwine/nvwine.zig");
    /// PrimeTime gaming compositor
    pub const primetime = @import("nvruntime/primetime/primetime.zig");
    /// Game streaming (NVENC)
    pub const nvstream = @import("nvruntime/nvstream/nvstream.zig");
};

// AI/DLSS features
pub const nvdlss = @import("nvdlss/nvdlss.zig");

// Overlay and telemetry (re-exports nvhud)
pub const nvhud = @import("nvhud/nvhud.zig");

// System integration
pub const nvpkg = @import("nvpkg/nvpkg.zig");

// Low-level bindings
pub const nvml = @import("bindings/nvml.zig");

// Direct access to standalone libraries (for advanced use)
pub const deps = struct {
    pub const nvvk = @import("nvvk");
    pub const nvhud_lib = @import("nvhud");
    pub const nvlatency_lib = @import("nvlatency");
    pub const nvsync = @import("nvsync");
    pub const nvshader_lib = @import("nvshader");
    pub const zeus = @import("zeus");
    pub const ghostvk = @import("ghostvk");
};

// Version info
pub const version = struct {
    pub const major = 0;
    pub const minor = 1;
    pub const patch = 0;
    pub const string = "0.1.0-dev";
};

/// Initialize all NVPrime subsystems
pub fn init() !void {
    try nvml.init();
    try nvcaps.init();
}

/// Deinitialize all NVPrime subsystems
pub fn deinit() void {
    nvcaps.deinit();
    nvml.shutdown();
}

test "nvprime initialization" {
    // Basic smoke test
    _ = version.string;
}
