//! nvcore/pstates - Performance State Control
//!
//! NVIDIA GPUs use P-states (Performance States) to manage power and performance.
//! P0 = Maximum performance, P8 = Basic 3D, P12 = Idle

const std = @import("std");
const nvml = @import("../bindings/nvml.zig");

/// P-state definitions
pub const PState = enum(u4) {
    p0 = 0, // Maximum 3D performance
    p1 = 1, // (Reserved)
    p2 = 2, // Balanced 3D
    p3 = 3, // Balanced 3D
    p5 = 5, // (Reserved)
    p8 = 8, // Basic HD video playback
    p10 = 10, // DVD playback
    p12 = 12, // Idle/2D
    p15 = 15, // Unknown/Unused

    pub fn description(self: PState) []const u8 {
        return switch (self) {
            .p0 => "Maximum 3D Performance",
            .p1 => "Reserved",
            .p2 => "Balanced 3D Performance",
            .p3 => "Balanced 3D",
            .p5 => "Reserved",
            .p8 => "Basic HD Video",
            .p10 => "DVD Playback",
            .p12 => "Idle / 2D",
            .p15 => "Unknown",
        };
    }

    pub fn isPerformance(self: PState) bool {
        return switch (self) {
            .p0, .p2, .p3 => true,
            else => false,
        };
    }

    pub fn isIdle(self: PState) bool {
        return switch (self) {
            .p8, .p10, .p12 => true,
            else => false,
        };
    }
};

/// Get current P-state
pub fn getCurrent(device_index: u32) !PState {
    const device = try nvml.getDeviceByIndex(device_index);
    const pstate = try nvml.getDevicePerformanceState(device);
    return @enumFromInt(@as(u4, @intCast(@intFromEnum(pstate))));
}

/// Check if GPU is in a performance state
pub fn isInPerformanceState(device_index: u32) !bool {
    const pstate = try getCurrent(device_index);
    return pstate.isPerformance();
}

/// Check if GPU is idle
pub fn isIdle(device_index: u32) !bool {
    const pstate = try getCurrent(device_index);
    return pstate.isIdle();
}

/// P-state lock configuration
pub const LockMode = enum {
    /// Dynamic P-state switching (default)
    dynamic,
    /// Lock to P0 for maximum performance
    performance,
    /// Lock to P2 for balanced
    balanced,
};

/// Lock P-state (requires elevated permissions)
/// Note: This uses nvidia-smi under the hood
pub fn lock(device_index: u32, mode: LockMode) !void {
    _ = device_index;
    _ = mode;
    // TODO: Implement via nvidia-smi persistence mode / application clocks
    // nvidia-smi -pm 1 to enable persistence
    // nvidia-smi -ac <mem_clock>,<gpu_clock> to lock clocks
    return error.NotSupported;
}

/// Unlock P-state (return to dynamic)
pub fn unlock(device_index: u32) !void {
    _ = device_index;
    // TODO: nvidia-smi -rac to reset application clocks
    return error.NotSupported;
}

/// P-state history tracking
pub const PStateHistory = struct {
    states: [64]PState,
    timestamps: [64]i64,
    count: usize,
    write_index: usize,

    pub fn init() PStateHistory {
        return PStateHistory{
            .states = [_]PState{.p15} ** 64,
            .timestamps = [_]i64{0} ** 64,
            .count = 0,
            .write_index = 0,
        };
    }

    pub fn record(self: *PStateHistory, state: PState) void {
        self.states[self.write_index] = state;
        self.timestamps[self.write_index] = std.time.milliTimestamp();
        self.write_index = (self.write_index + 1) % 64;
        if (self.count < 64) self.count += 1;
    }

    pub fn getTimeInState(self: *const PStateHistory, state: PState) i64 {
        var total: i64 = 0;
        var i: usize = 0;
        while (i < self.count) : (i += 1) {
            if (self.states[i] == state) {
                // Approximate time in state
                total += 100; // Assuming 100ms sample interval
            }
        }
        return total;
    }
};

test "pstate enum" {
    const p0 = PState.p0;
    try std.testing.expect(p0.isPerformance());
    try std.testing.expect(!p0.isIdle());

    const p12 = PState.p12;
    try std.testing.expect(!p12.isPerformance());
    try std.testing.expect(p12.isIdle());
}
