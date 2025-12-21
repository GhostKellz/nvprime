//! nvpower C API exports
//!
//! Provides C ABI-compatible functions for power and thermal management.

const std = @import("std");
const nvprime = @import("nvprime");
const nvpower = nvprime.nvpower;
const nvml = nvprime.nvml;

/// C-compatible fan mode
pub const NvFanMode = enum(c_int) {
    auto = 0,
    manual = 1,
    curve = 2,
    zero_rpm = 3,
};

/// C-compatible power health status
pub const NvPowerHealth = enum(c_int) {
    optimal = 0,
    moderate = 1,
    throttling = 2,
    critical = 3,
};

/// C-compatible efficiency mode
pub const NvEfficiencyMode = enum(c_int) {
    performance = 0,
    balanced = 1,
    quiet = 2,
    efficiency = 3,
};

/// C-compatible power state structure
pub const NvPowerState = extern struct {
    // Power
    power_draw_w: f32,
    power_limit_w: f32,
    power_limit_default_w: f32,
    power_limit_min_w: f32,
    power_limit_max_w: f32,

    // Thermals
    gpu_temp_c: u32,
    memory_temp_c: u32,
    hotspot_temp_c: u32,
    thermal_target_c: u32,
    thermal_slowdown_c: u32,
    thermal_shutdown_c: u32,

    // Fans
    fan_speed_percent: u32,
    fan_speed_rpm: u32,
    fan_target_percent: u32,
    fan_mode: NvFanMode,
};

fn stateToC(state: nvpower.PowerState) NvPowerState {
    return NvPowerState{
        .power_draw_w = state.power_draw_w,
        .power_limit_w = state.power_limit_w,
        .power_limit_default_w = state.power_limit_default_w,
        .power_limit_min_w = state.power_limit_min_w,
        .power_limit_max_w = state.power_limit_max_w,
        .gpu_temp_c = state.gpu_temp_c,
        .memory_temp_c = state.memory_temp_c,
        .hotspot_temp_c = state.hotspot_temp_c,
        .thermal_target_c = state.thermal_target_c,
        .thermal_slowdown_c = state.thermal_slowdown_c,
        .thermal_shutdown_c = state.thermal_shutdown_c,
        .fan_speed_percent = state.fan_speed_percent,
        .fan_speed_rpm = state.fan_speed_rpm,
        .fan_target_percent = state.fan_target_percent,
        .fan_mode = switch (state.fan_mode) {
            .auto => .auto,
            .manual => .manual,
            .curve => .curve,
            .zero_rpm => .zero_rpm,
        },
    };
}

// ============================================================================
// C ABI Exports
// ============================================================================

/// Get current power/thermal state
export fn nvprime_power_get_state(index: u32, out_state: *NvPowerState) c_int {
    const state = nvpower.getState(index) catch return -1;
    out_state.* = stateToC(state);
    return 0;
}

/// Get power health status
export fn nvprime_power_get_health(index: u32) NvPowerHealth {
    const health = nvpower.getHealthStatus(index) catch return .critical;
    return switch (health) {
        .optimal => .optimal,
        .moderate => .moderate,
        .throttling => .throttling,
        .critical => .critical,
    };
}

/// Check if GPU is thermal throttling
export fn nvprime_power_is_thermal_throttling(index: u32) bool {
    const state = nvpower.getState(index) catch return false;
    return state.isThermalThrottling();
}

/// Check if GPU is power throttling
export fn nvprime_power_is_power_throttling(index: u32) bool {
    const state = nvpower.getState(index) catch return false;
    return state.isPowerThrottling();
}

/// Get current power draw in watts
export fn nvprime_power_get_power_draw(index: u32) f32 {
    const device = nvml.getDeviceByIndex(index) catch return -1.0;
    const power = nvml.getDevicePowerUsage(device) catch return -1.0;
    return @as(f32, @floatFromInt(power)) / 1000.0;
}

/// Get current power limit in watts
export fn nvprime_power_get_power_limit(index: u32) f32 {
    const device = nvml.getDeviceByIndex(index) catch return -1.0;
    const limit = nvml.getDevicePowerLimit(device) catch return -1.0;
    return @as(f32, @floatFromInt(limit)) / 1000.0;
}

/// Set power limit in milliwatts (requires root/admin)
export fn nvprime_power_set_power_limit(index: u32, limit_mw: u32) c_int {
    const device = nvml.getDeviceByIndex(index) catch return -1;
    nvml.setDevicePowerLimit(device, limit_mw) catch return -2;
    return 0;
}

/// Get GPU temperature in Celsius
export fn nvprime_power_get_temperature(index: u32) c_int {
    const device = nvml.getDeviceByIndex(index) catch return -1;
    const temp = nvml.getDeviceTemperature(device, nvml.TEMPERATURE_GPU) catch return -1;
    return @intCast(temp);
}

/// Get fan speed percentage (0-100)
export fn nvprime_power_get_fan_speed(index: u32) c_int {
    const device = nvml.getDeviceByIndex(index) catch return -1;
    const speed = nvml.getDeviceFanSpeed(device) catch return -1;
    return @intCast(speed);
}

/// Get efficiency mode power limit percentage
export fn nvprime_efficiency_power_percent(mode: NvEfficiencyMode) u32 {
    const m: nvpower.EfficiencyMode = switch (mode) {
        .performance => .performance,
        .balanced => .balanced,
        .quiet => .quiet,
        .efficiency => .efficiency,
    };
    return m.powerLimitPercent();
}

/// Get efficiency mode thermal target
export fn nvprime_efficiency_thermal_target(mode: NvEfficiencyMode) u32 {
    const m: nvpower.EfficiencyMode = switch (mode) {
        .performance => .performance,
        .balanced => .balanced,
        .quiet => .quiet,
        .efficiency => .efficiency,
    };
    return m.thermalTarget();
}
