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

/// Query fan info via nvidia-smi
fn queryNvidiaSmi(device_index: u32, query: []const u8) u32 {
    const allocator = std.heap.page_allocator;
    const io = std.Io.Threaded.global_single_threaded.io();
    var id_buf: [16]u8 = undefined;
    const id_str = std.fmt.bufPrint(&id_buf, "{d}", .{device_index}) catch return 0;

    const result = std.process.run(allocator, io, .{
        .argv = &.{ "nvidia-smi", "-i", id_str, "--query-gpu", query, "--format=csv,noheader,nounits" },
    }) catch return 0;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term != .exited or result.term.exited != 0) return 0;

    const output = std.mem.trim(u8, result.stdout, " \t\n\r");
    return std.fmt.parseInt(u32, output, 10) catch 0;
}

/// Count number of fans via nvidia-settings
fn getFanCount(device_index: u32) u32 {
    const allocator = std.heap.page_allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const result = std.process.run(allocator, io, .{
        .argv = &.{ "nvidia-settings", "-t", "-q", "fans" },
    }) catch return 1;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    // Count lines that contain our GPU index
    var count: u32 = 0;
    var iter = std.mem.splitScalar(u8, result.stdout, '\n');
    var target_buf: [32]u8 = undefined;
    const target = std.fmt.bufPrint(&target_buf, "[gpu:{d}]", .{device_index}) catch return 1;

    while (iter.next()) |line| {
        if (std.mem.indexOf(u8, line, target) != null) {
            count += 1;
        }
    }

    return if (count > 0) count else 1;
}

/// Get current fan state
pub fn getState(device_index: u32) !FanState {
    const device = try nvml.getDeviceByIndex(device_index);
    const speed = nvml.getDeviceFanSpeed(device) catch 0;

    // Query fan speed via nvidia-smi as backup and for RPM estimation
    const smi_speed = queryNvidiaSmi(device_index, "fan.speed");
    const actual_speed = if (speed > 0) speed else smi_speed;

    // Estimate RPM from percentage (typical max is ~2500-3500 RPM for GPU fans)
    const estimated_rpm = actual_speed * 30; // Rough estimate: 100% = 3000 RPM

    // Get fan count
    const fan_count = getFanCount(device_index);

    return FanState{
        .speed_percent = actual_speed,
        .speed_rpm = estimated_rpm,
        .target_percent = actual_speed,
        .mode = .auto,
        .fan_count = fan_count,
    };
}

/// Get fan speed percentage
pub fn getSpeed(device_index: u32) !u32 {
    const device = try nvml.getDeviceByIndex(device_index);
    return nvml.getDeviceFanSpeed(device);
}

/// Run nvidia-settings assignment
fn assignNvidiaSettings(assignment: []const u8) !void {
    const allocator = std.heap.page_allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const result = std.process.run(allocator, io, .{
        .argv = &.{ "nvidia-settings", "-a", assignment },
    }) catch return error.NvidiaSettingsError;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term != .exited or result.term.exited != 0) return error.NvidiaSettingsError;
}

/// Set manual fan speed (requires elevated permissions + Coolbits)
/// Note: Requires Coolbits=4 or Coolbits=28 in xorg.conf
pub fn setSpeed(device_index: u32, speed_percent: u32) !void {
    const clamped = @min(speed_percent, 100);
    var buf: [128]u8 = undefined;

    // First enable manual fan control
    const control_assign = std.fmt.bufPrint(&buf, "[gpu:{d}]/GPUFanControlState=1", .{device_index}) catch return error.FormatError;
    try assignNvidiaSettings(control_assign);

    // Set fan speed for all fans on this GPU
    var fan_buf: [128]u8 = undefined;
    const fan_count = getFanCount(device_index);

    for (0..fan_count) |fan_idx| {
        const fan_assign = std.fmt.bufPrint(&fan_buf, "[fan:{d}]/GPUTargetFanSpeed={d}", .{ fan_idx, clamped }) catch continue;
        assignNvidiaSettings(fan_assign) catch {};
    }
}

/// Enable automatic fan control
pub fn setAuto(device_index: u32) !void {
    var buf: [128]u8 = undefined;

    // Disable manual fan control (return to auto)
    const assign = std.fmt.bufPrint(&buf, "[gpu:{d}]/GPUFanControlState=0", .{device_index}) catch return error.FormatError;
    try assignNvidiaSettings(assign);
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
