//! Frame Pacing Engine for PrimeTime
//!
//! Handles frame timing, VRR coordination, and latency optimization.
//! Integrates with nvlatency and nvsync for full pipeline control.

const std = @import("std");

/// Frame pacing mode
pub const PacingMode = enum {
    /// No frame pacing - present as fast as possible
    none,
    /// VSync - wait for vertical blank
    vsync,
    /// Adaptive VSync - VSync when above target, tear when below
    adaptive,
    /// VRR - Variable Refresh Rate (G-Sync/FreeSync)
    vrr,
    /// Frame limiter - cap at specific FPS
    limited,
};

/// Frame statistics
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

/// Rolling statistics buffer
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

/// Frame pacer state
pub const FramePacer = struct {
    mode: PacingMode = .vsync,
    target_fps: u32 = 60,
    target_frame_ns: u64 = 16_666_667, // 60 FPS
    vrr_min_hz: u32 = 30,
    vrr_max_hz: u32 = 144,

    last_present_ns: u64 = 0,
    frame_number: u64 = 0,

    // Statistics (last 300 frames = ~5 seconds at 60fps)
    frame_times: RollingStats(300) = .{},
    latencies: RollingStats(300) = .{},

    /// Initialize with target FPS
    pub fn init(target_fps: u32) FramePacer {
        return FramePacer{
            .target_fps = target_fps,
            .target_frame_ns = if (target_fps > 0) 1_000_000_000 / target_fps else 0,
        };
    }

    /// Set pacing mode
    pub fn setMode(self: *FramePacer, mode: PacingMode) void {
        self.mode = mode;
    }

    /// Set target FPS (for limited mode)
    pub fn setTargetFps(self: *FramePacer, fps: u32) void {
        self.target_fps = fps;
        self.target_frame_ns = if (fps > 0) 1_000_000_000 / fps else 0;
    }

    /// Set VRR range
    pub fn setVrrRange(self: *FramePacer, min_hz: u32, max_hz: u32) void {
        self.vrr_min_hz = min_hz;
        self.vrr_max_hz = max_hz;
    }

    /// Record frame completion
    pub fn recordFrame(self: *FramePacer, stats: *const FrameStats) void {
        const frame_time_ms = @as(f32, @floatFromInt(stats.cpuTimeNs())) / 1_000_000.0;
        const latency_ms = stats.totalLatencyMs();

        self.frame_times.push(frame_time_ms);
        self.latencies.push(latency_ms);

        if (stats.present_ns > 0) {
            self.last_present_ns = stats.present_ns;
        }
        self.frame_number = stats.frame_number;
    }

    /// Calculate how long to sleep before next frame (for frame limiting)
    pub fn calculateSleepNs(self: *const FramePacer, current_ns: u64) u64 {
        if (self.mode != .limited or self.target_frame_ns == 0) {
            return 0;
        }

        if (self.last_present_ns == 0) return 0;

        const elapsed = current_ns - self.last_present_ns;
        if (elapsed >= self.target_frame_ns) return 0;

        return self.target_frame_ns - elapsed;
    }

    /// Get current FPS
    pub fn getCurrentFps(self: *const FramePacer) f32 {
        const avg_frame_time = self.frame_times.average();
        if (avg_frame_time <= 0) return 0;
        return 1000.0 / avg_frame_time;
    }

    /// Get average frame time (ms)
    pub fn getAverageFrameTimeMs(self: *const FramePacer) f32 {
        return self.frame_times.average();
    }

    /// Get 1% low FPS
    pub fn getOnePercentLowFps(self: *const FramePacer) f32 {
        const worst_frame_time = self.frame_times.onePercentLow();
        if (worst_frame_time <= 0) return 0;
        return 1000.0 / worst_frame_time;
    }

    /// Get average latency (ms)
    pub fn getAverageLatencyMs(self: *const FramePacer) f32 {
        return self.latencies.average();
    }

    /// Determine optimal VRR refresh rate for current frame time
    pub fn getOptimalVrrHz(self: *const FramePacer) u32 {
        const avg_frame_time_ms = self.frame_times.average();
        if (avg_frame_time_ms <= 0) return self.vrr_max_hz;

        const target_hz = @as(u32, @intFromFloat(1000.0 / avg_frame_time_ms));

        // Clamp to VRR range
        if (target_hz < self.vrr_min_hz) return self.vrr_min_hz;
        if (target_hz > self.vrr_max_hz) return self.vrr_max_hz;
        return target_hz;
    }
};

/// High precision sleep
pub fn precisionSleepNs(ns: u64) void {
    if (ns == 0) return;

    const ts = std.posix.timespec{
        .sec = @intCast(ns / 1_000_000_000),
        .nsec = @intCast(ns % 1_000_000_000),
    };
    _ = std.posix.nanosleep(ts, null);
}

test "frame pacer" {
    var pacer = FramePacer.init(60);
    try std.testing.expectEqual(@as(u64, 16_666_667), pacer.target_frame_ns);

    pacer.setTargetFps(144);
    try std.testing.expectEqual(@as(u32, 144), pacer.target_fps);
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
