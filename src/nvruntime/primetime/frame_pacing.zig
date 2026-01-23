//! Frame Pacing Engine for PrimeTime
//!
//! Integrates with ghostVK's VRR-aware frame pacer and nvlatency for
//! full pipeline latency control. Provides frame timing, VRR coordination,
//! and latency optimization.
//!
//! ## nvvk Integration
//!
//! - VRR configuration via nvvk.vrr module
//! - LFC (Low Framerate Compensation) awareness
//! - Async sleep for non-blocking pacing
//! - Frame injection timing calculation

const std = @import("std");
const ghostvk = @import("ghostvk");
const nvvk = @import("nvvk");

// Re-export ghostVK's frame pacer as the primary implementation
pub const FramePacer = ghostvk.frame_pacer.FramePacer;
pub const FramePacerConfig = ghostvk.frame_pacer.FramePacerConfig;
pub const PacingMode = ghostvk.frame_pacer.PacingMode;

// Re-export nvvk VRR types for convenience
pub const VrrConfig = nvvk.VrrConfig;
pub const VrrSource = nvvk.VrrSource;
pub const LfcState = nvvk.LfcState;
pub const AsyncSleepContext = nvvk.AsyncSleepContext;
pub const AsyncSleepHandle = nvvk.AsyncSleepHandle;

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

// =============================================================================
// nvvk VRR Integration
// =============================================================================

/// VRR-aware frame pacing context
pub const VrrFramePacer = struct {
    allocator: std.mem.Allocator,
    base_pacer: FramePacer,
    vrr_config: ?VrrConfig = null,
    lfc_state: LfcState = .{},
    async_sleep_ctx: ?*AsyncSleepContext = null,

    // Frame timing state
    frame_count: u64 = 0,
    last_frame_time_ns: i64 = 0,
    avg_frame_time_us: u64 = 16667, // Default 60Hz

    // Statistics
    frames_in_vrr_range: u64 = 0,
    frames_in_lfc: u64 = 0,
    total_sleep_time_ns: u64 = 0,

    /// Initialize with VRR configuration from nvvk
    pub fn init(allocator: std.mem.Allocator, config: FramePacerConfig) !VrrFramePacer {
        var pacer = VrrFramePacer{
            .allocator = allocator,
            .base_pacer = try FramePacer.init(allocator, config),
        };

        // Query VRR configuration from system
        pacer.vrr_config = nvvk.vrr.queryFirstDisplay(allocator) catch null;

        if (pacer.vrr_config) |vrr| {
            std.log.info("VRR pacing initialized: {}-{}Hz (LFC: {}, source: {s})", .{
                vrr.min_hz,
                vrr.max_hz,
                vrr.lfc_supported,
                vrr.source.name(),
            });
        }

        return pacer;
    }

    /// Initialize async sleep context for non-blocking pacing
    pub fn initAsyncSleep(self: *VrrFramePacer, device: ?*anyopaque, dispatch: ?*anyopaque) !void {
        _ = self;
        _ = device;
        _ = dispatch;
        // In production: self.async_sleep_ctx = try AsyncSleepContext.init(device, dispatch, self.allocator);
    }

    /// Begin frame pacing
    pub fn beginFrame(self: *VrrFramePacer) void {
        self.base_pacer.beginFrame();
    }

    /// Wait for next frame with VRR awareness
    pub fn waitForNextFrame(self: *VrrFramePacer) void {
        const now = std.time.nanoTimestamp();
        const frame_time_ns: u64 = if (self.last_frame_time_ns > 0)
            @intCast(now - self.last_frame_time_ns)
        else
            16_666_667; // Default 60Hz

        // Update average frame time
        const frame_time_us: u64 = frame_time_ns / 1000;
        self.avg_frame_time_us = (self.avg_frame_time_us * 7 + frame_time_us) / 8;

        // Calculate current FPS
        const current_fps: u32 = if (frame_time_us > 0)
            @intCast(1_000_000 / frame_time_us)
        else
            60;

        // Update LFC state if VRR is configured
        if (self.vrr_config) |vrr| {
            self.lfc_state.update(current_fps, vrr, self.frame_count);

            if (vrr.isInRange(current_fps)) {
                self.frames_in_vrr_range += 1;
            }
            if (self.lfc_state.active) {
                self.frames_in_lfc += 1;
            }
        }

        // Delegate to base pacer for actual sleep
        self.base_pacer.waitForNextFrame();

        self.last_frame_time_ns = now;
        self.frame_count += 1;
    }

    /// Get optimal frame injection interval for frame generation
    pub fn getInjectionInterval(self: *const VrrFramePacer) u64 {
        if (self.vrr_config) |vrr| {
            return vrr.calculateInjectionInterval(self.avg_frame_time_us);
        }
        // Default: half frame at 60Hz
        return 8333;
    }

    /// Check if frame injection should be paused (LFC active)
    pub fn shouldPauseInjection(self: *const VrrFramePacer) bool {
        return self.lfc_state.shouldPauseInjection();
    }

    /// Get VRR-aware statistics
    pub fn getVrrStats(self: *const VrrFramePacer) VrrPacerStats {
        const base_stats = self.base_pacer.getStats();
        return .{
            .fps = base_stats.fps,
            .avg_frame_time_ms = base_stats.avg_frame_time_ms,
            .one_percent_low_fps = base_stats.one_percent_low_fps,
            .vrr_enabled = self.vrr_config != null and (self.vrr_config.?.enabled),
            .vrr_min_hz = if (self.vrr_config) |v| v.min_hz else 0,
            .vrr_max_hz = if (self.vrr_config) |v| v.max_hz else 0,
            .lfc_supported = if (self.vrr_config) |v| v.lfc_supported else false,
            .lfc_active = self.lfc_state.active,
            .frames_in_vrr_range = self.frames_in_vrr_range,
            .frames_in_lfc = self.frames_in_lfc,
            .total_frames = self.frame_count,
        };
    }

    pub fn deinit(self: *VrrFramePacer) void {
        // Clean up async sleep context
        if (self.async_sleep_ctx) |ctx| {
            ctx.deinit();
            self.allocator.destroy(ctx);
        }

        // Free VRR config display name if allocated
        if (self.vrr_config) |vrr| {
            if (vrr.display_name) |name| {
                self.allocator.free(name);
            }
        }

        self.base_pacer.deinit();
    }
};

