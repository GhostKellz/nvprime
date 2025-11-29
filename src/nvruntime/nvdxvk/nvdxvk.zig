//! nvruntime/nvdxvk - NVIDIA DXVK Optimizations
//!
//! NVIDIA-specific DXVK optimizations and Reflex injection.
//! Uses nvvk for low-level Vulkan extension access.
//!
//! ## Features
//!
//! - **Reflex Injection** - Inject VK_NV_low_latency2 into DXVK
//! - **Shader Optimizations** - NVIDIA-specific shader paths
//! - **Async Compute** - Better async compute scheduling
//! - **State Cache** - Enhanced state cache with NVIDIA extensions

const std = @import("std");
const nvvk = @import("nvvk");

pub const version = "0.1.0-dev";

/// DXVK patch status
pub const PatchStatus = enum {
    not_applied,
    applied,
    outdated,
    incompatible,

    pub fn description(self: PatchStatus) []const u8 {
        return switch (self) {
            .not_applied => "NVIDIA patches not applied",
            .applied => "NVIDIA patches active",
            .outdated => "Patches need update",
            .incompatible => "DXVK version incompatible",
        };
    }
};

/// DXVK optimization level
pub const OptimizationLevel = enum {
    /// No NVIDIA-specific optimizations
    none,
    /// Basic optimizations (safe for all games)
    basic,
    /// Aggressive optimizations (may cause issues)
    aggressive,
    /// Maximum performance (experimental)
    experimental,

    pub fn description(self: OptimizationLevel) []const u8 {
        return switch (self) {
            .none => "No NVIDIA optimizations",
            .basic => "Safe optimizations for all games",
            .aggressive => "Aggressive (may cause issues)",
            .experimental => "Maximum performance (experimental)",
        };
    }
};

/// DXVK configuration for NVIDIA
pub const DxvkConfig = struct {
    /// Enable Reflex low-latency mode
    reflex_enabled: bool = true,
    /// Reflex mode (on/boost)
    reflex_mode: nvvk.low_latency.ModeConfig = .{ .enabled = true, .boost = false },
    /// Optimization level
    optimization_level: OptimizationLevel = .basic,
    /// Use async compute for supported operations
    async_compute: bool = true,
    /// Enable NVIDIA-specific shader paths
    nvidia_shaders: bool = true,
    /// Enable state cache enhancements
    enhanced_cache: bool = true,

    pub fn default() DxvkConfig {
        return .{};
    }

    pub fn lowLatency() DxvkConfig {
        return .{
            .reflex_enabled = true,
            .reflex_mode = .{ .enabled = true, .boost = true },
            .optimization_level = .aggressive,
            .async_compute = true,
            .nvidia_shaders = true,
            .enhanced_cache = true,
        };
    }

    pub fn compatibility() DxvkConfig {
        return .{
            .reflex_enabled = false,
            .reflex_mode = .{ .enabled = false, .boost = false },
            .optimization_level = .none,
            .async_compute = false,
            .nvidia_shaders = false,
            .enhanced_cache = false,
        };
    }
};

/// Get current patch status
pub fn getPatchStatus() PatchStatus {
    // TODO: Check DXVK installation and patch state
    return .not_applied;
}

/// Environment variables to set for DXVK with NVIDIA optimizations
pub const EnvVars = struct {
    /// Enable DXVK async shader compilation
    pub const DXVK_ASYNC = "DXVK_ASYNC";
    /// State cache path
    pub const DXVK_STATE_CACHE_PATH = "DXVK_STATE_CACHE_PATH";
    /// Log level
    pub const DXVK_LOG_LEVEL = "DXVK_LOG_LEVEL";
    /// HUD configuration
    pub const DXVK_HUD = "DXVK_HUD";
    /// Frame rate limit
    pub const DXVK_FRAME_RATE = "DXVK_FRAME_RATE";

    /// Get recommended env vars for a config
    pub fn forConfig(config: DxvkConfig) []const [2][]const u8 {
        _ = config;
        // TODO: Generate env vars based on config
        return &[_][2][]const u8{};
    }
};

/// DXVK version info
pub const DxvkVersion = struct {
    major: u32,
    minor: u32,
    patch: u32,
    is_async: bool,
    is_gplasync: bool,

    pub fn format(self: DxvkVersion, writer: anytype) !void {
        try writer.print("{d}.{d}.{d}", .{ self.major, self.minor, self.patch });
        if (self.is_async) try writer.writeAll("-async");
        if (self.is_gplasync) try writer.writeAll("-gplasync");
    }
};

/// Detect installed DXVK version
pub fn detectVersion() ?DxvkVersion {
    // TODO: Parse DXVK DLL/SO version info
    return null;
}

test "nvdxvk config" {
    const config = DxvkConfig.default();
    try std.testing.expect(config.reflex_enabled);
    try std.testing.expectEqual(OptimizationLevel.basic, config.optimization_level);
}

test "nvdxvk low latency config" {
    const config = DxvkConfig.lowLatency();
    try std.testing.expect(config.reflex_mode.boost);
    try std.testing.expectEqual(OptimizationLevel.aggressive, config.optimization_level);
}
