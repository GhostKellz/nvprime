//! nvcore/boost - GPU Boost Clock Management
//!
//! NVIDIA GPU Boost dynamically adjusts clock speeds based on power, thermals, and utilization.
//! This module provides control over boost behavior and offsets.

const std = @import("std");
const nvml = @import("../bindings/nvml.zig");

/// Boost state information
pub const BoostState = struct {
    /// Base clock (guaranteed minimum)
    base_clock_mhz: u32,
    /// Boost clock (rated maximum)
    boost_clock_mhz: u32,
    /// Current actual clock
    current_clock_mhz: u32,
    /// User-applied offset
    offset_mhz: i32,
    /// Whether thermal throttling is active
    thermal_throttle: bool,
    /// Whether power throttling is active
    power_throttle: bool,

    pub fn effectiveBoost(self: BoostState) u32 {
        const base: i32 = @intCast(self.boost_clock_mhz);
        const adjusted = base + self.offset_mhz;
        return if (adjusted > 0) @intCast(adjusted) else 0;
    }

    pub fn utilizationPercent(self: BoostState) f32 {
        if (self.boost_clock_mhz == 0) return 0;
        return @as(f32, @floatFromInt(self.current_clock_mhz)) /
            @as(f32, @floatFromInt(self.effectiveBoost())) * 100.0;
    }
};

/// Get current boost state
pub fn getState(device_index: u32) !BoostState {
    const device = try nvml.getDeviceByIndex(device_index);

    const current = nvml.getDeviceClock(device, nvml.CLOCK_GRAPHICS) catch 0;
    const max_clock = nvml.getDeviceMaxClock(device, nvml.CLOCK_GRAPHICS) catch 0;

    // Estimate base clock as ~70% of boost (typical ratio)
    const base = max_clock * 7 / 10;

    return BoostState{
        .base_clock_mhz = base,
        .boost_clock_mhz = max_clock,
        .current_clock_mhz = current,
        .offset_mhz = 0, // Would need to read from nvidia-settings or similar
        .thermal_throttle = false, // Would need throttle reason query
        .power_throttle = false,
    };
}

/// Clock offset configuration
pub const OffsetConfig = struct {
    /// GPU clock offset in MHz (can be negative)
    gpu_offset_mhz: i32 = 0,
    /// Memory clock offset in MHz (can be negative)
    mem_offset_mhz: i32 = 0,
};

/// Set clock offset (requires elevated permissions)
pub fn setOffset(device_index: u32, config: OffsetConfig) !void {
    _ = device_index;
    _ = config;
    // TODO: Implement via nvidia-settings or Coolbits
    // nvidia-settings -a "[gpu:0]/GPUGraphicsClockOffsetAllPerformanceLevels=100"
    return error.NotSupported;
}

/// Get current clock offset
pub fn getOffset(device_index: u32) !OffsetConfig {
    _ = device_index;
    // TODO: Query from nvidia-settings
    return OffsetConfig{
        .gpu_offset_mhz = 0,
        .mem_offset_mhz = 0,
    };
}

/// Reset clock offsets to default
pub fn resetOffset(device_index: u32) !void {
    return setOffset(device_index, .{
        .gpu_offset_mhz = 0,
        .mem_offset_mhz = 0,
    });
}

/// Boost profiles
pub const BoostProfile = enum {
    /// Default boost behavior
    default,
    /// Aggressive boost (higher clocks, more power)
    aggressive,
    /// Conservative boost (stable, lower thermals)
    conservative,
    /// Fixed boost (minimal dynamic adjustment)
    fixed,

    pub fn gpuOffset(self: BoostProfile) i32 {
        return switch (self) {
            .default => 0,
            .aggressive => 100,
            .conservative => -50,
            .fixed => 0,
        };
    }

    pub fn memOffset(self: BoostProfile) i32 {
        return switch (self) {
            .default => 0,
            .aggressive => 200,
            .conservative => 0,
            .fixed => 0,
        };
    }
};

/// Apply a boost profile
pub fn applyProfile(device_index: u32, profile: BoostProfile) !void {
    return setOffset(device_index, .{
        .gpu_offset_mhz = profile.gpuOffset(),
        .mem_offset_mhz = profile.memOffset(),
    });
}

test "boost state" {
    const state = BoostState{
        .base_clock_mhz = 1400,
        .boost_clock_mhz = 2000,
        .current_clock_mhz = 1800,
        .offset_mhz = 50,
        .thermal_throttle = false,
        .power_throttle = false,
    };
    try std.testing.expectEqual(@as(u32, 2050), state.effectiveBoost());
}
