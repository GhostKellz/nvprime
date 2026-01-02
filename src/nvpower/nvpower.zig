//! nvpower - Power & Thermal Management
//!
//! Control power limits, thermal targets, and fan curves.
//! This is the thermal/power management core of NVPrime.

const std = @import("std");
const nvml = @import("../bindings/nvml.zig");

pub const limits = @import("limits.zig");
pub const thermals = @import("thermals.zig");
pub const fans = @import("fans.zig");
pub const efficiency = @import("efficiency.zig");

/// Complete power/thermal state
pub const PowerState = struct {
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
    fan_mode: FanMode,

    pub fn print(self: PowerState, writer: anytype) !void {
        try writer.print("Power: {d:.1}W / {d:.1}W ({d:.0}%)\n", .{
            self.power_draw_w,
            self.power_limit_w,
            self.power_draw_w / self.power_limit_w * 100,
        });
        try writer.print("Temps: GPU {d}C | MEM {d}C | Hot {d}C (target {d}C)\n", .{
            self.gpu_temp_c,
            self.memory_temp_c,
            self.hotspot_temp_c,
            self.thermal_target_c,
        });
        try writer.print("Fans: {d}% ({d} RPM) - {s}\n", .{
            self.fan_speed_percent,
            self.fan_speed_rpm,
            @tagName(self.fan_mode),
        });
    }

    pub fn isThermalThrottling(self: PowerState) bool {
        return self.gpu_temp_c >= self.thermal_slowdown_c;
    }

    pub fn isPowerThrottling(self: PowerState) bool {
        return self.power_draw_w >= self.power_limit_w * 0.98;
    }
};

/// Fan operation mode
pub const FanMode = enum {
    auto, // GPU controls fan speed
    manual, // User-defined speed
    curve, // Custom fan curve
    zero_rpm, // Zero RPM mode when cool enough
};

/// Get current power state
pub fn getState(device_index: u32) !PowerState {
    const device = try nvml.getDeviceByIndex(device_index);

    // Get power info from limits module
    const power_info = limits.getInfo(device_index) catch limits.PowerLimitInfo{
        .current_w = 0,
        .default_w = 0,
        .min_w = 0,
        .max_w = 0,
        .enforced_w = 0,
    };

    // Get thermal info from thermals module
    const thermal_state = thermals.getState(device_index) catch thermals.ThermalState{
        .gpu_temp_c = 0,
        .memory_temp_c = 0,
        .hotspot_temp_c = 0,
        .target_temp_c = 83,
        .slowdown_temp_c = 83,
        .shutdown_temp_c = 92,
    };

    // Get fan info from fans module
    const fan_state = fans.getState(device_index) catch fans.FanState{
        .speed_percent = 0,
        .speed_rpm = 0,
        .target_percent = 0,
        .mode = .auto,
        .fan_count = 1,
    };

    const power = nvml.getDevicePowerUsage(device) catch 0;

    return PowerState{
        .power_draw_w = @as(f32, @floatFromInt(power)) / 1000.0,
        .power_limit_w = @as(f32, @floatFromInt(power_info.current_w)),
        .power_limit_default_w = @as(f32, @floatFromInt(power_info.default_w)),
        .power_limit_min_w = @as(f32, @floatFromInt(power_info.min_w)),
        .power_limit_max_w = @as(f32, @floatFromInt(power_info.max_w)),
        .gpu_temp_c = thermal_state.gpu_temp_c,
        .memory_temp_c = thermal_state.memory_temp_c,
        .hotspot_temp_c = thermal_state.hotspot_temp_c,
        .thermal_target_c = thermal_state.target_temp_c,
        .thermal_slowdown_c = thermal_state.slowdown_temp_c,
        .thermal_shutdown_c = thermal_state.shutdown_temp_c,
        .fan_speed_percent = fan_state.speed_percent,
        .fan_speed_rpm = fan_state.speed_rpm,
        .fan_target_percent = fan_state.target_percent,
        .fan_mode = .auto,
    };
}

/// Quick power check
pub const PowerHealth = enum {
    optimal, // Well under limits
    moderate, // Approaching limits
    throttling, // At limits
    critical, // Thermal emergency
};

pub fn getHealthStatus(device_index: u32) !PowerHealth {
    const state = try getState(device_index);

    if (state.gpu_temp_c >= state.thermal_shutdown_c - 5) {
        return .critical;
    }
    if (state.isThermalThrottling() or state.isPowerThrottling()) {
        return .throttling;
    }
    if (state.gpu_temp_c >= state.thermal_target_c - 10 or
        state.power_draw_w >= state.power_limit_w * 0.85)
    {
        return .moderate;
    }
    return .optimal;
}

/// Power efficiency mode
pub const EfficiencyMode = enum {
    performance, // Full power, maximum clocks
    balanced, // Default behavior
    quiet, // Reduced power for silent operation
    efficiency, // Maximum power savings

    pub fn powerLimitPercent(self: EfficiencyMode) u32 {
        return switch (self) {
            .performance => 100,
            .balanced => 90,
            .quiet => 70,
            .efficiency => 60,
        };
    }

    pub fn thermalTarget(self: EfficiencyMode) u32 {
        return switch (self) {
            .performance => 85,
            .balanced => 83,
            .quiet => 75,
            .efficiency => 70,
        };
    }
};

test "power state" {
    const state = PowerState{
        .power_draw_w = 250,
        .power_limit_w = 300,
        .power_limit_default_w = 300,
        .power_limit_min_w = 200,
        .power_limit_max_w = 350,
        .gpu_temp_c = 72,
        .memory_temp_c = 68,
        .hotspot_temp_c = 75,
        .thermal_target_c = 83,
        .thermal_slowdown_c = 83,
        .thermal_shutdown_c = 92,
        .fan_speed_percent = 50,
        .fan_speed_rpm = 1500,
        .fan_target_percent = 50,
        .fan_mode = .auto,
    };
    try std.testing.expect(!state.isThermalThrottling());
    try std.testing.expect(!state.isPowerThrottling());
}
