//! nvpower/thermals - Thermal Management
//!
//! Temperature monitoring, thermal targets, and throttling detection.

const std = @import("std");
const nvml = @import("../bindings/nvml.zig");

/// Temperature sensor types
pub const Sensor = enum {
    gpu, // Main GPU die
    memory, // VRAM (if available)
    hotspot, // Hottest point on die
    board, // Board ambient
    power_supply, // VRM temperature
};

/// Thermal state
pub const ThermalState = struct {
    gpu_temp_c: u32,
    memory_temp_c: u32,
    hotspot_temp_c: u32,
    target_temp_c: u32,
    slowdown_temp_c: u32,
    shutdown_temp_c: u32,

    pub fn isThrottling(self: ThermalState) bool {
        return self.gpu_temp_c >= self.slowdown_temp_c or
            self.hotspot_temp_c >= self.slowdown_temp_c;
    }

    pub fn isCritical(self: ThermalState) bool {
        return self.gpu_temp_c >= self.shutdown_temp_c - 5;
    }

    pub fn headroom(self: ThermalState) i32 {
        return @as(i32, @intCast(self.slowdown_temp_c)) - @as(i32, @intCast(self.gpu_temp_c));
    }

    pub fn status(self: ThermalState) ThermalStatus {
        if (self.isCritical()) return .critical;
        if (self.isThrottling()) return .throttling;
        if (self.headroom() < 10) return .warm;
        return .cool;
    }
};

pub const ThermalStatus = enum {
    cool, // Well under target
    warm, // Approaching target
    throttling, // At or above slowdown
    critical, // Near shutdown

    pub fn color(self: ThermalStatus) []const u8 {
        return switch (self) {
            .cool => "\x1b[32m", // Green
            .warm => "\x1b[33m", // Yellow
            .throttling => "\x1b[31m", // Red
            .critical => "\x1b[35m", // Magenta
        };
    }
};

/// Get current thermal state
pub fn getState(device_index: u32) !ThermalState {
    const device = try nvml.getDeviceByIndex(device_index);
    const temp = nvml.getDeviceTemperature(device, nvml.TEMPERATURE_GPU) catch 0;

    return ThermalState{
        .gpu_temp_c = temp,
        .memory_temp_c = 0, // TODO: query if available
        .hotspot_temp_c = 0, // TODO: query if available
        .target_temp_c = 83, // Default NVIDIA target
        .slowdown_temp_c = 83,
        .shutdown_temp_c = 92,
    };
}

/// Get single temperature reading
pub fn getTemperature(device_index: u32, sensor: Sensor) !u32 {
    const device = try nvml.getDeviceByIndex(device_index);

    return switch (sensor) {
        .gpu => nvml.getDeviceTemperature(device, nvml.TEMPERATURE_GPU),
        .memory, .hotspot, .board, .power_supply => error.NotSupported,
    };
}

/// Thermal target configuration
pub const ThermalConfig = struct {
    /// Target temperature in Celsius
    target_c: ?u32 = null,
    /// Priority: performance or thermals
    priority: ThermalPriority = .balanced,
};

pub const ThermalPriority = enum {
    performance, // Allow higher temps for more performance
    balanced, // Default behavior
    thermals, // Prioritize lower temps over performance
};

/// Set thermal target (limited driver support)
pub fn setTarget(device_index: u32, config: ThermalConfig) !void {
    _ = device_index;
    _ = config;
    // NVIDIA doesn't expose thermal target setting via NVML
    // Would need nvidia-settings or driver-specific methods
    return error.NotSupported;
}

/// Thermal alert thresholds
pub const AlertThresholds = struct {
    warning_c: u32 = 75,
    critical_c: u32 = 85,
    shutdown_c: u32 = 90,
};

/// Check if temperature is above threshold
pub fn checkThreshold(device_index: u32, thresholds: AlertThresholds) !?ThermalStatus {
    const state = try getState(device_index);

    if (state.gpu_temp_c >= thresholds.shutdown_c) return .critical;
    if (state.gpu_temp_c >= thresholds.critical_c) return .throttling;
    if (state.gpu_temp_c >= thresholds.warning_c) return .warm;
    return null; // No alert
}

/// Temperature history for trending
pub const TempHistory = struct {
    samples: [120]u32, // 2 minutes at 1s interval
    sample_count: usize,
    write_index: usize,

    pub fn init() TempHistory {
        return TempHistory{
            .samples = [_]u32{0} ** 120,
            .sample_count = 0,
            .write_index = 0,
        };
    }

    pub fn record(self: *TempHistory, temp: u32) void {
        self.samples[self.write_index] = temp;
        self.write_index = (self.write_index + 1) % 120;
        if (self.sample_count < 120) self.sample_count += 1;
    }

    pub fn average(self: *const TempHistory) u32 {
        if (self.sample_count == 0) return 0;
        var sum: u64 = 0;
        for (0..self.sample_count) |i| {
            sum += self.samples[i];
        }
        return @intCast(sum / self.sample_count);
    }

    pub fn max(self: *const TempHistory) u32 {
        var max_temp: u32 = 0;
        for (0..self.sample_count) |i| {
            if (self.samples[i] > max_temp) max_temp = self.samples[i];
        }
        return max_temp;
    }

    pub fn trend(self: *const TempHistory) i32 {
        if (self.sample_count < 10) return 0;
        // Compare last 10 samples to previous 10
        const end = self.write_index;
        const recent_start = if (end >= 10) end - 10 else 120 + end - 10;
        const older_start = if (recent_start >= 10) recent_start - 10 else 120 + recent_start - 10;

        var recent_sum: i32 = 0;
        var older_sum: i32 = 0;
        for (0..10) |i| {
            recent_sum += @intCast(self.samples[(recent_start + i) % 120]);
            older_sum += @intCast(self.samples[(older_start + i) % 120]);
        }
        return @divTrunc(recent_sum - older_sum, 10);
    }
};

test "thermal state" {
    const state = ThermalState{
        .gpu_temp_c = 75,
        .memory_temp_c = 70,
        .hotspot_temp_c = 78,
        .target_temp_c = 83,
        .slowdown_temp_c = 83,
        .shutdown_temp_c = 92,
    };
    try std.testing.expect(!state.isThrottling());
    try std.testing.expectEqual(@as(i32, 8), state.headroom());
    try std.testing.expectEqual(ThermalStatus.warm, state.status());
}
