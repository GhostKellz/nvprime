//! nvpower/efficiency - Power Efficiency Modes
//!
//! Manage overall power efficiency and performance trade-offs.

const std = @import("std");
const nvml = @import("../bindings/nvml.zig");

/// Efficiency mode
pub const EfficiencyMode = enum {
    /// Maximum performance, no power saving
    performance,
    /// Balanced power and performance (default)
    balanced,
    /// Quiet operation (reduced power/clocks for silence)
    quiet,
    /// Maximum power savings
    powersave,

    pub fn description(self: EfficiencyMode) []const u8 {
        return switch (self) {
            .performance => "Maximum performance, full power",
            .balanced => "Balanced power and performance",
            .quiet => "Quiet operation, reduced power",
            .powersave => "Maximum power efficiency",
        };
    }

    pub fn powerLimitPercent(self: EfficiencyMode) u32 {
        return switch (self) {
            .performance => 100,
            .balanced => 90,
            .quiet => 70,
            .powersave => 60,
        };
    }

    pub fn clockPercent(self: EfficiencyMode) u32 {
        return switch (self) {
            .performance => 100,
            .balanced => 90,
            .quiet => 80,
            .powersave => 70,
        };
    }

    pub fn fanProfile(self: EfficiencyMode) []const u8 {
        return switch (self) {
            .performance => "performance",
            .balanced => "balanced",
            .quiet => "silent",
            .powersave => "silent",
        };
    }
};

/// Efficiency state
pub const EfficiencyState = struct {
    mode: EfficiencyMode,
    actual_power_percent: u32,
    actual_clock_percent: u32,
    efficiency_score: u32, // 0-100, higher is better efficiency

    pub fn print(self: EfficiencyState, writer: anytype) !void {
        try writer.print("Efficiency: {s} | Power: {d}% | Clock: {d}% | Score: {d}/100", .{
            @tagName(self.mode),
            self.actual_power_percent,
            self.actual_clock_percent,
            self.efficiency_score,
        });
    }
};

/// Get current efficiency state
pub fn getState(device_index: u32) !EfficiencyState {
    const device = try nvml.getDeviceByIndex(device_index);

    const util = nvml.getDeviceUtilization(device) catch nvml.Utilization{ .gpu = 0, .memory = 0 };
    const power = nvml.getDevicePowerUsage(device) catch 0;
    const power_limit = nvml.getDevicePowerLimit(device) catch 1; // Avoid div by zero

    const power_percent: u32 = @intCast(@min(100, power * 100 / power_limit));

    // Simple efficiency score: high utilization with low power is good
    const efficiency = if (util.gpu > 0 and power_percent > 0)
        @min(100, util.gpu * 100 / power_percent)
    else
        50;

    return EfficiencyState{
        .mode = .balanced, // Would need to track active mode
        .actual_power_percent = power_percent,
        .actual_clock_percent = 100, // TODO: calculate from clocks
        .efficiency_score = @intCast(efficiency),
    };
}

/// Apply efficiency mode
pub fn setMode(device_index: u32, mode: EfficiencyMode) !void {
    _ = device_index;
    _ = mode;
    // Would need to coordinate:
    // - Power limit (via limits.zig)
    // - Clock limits (via nvcore/clocks.zig)
    // - Fan curve (via fans.zig)
    return error.NotSupported;
}

/// Adaptive efficiency settings
pub const AdaptiveConfig = struct {
    /// Enable adaptive mode switching
    enabled: bool = false,
    /// Utilization threshold to switch to performance
    performance_threshold: u32 = 90,
    /// Utilization threshold to switch to powersave
    powersave_threshold: u32 = 10,
    /// Seconds before switching modes
    switch_delay_s: u32 = 5,
};

/// Efficiency metrics over time
pub const EfficiencyMetrics = struct {
    /// Average performance per watt
    perf_per_watt: f32,
    /// Total energy consumed (Wh)
    energy_wh: f32,
    /// Time in each mode
    time_in_performance_s: u64,
    time_in_balanced_s: u64,
    time_in_quiet_s: u64,
    time_in_powersave_s: u64,

    pub fn averageMode(self: EfficiencyMetrics) EfficiencyMode {
        const total = self.time_in_performance_s + self.time_in_balanced_s +
            self.time_in_quiet_s + self.time_in_powersave_s;
        if (total == 0) return .balanced;

        if (self.time_in_performance_s * 2 >= total) return .performance;
        if (self.time_in_powersave_s * 2 >= total) return .powersave;
        if (self.time_in_quiet_s > self.time_in_balanced_s) return .quiet;
        return .balanced;
    }
};

test "efficiency mode" {
    const mode = EfficiencyMode.quiet;
    try std.testing.expectEqual(@as(u32, 70), mode.powerLimitPercent());
    try std.testing.expectEqual(@as(u32, 80), mode.clockPercent());
}
