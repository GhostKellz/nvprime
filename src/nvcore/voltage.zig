//! nvcore/voltage - Voltage Curve Management
//!
//! Control GPU voltage curve for undervolting or overclocking.
//! WARNING: Improper voltage settings can damage hardware or cause instability.

const std = @import("std");
const nvml = @import("../bindings/nvml.zig");

/// A point on the voltage-frequency curve
pub const VoltagePoint = struct {
    /// Voltage in millivolts
    voltage_mv: u32,
    /// Clock frequency in MHz
    frequency_mhz: u32,
};

/// Voltage curve (V/F curve)
pub const VoltageCurve = struct {
    points: [16]VoltagePoint,
    point_count: usize,

    pub fn init() VoltageCurve {
        return VoltageCurve{
            .points = undefined,
            .point_count = 0,
        };
    }

    pub fn addPoint(self: *VoltageCurve, voltage_mv: u32, frequency_mhz: u32) !void {
        if (self.point_count >= 16) return error.CurveFull;
        self.points[self.point_count] = .{
            .voltage_mv = voltage_mv,
            .frequency_mhz = frequency_mhz,
        };
        self.point_count += 1;
    }

    /// Get frequency for a given voltage (linear interpolation)
    pub fn getFrequencyAt(self: *const VoltageCurve, voltage_mv: u32) ?u32 {
        if (self.point_count < 2) return null;

        for (0..self.point_count - 1) |i| {
            const p1 = self.points[i];
            const p2 = self.points[i + 1];

            if (voltage_mv >= p1.voltage_mv and voltage_mv <= p2.voltage_mv) {
                // Linear interpolation
                const v_range = p2.voltage_mv - p1.voltage_mv;
                const f_range = @as(i32, @intCast(p2.frequency_mhz)) - @as(i32, @intCast(p1.frequency_mhz));
                const v_offset = voltage_mv - p1.voltage_mv;
                const f_offset = @divTrunc(f_range * @as(i32, @intCast(v_offset)), @as(i32, @intCast(v_range)));
                const result = @as(i32, @intCast(p1.frequency_mhz)) + f_offset;
                return if (result > 0) @intCast(result) else 0;
            }
        }
        return null;
    }
};

/// Voltage state
pub const VoltageState = struct {
    /// Current core voltage (millivolts)
    current_voltage_mv: u32,
    /// Default voltage for current frequency
    default_voltage_mv: u32,
    /// User offset (negative = undervolt)
    offset_mv: i32,
    /// Whether custom curve is active
    custom_curve_active: bool,
};

/// Get current voltage state
pub fn getState(device_index: u32) !VoltageState {
    _ = device_index;
    // NVML doesn't directly expose voltage reading
    // Would need nvidia-smi --query-gpu=power.draw or nvidia-settings
    return VoltageState{
        .current_voltage_mv = 0,
        .default_voltage_mv = 0,
        .offset_mv = 0,
        .custom_curve_active = false,
    };
}

/// Run nvidia-settings query and parse integer result
fn queryNvidiaSettings(query: []const u8) !i32 {
    const allocator = std.heap.page_allocator;

    var child = std.process.Child.init(
        &.{ "nvidia-settings", "-t", "-q", query },
        allocator,
    );
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    var stdout = std.ArrayList(u8).init(allocator);
    defer stdout.deinit();

    const reader = child.stdout.?.reader();
    reader.readAllArrayList(&stdout, 4096) catch {};

    const result = try child.wait();
    if (result.Exited != 0) return error.NvidiaSettingsError;

    const output = std.mem.trim(u8, stdout.items, " \t\n\r");
    return std.fmt.parseInt(i32, output, 10) catch 0;
}

/// Run nvidia-settings assignment
fn assignNvidiaSettings(assignment: []const u8) !void {
    const allocator = std.heap.page_allocator;

    var child = std.process.Child.init(
        &.{ "nvidia-settings", "-a", assignment },
        allocator,
    );
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();
    const result = try child.wait();
    if (result.Exited != 0) return error.NvidiaSettingsError;
}

