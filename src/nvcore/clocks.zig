//! nvcore/clocks - GPU Clock Management
//!
//! Control GPU and memory clock speeds.

const std = @import("std");
const nvml = @import("../bindings/nvml.zig");

/// Clock configuration
pub const ClockConfig = struct {
    min_mhz: ?u32 = null,
    max_mhz: ?u32 = null,
};

/// Get current GPU clock speed
pub fn getGpuClock(device_index: u32) !u32 {
    const device = try nvml.getDeviceByIndex(device_index);
    return nvml.getDeviceClock(device, nvml.CLOCK_GRAPHICS);
}

/// Get current memory clock speed
pub fn getMemoryClock(device_index: u32) !u32 {
    const device = try nvml.getDeviceByIndex(device_index);
    return nvml.getDeviceClock(device, nvml.CLOCK_MEM);
}

/// Get current SM clock speed
pub fn getSmClock(device_index: u32) !u32 {
    const device = try nvml.getDeviceByIndex(device_index);
    return nvml.getDeviceClock(device, nvml.CLOCK_SM);
}

/// Get max GPU clock speed
pub fn getMaxGpuClock(device_index: u32) !u32 {
    const device = try nvml.getDeviceByIndex(device_index);
    return nvml.getDeviceMaxClock(device, nvml.CLOCK_GRAPHICS);
}

/// Get max memory clock speed
pub fn getMaxMemoryClock(device_index: u32) !u32 {
    const device = try nvml.getDeviceByIndex(device_index);
    return nvml.getDeviceMaxClock(device, nvml.CLOCK_MEM);
}

/// Clock speed summary
pub const ClockSummary = struct {
    gpu_current_mhz: u32,
    gpu_max_mhz: u32,
    mem_current_mhz: u32,
    mem_max_mhz: u32,
    sm_current_mhz: u32,
    video_current_mhz: u32,

    pub fn gpuPercent(self: ClockSummary) f32 {
        if (self.gpu_max_mhz == 0) return 0;
        return @as(f32, @floatFromInt(self.gpu_current_mhz)) / @as(f32, @floatFromInt(self.gpu_max_mhz)) * 100.0;
    }

    pub fn memPercent(self: ClockSummary) f32 {
        if (self.mem_max_mhz == 0) return 0;
        return @as(f32, @floatFromInt(self.mem_current_mhz)) / @as(f32, @floatFromInt(self.mem_max_mhz)) * 100.0;
    }
};

/// Get complete clock summary
pub fn getSummary(device_index: u32) !ClockSummary {
    const device = try nvml.getDeviceByIndex(device_index);

    return ClockSummary{
        .gpu_current_mhz = nvml.getDeviceClock(device, nvml.CLOCK_GRAPHICS) catch 0,
        .gpu_max_mhz = nvml.getDeviceMaxClock(device, nvml.CLOCK_GRAPHICS) catch 0,
        .mem_current_mhz = nvml.getDeviceClock(device, nvml.CLOCK_MEM) catch 0,
        .mem_max_mhz = nvml.getDeviceMaxClock(device, nvml.CLOCK_MEM) catch 0,
        .sm_current_mhz = nvml.getDeviceClock(device, nvml.CLOCK_SM) catch 0,
        .video_current_mhz = nvml.getDeviceClock(device, nvml.CLOCK_VIDEO) catch 0,
    };
}

// Note: Setting clocks requires nvidia-smi or direct NVML API calls that may need
// special permissions. The following are stubs for future implementation:

/// Set GPU clock range (requires elevated permissions)
pub fn setGpuClock(device_index: u32, config: ClockConfig) !void {
    _ = device_index;
    _ = config;
    // TODO: Implement via nvidia-smi or NVML clock lock APIs
    // nvmlDeviceSetGpuLockedClocks or nvidia-smi -lgc
    return error.NotSupported;
}

/// Set memory clock (requires elevated permissions)
pub fn setMemoryClock(device_index: u32, config: ClockConfig) !void {
    _ = device_index;
    _ = config;
    // TODO: Implement via nvidia-smi or NVML
    // nvmlDeviceSetMemoryLockedClocks or nvidia-smi -lmc
    return error.NotSupported;
}

/// Reset clocks to default
pub fn resetClocks(device_index: u32) !void {
    _ = device_index;
    // TODO: nvmlDeviceResetGpuLockedClocks / nvidia-smi -rgc
    return error.NotSupported;
}

test "clock summary" {
    const summary = ClockSummary{
        .gpu_current_mhz = 1500,
        .gpu_max_mhz = 2000,
        .mem_current_mhz = 9000,
        .mem_max_mhz = 10000,
        .sm_current_mhz = 1500,
        .video_current_mhz = 1400,
    };
    try std.testing.expectEqual(@as(f32, 75.0), summary.gpuPercent());
}
