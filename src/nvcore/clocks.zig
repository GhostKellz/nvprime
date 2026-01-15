//! nvcore/clocks - GPU Clock Management
//!
//! Control GPU and memory clock speeds.

const std = @import("std");
const nvml = @import("../bindings/nvml.zig");

/// Clock configuration
pub const ClockConfig = struct {
    min_mhz: ?u32 = null,
    max_mhz: ?u32 = null,
};

/// Get current GPU clock speed
pub fn getGpuClock(device_index: u32) !u32 {
    const device = try nvml.getDeviceByIndex(device_index);
    return nvml.getDeviceClock(device, nvml.CLOCK_GRAPHICS);
}

/// Get current memory clock speed
pub fn getMemoryClock(device_index: u32) !u32 {
    const device = try nvml.getDeviceByIndex(device_index);
    return nvml.getDeviceClock(device, nvml.CLOCK_MEM);
}

/// Get current SM clock speed
pub fn getSmClock(device_index: u32) !u32 {
    const device = try nvml.getDeviceByIndex(device_index);
    return nvml.getDeviceClock(device, nvml.CLOCK_SM);
}

/// Get max GPU clock speed
pub fn getMaxGpuClock(device_index: u32) !u32 {
    const device = try nvml.getDeviceByIndex(device_index);
    return nvml.getDeviceMaxClock(device, nvml.CLOCK_GRAPHICS);
}

/// Get max memory clock speed
pub fn getMaxMemoryClock(device_index: u32) !u32 {
    const device = try nvml.getDeviceByIndex(device_index);
    return nvml.getDeviceMaxClock(device, nvml.CLOCK_MEM);
}

/// Clock speed summary
pub const ClockSummary = struct {
    gpu_current_mhz: u32,
    gpu_max_mhz: u32,
    mem_current_mhz: u32,
    mem_max_mhz: u32,
    sm_current_mhz: u32,
    video_current_mhz: u32,

    pub fn gpuPercent(self: ClockSummary) f32 {
        if (self.gpu_max_mhz == 0) return 0;
        return @as(f32, @floatFromInt(self.gpu_current_mhz)) / @as(f32, @floatFromInt(self.gpu_max_mhz)) * 100.0;
    }

    pub fn memPercent(self: ClockSummary) f32 {
        if (self.mem_max_mhz == 0) return 0;
        return @as(f32, @floatFromInt(self.mem_current_mhz)) / @as(f32, @floatFromInt(self.mem_max_mhz)) * 100.0;
    }
};

/// Get complete clock summary
pub fn getSummary(device_index: u32) !ClockSummary {
    const device = try nvml.getDeviceByIndex(device_index);

    return ClockSummary{
        .gpu_current_mhz = nvml.getDeviceClock(device, nvml.CLOCK_GRAPHICS) catch 0,
        .gpu_max_mhz = nvml.getDeviceMaxClock(device, nvml.CLOCK_GRAPHICS) catch 0,
        .mem_current_mhz = nvml.getDeviceClock(device, nvml.CLOCK_MEM) catch 0,
        .mem_max_mhz = nvml.getDeviceMaxClock(device, nvml.CLOCK_MEM) catch 0,
        .sm_current_mhz = nvml.getDeviceClock(device, nvml.CLOCK_SM) catch 0,
        .video_current_mhz = nvml.getDeviceClock(device, nvml.CLOCK_VIDEO) catch 0,
    };
}

// Clock control via nvidia-smi (requires root/sudo or appropriate permissions)

/// Run nvidia-smi command and return success/failure
fn runNvidiaSmi(args: []const []const u8) !void {
    const allocator = std.heap.page_allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.append("nvidia-smi");
    for (args) |arg| {
        try argv.append(arg);
    }

    const result = std.process.run(allocator, io, .{
        .argv = argv.items,
    }) catch return error.NvidiaSmiError;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term != .exited or result.term.exited != 0) {
        return error.NvidiaSmiError;
    }
}