/// VRR-aware pacing statistics
pub const VrrPacerStats = struct {
    fps: f32,
    avg_frame_time_ms: f32,
    one_percent_low_fps: f32,
    vrr_enabled: bool,
    vrr_min_hz: u32,
    vrr_max_hz: u32,
    lfc_supported: bool,
    lfc_active: bool,
    frames_in_vrr_range: u64,
    frames_in_lfc: u64,
    total_frames: u64,

    /// Calculate percentage of frames in VRR range
    pub fn vrrRangePercent(self: VrrPacerStats) f32 {
        if (self.total_frames == 0) return 0;
        return @as(f32, @floatFromInt(self.frames_in_vrr_range)) / @as(f32, @floatFromInt(self.total_frames)) * 100.0;
    }

    /// Calculate percentage of frames in LFC mode
    pub fn lfcPercent(self: VrrPacerStats) f32 {
        if (self.total_frames == 0) return 0;
        return @as(f32, @floatFromInt(self.frames_in_lfc)) / @as(f32, @floatFromInt(self.total_frames)) * 100.0;
    }
};

/// Query VRR availability from nvvk
pub fn isVrrAvailable(allocator: std.mem.Allocator) bool {
    return nvvk.vrr.isVrrAvailable(allocator);
}

/// Get VRR system status
pub fn getVrrStatus(allocator: std.mem.Allocator) !nvvk.VrrStatus {
    return nvvk.vrr.getSystemStatus(allocator);
}

/// Create a VRR-optimized frame pacer
pub fn createVrrAwarePacer(allocator: std.mem.Allocator, target_fps: u32) !VrrFramePacer {
    return VrrFramePacer.init(allocator, .{
        .target_fps = target_fps,
        .mode = .hybrid,
        .vrr_enabled = true,
        .busy_wait_threshold_ns = 500_000, // 0.5ms for gaming
    });
}

test "vrr pacer stats" {
    const stats = VrrPacerStats{
        .fps = 120,
        .avg_frame_time_ms = 8.33,
        .one_percent_low_fps = 100,
        .vrr_enabled = true,
        .vrr_min_hz = 48,
        .vrr_max_hz = 144,
        .lfc_supported = true,
        .lfc_active = false,
        .frames_in_vrr_range = 90,
        .frames_in_lfc = 10,
        .total_frames = 100,
    };

    try std.testing.expectEqual(@as(f32, 90.0), stats.vrrRangePercent());
    try std.testing.expectEqual(@as(f32, 10.0), stats.lfcPercent());
}
