//! nvpower/limits - Power Limit Management
//!
//! Control GPU power limits (TDP).

const std = @import("std");
const nvml = @import("../bindings/nvml.zig");

/// Power limit configuration
pub const PowerLimitConfig = struct {
    /// Power limit in watts
    watts: ?u32 = null,
    /// Power limit as percentage of default (0-100+)
    percent: ?u32 = null,
};

/// Power limit info
pub const PowerLimitInfo = struct {
    current_w: u32,
    default_w: u32,
    min_w: u32,
    max_w: u32,
    enforced_w: u32,

    pub fn currentPercent(self: PowerLimitInfo) u32 {
        if (self.default_w == 0) return 0;
        return self.current_w * 100 / self.default_w;
    }

    pub fn headroom(self: PowerLimitInfo) u32 {
        if (self.current_w >= self.max_w) return 0;
        return self.max_w - self.current_w;
    }
};

/// Get power limit info
pub fn getInfo(device_index: u32) !PowerLimitInfo {
    const device = try nvml.getDeviceByIndex(device_index);

    const limit = nvml.getDevicePowerLimit(device) catch 0;
    // NVML returns milliwatts
    const limit_w = limit / 1000;

    // Estimate min/max (typically 70-110% of default)
    return PowerLimitInfo{
        .current_w = limit_w,
        .default_w = limit_w, // TODO: query actual default
        .min_w = limit_w * 70 / 100,
        .max_w = limit_w * 110 / 100,
        .enforced_w = limit_w,
    };
}

/// Get current power limit in watts
pub fn get(device_index: u32) !u32 {
    const device = try nvml.getDeviceByIndex(device_index);
    const limit = try nvml.getDevicePowerLimit(device);
    return limit / 1000;
}

/// Get current power draw in watts
pub fn getPowerDraw(device_index: u32) !u32 {
    const device = try nvml.getDeviceByIndex(device_index);
    const power = try nvml.getDevicePowerUsage(device);
    return power / 1000;
}

/// Set power limit (requires root)
pub fn set(device_index: u32, config: PowerLimitConfig) !void {
    const device = try nvml.getDeviceByIndex(device_index);
    const info = try getInfo(device_index);

    var target_watts: u32 = undefined;

    if (config.watts) |w| {
        target_watts = w;
    } else if (config.percent) |p| {
        target_watts = info.default_w * p / 100;
    } else {
        return error.InvalidArgument;
    }

    // Clamp to valid range
    target_watts = @max(info.min_w, @min(target_watts, info.max_w));

    // NVML expects milliwatts
    try nvml.setDevicePowerLimit(device, target_watts * 1000);
}

/// Reset power limit to default
pub fn reset(device_index: u32) !void {
    const info = try getInfo(device_index);
    return set(device_index, .{ .watts = info.default_w });
}

/// Power limit presets
pub const PowerPreset = enum {
    /// Stock power limit
    stock,
    /// Reduced for efficiency (-20%)
    eco,
    /// Slightly reduced for quiet operation (-10%)
    quiet,
    /// Maximum allowed power limit
    maximum,

    pub fn percent(self: PowerPreset) u32 {
        return switch (self) {
            .stock => 100,
            .eco => 80,
            .quiet => 90,
            .maximum => 110,
        };
    }
};

/// Apply power preset
pub fn applyPreset(device_index: u32, preset: PowerPreset) !void {
    return set(device_index, .{ .percent = preset.percent() });
}

test "power limit info" {
    const info = PowerLimitInfo{
        .current_w = 250,
        .default_w = 300,
        .min_w = 200,
        .max_w = 350,
        .enforced_w = 250,
    };
    try std.testing.expectEqual(@as(u32, 83), info.currentPercent());
    try std.testing.expectEqual(@as(u32, 100), info.headroom());
}