/// Set voltage offset (requires elevated permissions + Coolbits)
/// Note: Requires Coolbits=8 or Coolbits=28 in xorg.conf for overvoltage control
pub fn setOffset(device_index: u32, offset_mv: i32) !void {
    var buf: [128]u8 = undefined;

    // GPUOverVoltageOffset is in microvolts (uV), so multiply by 1000
    const offset_uv = offset_mv * 1000;

    const assignment = std.fmt.bufPrint(&buf, "[gpu:{d}]/GPUOverVoltageOffset={d}", .{ device_index, offset_uv }) catch return error.FormatError;
    try assignNvidiaSettings(assignment);
}

/// Get current voltage offset
pub fn getOffset(device_index: u32) !i32 {
    var buf: [128]u8 = undefined;

    const query = std.fmt.bufPrint(&buf, "[gpu:{d}]/GPUOverVoltageOffset", .{device_index}) catch return error.FormatError;
    const offset_uv = queryNvidiaSettings(query) catch return 0;

    // Convert from microvolts to millivolts
    return @divTrunc(offset_uv, 1000);
}

/// Set custom voltage curve (requires elevated permissions + Coolbits)
/// This sets individual V/F curve points via nvidia-settings
pub fn setCurve(device_index: u32, curve: VoltageCurve) !void {
    if (curve.point_count == 0) return error.InvalidCurve;

    // nvidia-settings uses GPUGraphicsClockOffset and voltage offsets per point
    // The actual curve editing is complex - we apply a uniform offset based on the curve
    // For full curve editing, one would need to use nvidia-smi or direct NVAPI

    // Calculate average offset from the curve compared to stock
    // This is a simplification - real curve editing needs NVAPI or nvidia-inspector
    var total_offset: i64 = 0;
    for (0..curve.point_count) |i| {
        const point = curve.points[i];
        total_offset += @as(i64, point.voltage_mv);
    }
    const avg_voltage = @divTrunc(total_offset, @as(i64, @intCast(curve.point_count)));

    // Assume stock voltage around 1000mV for modern GPUs, calculate offset
    const stock_voltage: i64 = 1000;
    const offset = @as(i32, @intCast(avg_voltage - stock_voltage));

    try setOffset(device_index, offset);
}

/// Reset voltage to stock
pub fn reset(device_index: u32) !void {
    // Reset by setting offset to 0
    try setOffset(device_index, 0);
}

/// Undervolt presets (conservative, safe values)
pub const UndervoltPreset = enum {
    /// No undervolt
    stock,
    /// Light undervolt (-25mV)
    light,
    /// Moderate undervolt (-50mV)
    moderate,
    /// Aggressive undervolt (-75mV) - test thoroughly!
    aggressive,

    pub fn offsetMv(self: UndervoltPreset) i32 {
        return switch (self) {
            .stock => 0,
            .light => -25,
            .moderate => -50,
            .aggressive => -75,
        };
    }

    pub fn description(self: UndervoltPreset) []const u8 {
        return switch (self) {
            .stock => "Stock voltage (no changes)",
            .light => "Light undervolt (-25mV) - safe for most GPUs",
            .moderate => "Moderate undervolt (-50mV) - test for stability",
            .aggressive => "Aggressive undervolt (-75mV) - requires stability testing",
        };
    }
};

/// Apply undervolt preset
pub fn applyPreset(device_index: u32, preset: UndervoltPreset) !void {
    return setOffset(device_index, preset.offsetMv());
}

test "voltage curve" {
    var curve = VoltageCurve.init();
    try curve.addPoint(800, 1200);
    try curve.addPoint(900, 1500);
    try curve.addPoint(1000, 1800);

    // Test interpolation
    const freq = curve.getFrequencyAt(850).?;
    try std.testing.expect(freq > 1200 and freq < 1500);
}
