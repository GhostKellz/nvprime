//! Frame Pacing Engine for PrimeTime
//!
//! Integrates with ghostVK's VRR-aware frame pacer and nvlatency for
//! full pipeline latency control. Provides frame timing, VRR coordination,
//! and latency optimization.

const std = @import("std");
const ghostvk = @import("ghostvk");

// Re-export ghostVK's frame pacer as the primary implementation
pub const FramePacer = ghostvk.frame_pacer.FramePacer;
pub const FramePacerConfig = ghostvk.frame_pacer.FramePacerConfig;
pub const PacingMode = ghostvk.frame_pacer.PacingMode;

/// Frame statistics for detailed timing analysis
pub const FrameStats = struct {
    /// Frame number
    frame_number: u64 = 0,
    /// CPU frame start time (ns)
    cpu_start_ns: u64 = 0,
    /// CPU frame end time (ns)
    cpu_end_ns: u64 = 0,
    /// GPU submit time (ns)
    gpu_submit_ns: u64 = 0,
    /// GPU complete time (ns)
    gpu_complete_ns: u64 = 0,
    /// Present/scanout time (ns)
    present_ns: u64 = 0,

    /// Calculate CPU frame time
    pub fn cpuTimeNs(self: *const FrameStats) u64 {
        if (self.cpu_end_ns > self.cpu_start_ns) {
            return self.cpu_end_ns - self.cpu_start_ns;
        }
        return 0;
    }

    /// Calculate GPU time
    pub fn gpuTimeNs(self: *const FrameStats) u64 {
        if (self.gpu_complete_ns > self.gpu_submit_ns) {
            return self.gpu_complete_ns - self.gpu_submit_ns;
        }
        return 0;
    }

    /// Calculate total latency
    pub fn totalLatencyNs(self: *const FrameStats) u64 {
        if (self.present_ns > self.cpu_start_ns) {
            return self.present_ns - self.cpu_start_ns;
        }
        return 0;
    }

    /// Get total latency in milliseconds
    pub fn totalLatencyMs(self: *const FrameStats) f32 {
        return @as(f32, @floatFromInt(self.totalLatencyNs())) / 1_000_000.0;
    }
};

/// Rolling statistics buffer for frame time analysis
pub fn RollingStats(comptime N: usize) type {
    return struct {
        const Self = @This();

        values: [N]f32 = [_]f32{0} ** N,
        index: usize = 0,
        count: usize = 0,

        pub fn push(self: *Self, value: f32) void {
            self.values[self.index] = value;
            self.index = (self.index + 1) % N;
            if (self.count < N) self.count += 1;
        }

        pub fn average(self: *const Self) f32 {
            if (self.count == 0) return 0;
            var sum: f32 = 0;
            for (self.values[0..self.count]) |v| {
                sum += v;
            }
            return sum / @as(f32, @floatFromInt(self.count));
        }

        pub fn min(self: *const Self) f32 {
            if (self.count == 0) return 0;
            var m: f32 = self.values[0];
            for (self.values[1..self.count]) |v| {
                if (v < m) m = v;
            }
            return m;
        }

        pub fn max(self: *const Self) f32 {
            if (self.count == 0) return 0;
            var m: f32 = self.values[0];
            for (self.values[1..self.count]) |v| {
                if (v > m) m = v;
            }
            return m;
        }

        /// Calculate percentile (0-100)
        pub fn percentile(self: *const Self, p: f32) f32 {
            if (self.count == 0) return 0;
            if (self.count == 1) return self.values[0];

            // Copy and sort
            var sorted: [N]f32 = undefined;
            @memcpy(sorted[0..self.count], self.values[0..self.count]);
            std.mem.sort(f32, sorted[0..self.count], {}, std.sort.asc(f32));

            const idx = @as(usize, @intFromFloat(@as(f32, @floatFromInt(self.count - 1)) * p / 100.0));
            return sorted[idx];
        }

        /// Get 1% low (99th percentile of frame times)
        pub fn onePercentLow(self: *const Self) f32 {
            return self.percentile(99);
        }
    };
}

/// Pacer statistics for monitoring
pub const PacerStats = struct {
    /// Current FPS
    fps: f32 = 0,
    /// Average frame time (ms)
    avg_frame_time_ms: f32 = 0,
    /// 1% low FPS
    one_percent_low_fps: f32 = 0,
    /// VRR enabled
    vrr_enabled: bool = false,
    /// VRR range (min, max Hz)
    vrr_range: [2]u32 = .{ 0, 0 },
    /// Total frames paced
    frames_paced: u64 = 0,
    /// Total sleep time (ns)
    total_sleep_ns: u64 = 0,
};

/// High precision sleep
pub fn precisionSleepNs(ns: u64) void {
    if (ns == 0) return;

    const seconds: i64 = @intCast(ns / 1_000_000_000);
    const nanos: i64 = @intCast(ns % 1_000_000_000);
    std.posix.nanosleep(seconds, nanos);
}

/// Create a frame pacer with default gaming settings
pub fn createGamingPacer(allocator: std.mem.Allocator, target_fps: u32) !FramePacer {
    return FramePacer.init(allocator, .{
        .target_fps = target_fps,
        .mode = .hybrid,
        .busy_wait_threshold_ns = 500_000, // 0.5ms for low latency
    });
}

/// Create a frame pacer optimized for VRR displays
pub fn createVrrPacer(allocator: std.mem.Allocator) !FramePacer {
    return FramePacer.init(allocator, .{
        .target_fps = 0, // Unlimited, let VRR handle it
        .mode = .hybrid,
        .vrr_enabled = true,
    });
}

test "frame stats" {
    var stats = FrameStats{
        .frame_number = 1,
        .cpu_start_ns = 1000,
        .cpu_end_ns = 2000,
        .gpu_submit_ns = 2000,
        .gpu_complete_ns = 5000,
        .present_ns = 6000,
    };

    try std.testing.expectEqual(@as(u64, 1000), stats.cpuTimeNs());
    try std.testing.expectEqual(@as(u64, 3000), stats.gpuTimeNs());
    try std.testing.expectEqual(@as(u64, 5000), stats.totalLatencyNs());
}

test "rolling stats" {
    var stats: RollingStats(10) = .{};
    stats.push(10.0);
    stats.push(20.0);
    stats.push(30.0);

    try std.testing.expectEqual(@as(f32, 20.0), stats.average());
    try std.testing.expectEqual(@as(f32, 10.0), stats.min());
    try std.testing.expectEqual(@as(f32, 30.0), stats.max());
}
