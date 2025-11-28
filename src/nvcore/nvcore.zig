//! nvcore - GPU Fundamentals
//!
//! Low-level GPU control: clocks, p-states, boost, and voltage management.
//! This is the performance tuning core of NVPrime.

const std = @import("std");
const nvml = @import("../bindings/nvml.zig");

pub const clocks = @import("clocks.zig");
pub const pstates = @import("pstates.zig");
pub const boost = @import("boost.zig");
pub const voltage = @import("voltage.zig");

/// GPU core state snapshot
pub const CoreState = struct {
    gpu_clock_mhz: u32,
    mem_clock_mhz: u32,
    sm_clock_mhz: u32,
    video_clock_mhz: u32,
    pstate: u32,
    gpu_utilization: u32,
    mem_utilization: u32,

    pub fn print(self: CoreState, writer: anytype) !void {
        try writer.print("Core: GPU {d}MHz | MEM {d}MHz | SM {d}MHz | P{d} | Util: GPU {d}% MEM {d}%", .{
            self.gpu_clock_mhz,
            self.mem_clock_mhz,
            self.sm_clock_mhz,
            self.pstate,
            self.gpu_utilization,
            self.mem_utilization,
        });
    }
};

/// Get current core state for a GPU
pub fn getState(device_index: u32) !CoreState {
    const device = try nvml.getDeviceByIndex(device_index);

    const gpu_clock = nvml.getDeviceClock(device, nvml.CLOCK_GRAPHICS) catch 0;
    const mem_clock = nvml.getDeviceClock(device, nvml.CLOCK_MEM) catch 0;
    const sm_clock = nvml.getDeviceClock(device, nvml.CLOCK_SM) catch 0;
    const video_clock = nvml.getDeviceClock(device, nvml.CLOCK_VIDEO) catch 0;
    const pstate = nvml.getDevicePerformanceState(device) catch @as(c_uint, 15);
    const util = nvml.getDeviceUtilization(device) catch nvml.Utilization{ .gpu = 0, .memory = 0 };

    return CoreState{
        .gpu_clock_mhz = gpu_clock,
        .mem_clock_mhz = mem_clock,
        .sm_clock_mhz = sm_clock,
        .video_clock_mhz = video_clock,
        .pstate = @intCast(pstate),
        .gpu_utilization = util.gpu,
        .mem_utilization = util.memory,
    };
}

/// Clock limits structure
pub const ClockLimits = struct {
    min_gpu_mhz: u32,
    max_gpu_mhz: u32,
    min_mem_mhz: u32,
    max_mem_mhz: u32,
    default_gpu_mhz: u32,
    default_mem_mhz: u32,
};

/// Get clock limits for a GPU
pub fn getClockLimits(device_index: u32) !ClockLimits {
    const device = try nvml.getDeviceByIndex(device_index);

    // Get max supported clocks
    const max_gpu = nvml.getDeviceMaxClock(device, nvml.CLOCK_GRAPHICS) catch 0;
    const max_mem = nvml.getDeviceMaxClock(device, nvml.CLOCK_MEM) catch 0;

    // Estimate mins (NVML doesn't directly expose this for all cards)
    // Typically ~30-40% of max for idle states
    const min_gpu = max_gpu / 3;
    const min_mem = max_mem / 2;

    return ClockLimits{
        .min_gpu_mhz = min_gpu,
        .max_gpu_mhz = max_gpu,
        .min_mem_mhz = min_mem,
        .max_mem_mhz = max_mem,
        .default_gpu_mhz = max_gpu,
        .default_mem_mhz = max_mem,
    };
}

/// Performance profile for nvcore
pub const PerformanceProfile = enum {
    /// Maximum performance, no power saving
    maximum,
    /// Balanced performance and efficiency
    balanced,
    /// Favor efficiency over raw performance
    efficient,
    /// Quiet operation (lower clocks/power for reduced noise)
    quiet,

    pub fn getGpuClockPercent(self: PerformanceProfile) u32 {
        return switch (self) {
            .maximum => 100,
            .balanced => 85,
            .efficient => 70,
            .quiet => 60,
        };
    }

    pub fn getMemClockPercent(self: PerformanceProfile) u32 {
        return switch (self) {
            .maximum => 100,
            .balanced => 100,
            .efficient => 85,
            .quiet => 75,
        };
    }

    pub fn getPowerLimitPercent(self: PerformanceProfile) u32 {
        return switch (self) {
            .maximum => 100,
            .balanced => 90,
            .efficient => 75,
            .quiet => 65,
        };
    }
};

test "core state" {
    const state = CoreState{
        .gpu_clock_mhz = 1800,
        .mem_clock_mhz = 9000,
        .sm_clock_mhz = 1800,
        .video_clock_mhz = 1600,
        .pstate = 0,
        .gpu_utilization = 75,
        .mem_utilization = 45,
    };
    try std.testing.expectEqual(@as(u32, 1800), state.gpu_clock_mhz);
}