/// Set GPU clock range (requires elevated permissions)
/// Uses nvidia-smi -lgc min,max to lock GPU clocks
pub fn setGpuClock(device_index: u32, config: ClockConfig) !void {
    var buf: [64]u8 = undefined;
    var id_buf: [16]u8 = undefined;

    const id_str = std.fmt.bufPrint(&id_buf, "{d}", .{device_index}) catch return error.FormatError;

    // Build clock range string
    const clock_str = blk: {
        if (config.min_mhz != null and config.max_mhz != null) {
            break :blk std.fmt.bufPrint(&buf, "{d},{d}", .{ config.min_mhz.?, config.max_mhz.? }) catch return error.FormatError;
        } else if (config.max_mhz != null) {
            // Lock to single frequency
            break :blk std.fmt.bufPrint(&buf, "{d},{d}", .{ config.max_mhz.?, config.max_mhz.? }) catch return error.FormatError;
        } else if (config.min_mhz != null) {
            break :blk std.fmt.bufPrint(&buf, "{d},", .{config.min_mhz.?}) catch return error.FormatError;
        } else {
            return error.InvalidConfig;
        }
    };

    try runNvidiaSmi(&.{ "-i", id_str, "-lgc", clock_str });
}

/// Set memory clock range (requires elevated permissions)
/// Uses nvidia-smi -lmc min,max to lock memory clocks
pub fn setMemoryClock(device_index: u32, config: ClockConfig) !void {
    var buf: [64]u8 = undefined;
    var id_buf: [16]u8 = undefined;

    const id_str = std.fmt.bufPrint(&id_buf, "{d}", .{device_index}) catch return error.FormatError;

    const clock_str = blk: {
        if (config.min_mhz != null and config.max_mhz != null) {
            break :blk std.fmt.bufPrint(&buf, "{d},{d}", .{ config.min_mhz.?, config.max_mhz.? }) catch return error.FormatError;
        } else if (config.max_mhz != null) {
            break :blk std.fmt.bufPrint(&buf, "{d},{d}", .{ config.max_mhz.?, config.max_mhz.? }) catch return error.FormatError;
        } else {
            return error.InvalidConfig;
        }
    };

    try runNvidiaSmi(&.{ "-i", id_str, "-lmc", clock_str });
}

/// Reset GPU clocks to default (unlocked)
/// Uses nvidia-smi -rgc to reset GPU clock locks
pub fn resetGpuClocks(device_index: u32) !void {
    var id_buf: [16]u8 = undefined;
    const id_str = std.fmt.bufPrint(&id_buf, "{d}", .{device_index}) catch return error.FormatError;
    try runNvidiaSmi(&.{ "-i", id_str, "-rgc" });
}

/// Reset memory clocks to default (unlocked)
/// Uses nvidia-smi -rmc to reset memory clock locks
pub fn resetMemoryClocks(device_index: u32) !void {
    var id_buf: [16]u8 = undefined;
    const id_str = std.fmt.bufPrint(&id_buf, "{d}", .{device_index}) catch return error.FormatError;
    try runNvidiaSmi(&.{ "-i", id_str, "-rmc" });
}

/// Reset all clocks to default
pub fn resetClocks(device_index: u32) !void {
    try resetGpuClocks(device_index);
    try resetMemoryClocks(device_index);
}

/// Enable persistence mode (keeps driver loaded, reduces latency)
pub fn enablePersistenceMode(device_index: u32) !void {
    var id_buf: [16]u8 = undefined;
    const id_str = std.fmt.bufPrint(&id_buf, "{d}", .{device_index}) catch return error.FormatError;
    try runNvidiaSmi(&.{ "-i", id_str, "-pm", "1" });
}

/// Disable persistence mode
pub fn disablePersistenceMode(device_index: u32) !void {
    var id_buf: [16]u8 = undefined;
    const id_str = std.fmt.bufPrint(&id_buf, "{d}", .{device_index}) catch return error.FormatError;
    try runNvidiaSmi(&.{ "-i", id_str, "-pm", "0" });
}

test "clock summary" {
    const summary = ClockSummary{
        .gpu_current_mhz = 1500,
        .gpu_max_mhz = 2000,
        .mem_current_mhz = 9000,
        .mem_max_mhz = 10000,
        .sm_current_mhz = 1500,
        .video_current_mhz = 1400,
    };
    try std.testing.expectEqual(@as(f32, 75.0), summary.gpuPercent());
}
