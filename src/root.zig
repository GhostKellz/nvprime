//! NVPrime - Unified NVIDIA Linux Platform
//!
//! This is the root module that exports all NVPrime subsystems.
//! Each subsystem provides specific NVIDIA GPU functionality.

const std = @import("std");

// Core subsystems
pub const nvcaps = @import("nvcaps/nvcaps.zig");
pub const nvcore = @import("nvcore/nvcore.zig");
pub const nvpower = @import("nvpower/nvpower.zig");
pub const nvdisplay = @import("nvdisplay/nvdisplay.zig");

// Runtime subsystems (gaming stack)
pub const nvruntime = struct {
    pub const nvvulkan = @import("nvruntime/nvvulkan/nvvulkan.zig");
    pub const nvdxvk = @import("nvruntime/nvdxvk/nvdxvk.zig");
    pub const nvwine = @import("nvruntime/nvwine/nvwine.zig");
    pub const primetime = @import("nvruntime/primetime/primetime.zig");
    pub const nvstream = @import("nvruntime/nvstream/nvstream.zig");
};

// AI/DLSS features
pub const nvdlss = @import("nvdlss/nvdlss.zig");

// Overlay and telemetry
pub const nvhud = @import("nvhud/nvhud.zig");

// System integration
pub const nvpkg = @import("nvpkg/nvpkg.zig");

// Low-level bindings
pub const nvml = @import("bindings/nvml.zig");

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
