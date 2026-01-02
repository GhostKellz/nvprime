//! nvcore/boost - GPU Boost Clock Management
//!
//! NVIDIA GPU Boost dynamically adjusts clock speeds based on power, thermals, and utilization.
//! This module provides control over boost behavior and offsets.

const std = @import("std");
const nvml = @import("../bindings/nvml.zig");

/// Boost state information
pub const BoostState = struct {
    /// Base clock (guaranteed minimum)
    base_clock_mhz: u32,
    /// Boost clock (rated maximum)
    boost_clock_mhz: u32,
    /// Current actual clock
    current_clock_mhz: u32,
    /// User-applied offset
    offset_mhz: i32,
    /// Whether thermal throttling is active
    thermal_throttle: bool,
    /// Whether power throttling is active
    power_throttle: bool,

    pub fn effectiveBoost(self: BoostState) u32 {
        const base: i32 = @intCast(self.boost_clock_mhz);
        const adjusted = base + self.offset_mhz;
        return if (adjusted > 0) @intCast(adjusted) else 0;
    }

    pub fn utilizationPercent(self: BoostState) f32 {
        if (self.boost_clock_mhz == 0) return 0;
        return @as(f32, @floatFromInt(self.current_clock_mhz)) /
            @as(f32, @floatFromInt(self.effectiveBoost())) * 100.0;
    }
};

/// Get current boost state
pub fn getState(device_index: u32) !BoostState {
    const device = try nvml.getDeviceByIndex(device_index);

    const current = nvml.getDeviceClock(device, nvml.CLOCK_GRAPHICS) catch 0;
    const max_clock = nvml.getDeviceMaxClock(device, nvml.CLOCK_GRAPHICS) catch 0;

    // Estimate base clock as ~70% of boost (typical ratio)
    const base = max_clock * 7 / 10;

    return BoostState{
        .base_clock_mhz = base,
        .boost_clock_mhz = max_clock,
        .current_clock_mhz = current,
        .offset_mhz = 0, // Would need to read from nvidia-settings or similar
        .thermal_throttle = false, // Would need throttle reason query
        .power_throttle = false,
    };
}

/// Clock offset configuration
pub const OffsetConfig = struct {
    /// GPU clock offset in MHz (can be negative)
    gpu_offset_mhz: i32 = 0,
    /// Memory clock offset in MHz (can be negative)
    mem_offset_mhz: i32 = 0,
};

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

    // Parse the output as an integer
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

/// Set clock offset (requires elevated permissions and Coolbits enabled)
/// Note: Requires Coolbits=28 or similar in xorg.conf
pub fn setOffset(device_index: u32, config: OffsetConfig) !void {
    const allocator = std.heap.page_allocator;
    var buf: [128]u8 = undefined;

    // Set GPU clock offset for all performance levels
    const gpu_assign = std.fmt.bufPrint(&buf, "[gpu:{d}]/GPUGraphicsClockOffsetAllPerformanceLevels={d}", .{ device_index, config.gpu_offset_mhz }) catch return error.FormatError;
    assignNvidiaSettings(gpu_assign) catch |err| {
        // Coolbits might not be enabled - try per-level approach
        if (err == error.NvidiaSettingsError) {
            // Try setting for P0 state specifically
            const p0_assign = std.fmt.bufPrint(&buf, "[gpu:{d}]/GPUGraphicsClockOffset[3]={d}", .{ device_index, config.gpu_offset_mhz }) catch return error.FormatError;
            try assignNvidiaSettings(p0_assign);
        } else return err;
    };

    // Set memory clock offset
    if (config.mem_offset_mhz != 0) {
        var mem_buf: [128]u8 = undefined;
        const mem_assign = std.fmt.bufPrint(&mem_buf, "[gpu:{d}]/GPUMemoryTransferRateOffsetAllPerformanceLevels={d}", .{ device_index, config.mem_offset_mhz }) catch return error.FormatError;
        assignNvidiaSettings(mem_assign) catch {
            // Try per-level if all-levels fails
            const p0_mem = std.fmt.bufPrint(&mem_buf, "[gpu:{d}]/GPUMemoryTransferRateOffset[3]={d}", .{ device_index, config.mem_offset_mhz }) catch return error.FormatError;
            assignNvidiaSettings(p0_mem) catch {};
        };
    }

    _ = allocator;
}

/// Get current clock offset
pub fn getOffset(device_index: u32) !OffsetConfig {
    var query_buf: [128]u8 = undefined;

    // Query GPU clock offset (try P0/perf level 3 first)
    const gpu_query = std.fmt.bufPrint(&query_buf, "[gpu:{d}]/GPUGraphicsClockOffset[3]", .{device_index}) catch return error.FormatError;
    const gpu_offset = queryNvidiaSettings(gpu_query) catch 0;

    // Query memory offset
    var mem_buf: [128]u8 = undefined;
    const mem_query = std.fmt.bufPrint(&mem_buf, "[gpu:{d}]/GPUMemoryTransferRateOffset[3]", .{device_index}) catch return error.FormatError;
    const mem_offset = queryNvidiaSettings(mem_query) catch 0;

    return OffsetConfig{
        .gpu_offset_mhz = gpu_offset,
        .mem_offset_mhz = mem_offset,
    };
}

/// Reset clock offsets to default
pub fn resetOffset(device_index: u32) !void {
    return setOffset(device_index, .{
        .gpu_offset_mhz = 0,
        .mem_offset_mhz = 0,
    });
}

/// Boost profiles
pub const BoostProfile = enum {
    /// Default boost behavior
    default,
    /// Aggressive boost (higher clocks, more power)
    aggressive,
    /// Conservative boost (stable, lower thermals)
    conservative,
    /// Fixed boost (minimal dynamic adjustment)
    fixed,

    pub fn gpuOffset(self: BoostProfile) i32 {
        return switch (self) {
            .default => 0,
            .aggressive => 100,
            .conservative => -50,
            .fixed => 0,
        };
    }

    pub fn memOffset(self: BoostProfile) i32 {
        return switch (self) {
            .default => 0,
            .aggressive => 200,
            .conservative => 0,
            .fixed => 0,
        };
    }
};

/// Apply a boost profile
pub fn applyProfile(device_index: u32, profile: BoostProfile) !void {
    return setOffset(device_index, .{
        .gpu_offset_mhz = profile.gpuOffset(),
        .mem_offset_mhz = profile.memOffset(),
    });
}

test "boost state" {
    const state = BoostState{
        .base_clock_mhz = 1400,
        .boost_clock_mhz = 2000,
        .current_clock_mhz = 1800,
        .offset_mhz = 50,
        .thermal_throttle = false,
        .power_throttle = false,
    };
    try std.testing.expectEqual(@as(u32, 2050), state.effectiveBoost());
}
