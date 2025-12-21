//! nvcore C API exports
//!
//! Provides C ABI-compatible functions for GPU core control (clocks, p-states, etc.)

const std = @import("std");
const nvprime = @import("nvprime");
const nvcore = nvprime.nvcore;
const nvml = nvprime.nvml;

/// C-compatible performance profile
pub const NvPerformanceProfile = enum(c_int) {
    maximum = 0,
    balanced = 1,
    efficient = 2,
    quiet = 3,
};

/// C-compatible core state
pub const NvCoreState = extern struct {
    gpu_clock_mhz: u32,
    mem_clock_mhz: u32,
    sm_clock_mhz: u32,
    video_clock_mhz: u32,
    pstate: u32,
    gpu_utilization: u32,
    mem_utilization: u32,
};

/// C-compatible clock limits
pub const NvClockLimits = extern struct {
    min_gpu_mhz: u32,
    max_gpu_mhz: u32,
    min_mem_mhz: u32,
    max_mem_mhz: u32,
    default_gpu_mhz: u32,
    default_mem_mhz: u32,
};

fn stateToC(state: nvcore.CoreState) NvCoreState {
    return NvCoreState{
        .gpu_clock_mhz = state.gpu_clock_mhz,
        .mem_clock_mhz = state.mem_clock_mhz,
        .sm_clock_mhz = state.sm_clock_mhz,
        .video_clock_mhz = state.video_clock_mhz,
        .pstate = state.pstate,
        .gpu_utilization = state.gpu_utilization,
        .mem_utilization = state.mem_utilization,
    };
}

fn limitsToC(limits: nvcore.ClockLimits) NvClockLimits {
    return NvClockLimits{
        .min_gpu_mhz = limits.min_gpu_mhz,
        .max_gpu_mhz = limits.max_gpu_mhz,
        .min_mem_mhz = limits.min_mem_mhz,
        .max_mem_mhz = limits.max_mem_mhz,
        .default_gpu_mhz = limits.default_gpu_mhz,
        .default_mem_mhz = limits.default_mem_mhz,
    };
}

// ============================================================================
// C ABI Exports
// ============================================================================

/// Get current core state
export fn nvprime_core_get_state(index: u32, out_state: *NvCoreState) c_int {
    const state = nvcore.getState(index) catch return -1;
    out_state.* = stateToC(state);
    return 0;
}

/// Get clock limits
export fn nvprime_core_get_clock_limits(index: u32, out_limits: *NvClockLimits) c_int {
    const limits = nvcore.getClockLimits(index) catch return -1;
    out_limits.* = limitsToC(limits);
    return 0;
}

/// Get GPU clock speed in MHz
export fn nvprime_core_get_gpu_clock(index: u32) c_int {
    const device = nvml.getDeviceByIndex(index) catch return -1;
    const clock = nvml.getDeviceClock(device, nvml.CLOCK_GRAPHICS) catch return -1;
    return @intCast(clock);
}

/// Get memory clock speed in MHz
export fn nvprime_core_get_mem_clock(index: u32) c_int {
    const device = nvml.getDeviceByIndex(index) catch return -1;
    const clock = nvml.getDeviceClock(device, nvml.CLOCK_MEM) catch return -1;
    return @intCast(clock);
}

/// Get SM clock speed in MHz
export fn nvprime_core_get_sm_clock(index: u32) c_int {
    const device = nvml.getDeviceByIndex(index) catch return -1;
    const clock = nvml.getDeviceClock(device, nvml.CLOCK_SM) catch return -1;
    return @intCast(clock);
}

/// Get video clock speed in MHz
export fn nvprime_core_get_video_clock(index: u32) c_int {
    const device = nvml.getDeviceByIndex(index) catch return -1;
    const clock = nvml.getDeviceClock(device, nvml.CLOCK_VIDEO) catch return -1;
    return @intCast(clock);
}

/// Get current P-state (0-15)
export fn nvprime_core_get_pstate(index: u32) c_int {
    const device = nvml.getDeviceByIndex(index) catch return -1;
    const pstate = nvml.getDevicePerformanceState(device) catch return -1;
    return @intCast(pstate);
}

/// Get GPU utilization percentage (0-100)
export fn nvprime_core_get_gpu_utilization(index: u32) c_int {
    const device = nvml.getDeviceByIndex(index) catch return -1;
    const util = nvml.getDeviceUtilization(device) catch return -1;
    return @intCast(util.gpu);
}

/// Get memory utilization percentage (0-100)
export fn nvprime_core_get_mem_utilization(index: u32) c_int {
    const device = nvml.getDeviceByIndex(index) catch return -1;
    const util = nvml.getDeviceUtilization(device) catch return -1;
    return @intCast(util.memory);
}

/// Get max GPU clock in MHz
export fn nvprime_core_get_max_gpu_clock(index: u32) c_int {
    const device = nvml.getDeviceByIndex(index) catch return -1;
    const clock = nvml.getDeviceMaxClock(device, nvml.CLOCK_GRAPHICS) catch return -1;
    return @intCast(clock);
}

/// Get max memory clock in MHz
export fn nvprime_core_get_max_mem_clock(index: u32) c_int {
    const device = nvml.getDeviceByIndex(index) catch return -1;
    const clock = nvml.getDeviceMaxClock(device, nvml.CLOCK_MEM) catch return -1;
    return @intCast(clock);
}

/// Get GPU clock percent for a profile
export fn nvprime_profile_gpu_clock_percent(profile: NvPerformanceProfile) u32 {
    const p: nvcore.PerformanceProfile = switch (profile) {
        .maximum => .maximum,
        .balanced => .balanced,
        .efficient => .efficient,
        .quiet => .quiet,
    };
    return p.getGpuClockPercent();
}

/// Get memory clock percent for a profile
export fn nvprime_profile_mem_clock_percent(profile: NvPerformanceProfile) u32 {
    const p: nvcore.PerformanceProfile = switch (profile) {
        .maximum => .maximum,
        .balanced => .balanced,
        .efficient => .efficient,
        .quiet => .quiet,
    };
    return p.getMemClockPercent();
}

/// Get power limit percent for a profile
export fn nvprime_profile_power_limit_percent(profile: NvPerformanceProfile) u32 {
    const p: nvcore.PerformanceProfile = switch (profile) {
        .maximum => .maximum,
        .balanced => .balanced,
        .efficient => .efficient,
        .quiet => .quiet,
    };
    return p.getPowerLimitPercent();
}
