//! nvpower/fans - Fan Control
//!
//! Fan speed management and custom fan curves.

const std = @import("std");
const nvml = @import("../bindings/nvml.zig");

/// Fan state
pub const FanState = struct {
    speed_percent: u32,
    speed_rpm: u32,
    target_percent: u32,
    mode: FanMode,
    fan_count: u32,
};

/// Fan operation mode
pub const FanMode = enum {
    auto, // GPU controls fan speed
    manual, // User-defined constant speed
    curve, // Custom temperature-based curve
    zero_rpm, // Allow zero RPM when cool

    pub fn description(self: FanMode) []const u8 {
        return switch (self) {
            .auto => "Automatic (GPU controlled)",
            .manual => "Manual (fixed speed)",
            .curve => "Custom fan curve",
            .zero_rpm => "Zero RPM mode enabled",
        };
    }
};

/// Get current fan state
pub fn getState(device_index: u32) !FanState {
    const device = try nvml.getDeviceByIndex(device_index);
    const speed = nvml.getDeviceFanSpeed(device) catch 0;

    return FanState{
        .speed_percent = speed,
        .speed_rpm = 0, // TODO: query if available
        .target_percent = speed,
        .mode = .auto,
        .fan_count = 1, // TODO: query actual fan count
    };
}

/// Get fan speed percentage
pub fn getSpeed(device_index: u32) !u32 {
    const device = try nvml.getDeviceByIndex(device_index);
    return nvml.getDeviceFanSpeed(device);
}

/// Set manual fan speed (requires elevated permissions + Coolbits)
pub fn setSpeed(device_index: u32, speed_percent: u32) !void {
    _ = device_index;
    _ = speed_percent;
    // NVML doesn't support fan speed setting on consumer cards
    // Would need nvidia-settings with Coolbits enabled
    // nvidia-settings -a "[gpu:0]/GPUFanControlState=1"
    // nvidia-settings -a "[fan:0]/GPUTargetFanSpeed=XX"
    return error.NotSupported;
}

/// Enable automatic fan control
pub fn setAuto(device_index: u32) !void {
    _ = device_index;
    // nvidia-settings -a "[gpu:0]/GPUFanControlState=0"
    return error.NotSupported;
}

/// Fan curve point
pub const FanPoint = struct {
    temp_c: u32,
    speed_percent: u32,
};

/// Fan curve (temperature -> speed mapping)
pub const FanCurve = struct {
    points: [10]FanPoint,
    point_count: usize,
    hysteresis_c: u32,

    pub fn init() FanCurve {
        return FanCurve{
            .points = undefined,
            .point_count = 0,
            .hysteresis_c = 3,
        };
    }

    pub fn addPoint(self: *FanCurve, temp_c: u32, speed_percent: u32) !void {
        if (self.point_count >= 10) return error.CurveFull;

        // Insert sorted by temperature
        var insert_idx: usize = self.point_count;
        for (0..self.point_count) |i| {
            if (temp_c < self.points[i].temp_c) {
                insert_idx = i;
                break;
            }
        }

        // Shift existing points
        if (insert_idx < self.point_count) {
            var i: usize = self.point_count;
            while (i > insert_idx) : (i -= 1) {
                self.points[i] = self.points[i - 1];
            }
        }

        self.points[insert_idx] = .{
            .temp_c = temp_c,
            .speed_percent = speed_percent,
        };
        self.point_count += 1;
    }

    /// Get target fan speed for a given temperature
    pub fn getSpeedAt(self: *const FanCurve, temp_c: u32) u32 {
        if (self.point_count == 0) return 50; // Default

        // Below first point
        if (temp_c <= self.points[0].temp_c) {
            return self.points[0].speed_percent;
        }

        // Above last point
        if (temp_c >= self.points[self.point_count - 1].temp_c) {
            return self.points[self.point_count - 1].speed_percent;
        }

        // Linear interpolation between points
        for (0..self.point_count - 1) |i| {
            const p1 = self.points[i];
            const p2 = self.points[i + 1];

            if (temp_c >= p1.temp_c and temp_c <= p2.temp_c) {
                const temp_range = p2.temp_c - p1.temp_c;
                const speed_range = @as(i32, @intCast(p2.speed_percent)) -
                    @as(i32, @intCast(p1.speed_percent));
                const temp_offset = temp_c - p1.temp_c;
                const speed_offset = @divTrunc(speed_range * @as(i32, @intCast(temp_offset)), @as(i32, @intCast(temp_range)));
                const result = @as(i32, @intCast(p1.speed_percent)) + speed_offset;
                return if (result > 0) @intCast(result) else 0;
            }
        }

        return 50; // Fallback
    }
};

/// Set custom fan curve (requires elevated permissions)
pub fn setCurve(device_index: u32, curve: FanCurve) !void {
    _ = device_index;
    _ = curve;
    // Would need to implement as a daemon that polls temperature
    // and sets fan speed accordingly
    return error.NotSupported;
}

/// Preset fan curves
pub const FanPreset = enum {
    silent, // Prioritize quiet operation
    balanced, // Default curve
    performance, // Prioritize cooling
    aggressive, // Maximum cooling

    pub fn getCurve(self: FanPreset) FanCurve {
        var curve = FanCurve.init();

        switch (self) {
            .silent => {
                curve.addPoint(40, 0) catch {};
                curve.addPoint(50, 25) catch {};
                curve.addPoint(60, 35) catch {};
                curve.addPoint(70, 45) catch {};
                curve.addPoint(80, 60) catch {};
                curve.addPoint(85, 100) catch {};
            },
            .balanced => {
                curve.addPoint(40, 30) catch {};
                curve.addPoint(50, 35) catch {};
                curve.addPoint(60, 45) catch {};
                curve.addPoint(70, 55) catch {};
                curve.addPoint(80, 75) catch {};
                curve.addPoint(85, 100) catch {};
            },
            .performance => {
                curve.addPoint(40, 40) catch {};
                curve.addPoint(50, 50) catch {};
                curve.addPoint(60, 60) catch {};
                curve.addPoint(70, 75) catch {};
                curve.addPoint(75, 90) catch {};
                curve.addPoint(80, 100) catch {};
            },
            .aggressive => {
                curve.addPoint(40, 50) catch {};
                curve.addPoint(50, 65) catch {};
                curve.addPoint(60, 80) catch {};
                curve.addPoint(70, 100) catch {};
            },
        }

        return curve;
    }
};

/// Apply fan preset
pub fn applyPreset(device_index: u32, preset: FanPreset) !void {
    return setCurve(device_index, preset.getCurve());
}

test "fan curve" {
    var curve = FanCurve.init();
    try curve.addPoint(40, 30);
    try curve.addPoint(60, 50);
    try curve.addPoint(80, 100);

    try std.testing.expectEqual(@as(u32, 30), curve.getSpeedAt(30)); // Below first
    try std.testing.expectEqual(@as(u32, 40), curve.getSpeedAt(50)); // Interpolated
    try std.testing.expectEqual(@as(u32, 100), curve.getSpeedAt(90)); // Above last
}
