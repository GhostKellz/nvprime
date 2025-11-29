//! PrimeTime - NVIDIA-Native Gaming Compositor
//!
//! A wlroots-based gaming compositor designed as a Gamescope alternative.
//! Built to surpass and supersede Gamescope with NVIDIA-first optimizations.
//!
//! Features:
//! - NVIDIA-optimized (direct scanout, VRR, HDR)
//! - Low latency frame pacing
//! - FSR/NIS upscaling support
//! - Integration with nvlatency, nvsync, nvhud
//!
//! This is the compositor core that VENOM builds upon.

const std = @import("std");
const frame_pacing = @import("frame_pacing.zig");

// DRM is optional - only import when building with -Ddrm=true
// const drm = @import("drm.zig");

pub const version = "0.1.0-dev";

/// Compositor state
pub const CompositorState = enum {
    uninitialized,
    stopped,
    starting,
    running,
    error_state,
};

/// Upscaling methods
pub const Upscaler = enum {
    none,
    fsr1, // AMD FidelityFX Super Resolution 1.0
    fsr2, // AMD FSR 2.x
    nis, // NVIDIA Image Scaling
    dlss, // NVIDIA DLSS (if supported)

    pub fn description(self: Upscaler) []const u8 {
        return switch (self) {
            .none => "Native (no upscaling)",
            .fsr1 => "AMD FSR 1.0",
            .fsr2 => "AMD FSR 2.x",
            .nis => "NVIDIA Image Scaling",
            .dlss => "NVIDIA DLSS",
        };
    }
};

/// Compositor configuration
pub const Config = struct {
    /// Target output width (0 = native)
    width: u32 = 0,
    /// Target output height (0 = native)
    height: u32 = 0,
    /// Internal render resolution width (for upscaling)
    render_width: u32 = 0,
    /// Internal render resolution height
    render_height: u32 = 0,
    /// Target refresh rate (0 = max available)
    refresh_hz: u32 = 0,
    /// Enable VRR (G-Sync/FreeSync)
    vrr: bool = true,
    /// Enable HDR passthrough
    hdr: bool = true,
    /// Allow tearing (for competitive gaming)
    allow_tearing: bool = false,
    /// Upscaling method
    upscaler: Upscaler = .none,
    /// Frame limiter (0 = disabled)
    fps_limit: u32 = 0,
    /// Pacing mode
    pacing_mode: frame_pacing.PacingMode = .vrr,
    /// Force specific output (e.g., "DP-1", null = auto)
    output_name: ?[]const u8 = null,
    /// Enable performance overlay
    show_overlay: bool = false,
    /// Grab keyboard exclusively
    grab_keyboard: bool = true,
    /// Grab mouse exclusively
    grab_mouse: bool = true,
};

/// Output/display information
pub const OutputInfo = struct {
    name: [32]u8 = [_]u8{0} ** 32,
    name_len: usize = 0,
    width: u32 = 0,
    height: u32 = 0,
    refresh_hz: u32 = 0,
    vrr_capable: bool = false,
    hdr_capable: bool = false,
    connected: bool = false,

    pub fn getName(self: *const OutputInfo) []const u8 {
        return self.name[0..self.name_len];
    }
};

/// Latency statistics
pub const LatencyStats = struct {
    /// Total input-to-display latency (ms)
    total_latency_ms: f32 = 0,
    /// CPU frame time (ms)
    cpu_frame_ms: f32 = 0,
    /// GPU render time (ms)
    gpu_render_ms: f32 = 0,
    /// Compositor overhead (ms)
    compositor_ms: f32 = 0,
    /// Display scanout time (ms)
    scanout_ms: f32 = 0,
};

/// Performance statistics
pub const PerfStats = struct {
    /// Current FPS
    fps: f32 = 0,
    /// Average frame time (ms)
    frame_time_ms: f32 = 0,
    /// 1% low FPS
    one_percent_low_fps: f32 = 0,
    /// 0.1% low FPS
    point_one_percent_low_fps: f32 = 0,
    /// Current VRR refresh rate
    vrr_hz: u32 = 0,
    /// Frame number
    frame_count: u64 = 0,
};

/// Game capture mode for streaming/recording
pub const CaptureMode = enum {
    disabled,
    zero_copy, // DMA-BUF sharing (preferred)
    copy, // Fallback copy-based capture
};

/// The compositor instance
pub const Compositor = struct {
    allocator: std.mem.Allocator,
    config: Config,
    state: CompositorState = .uninitialized,

    // Frame pacing
    pacer: frame_pacing.FramePacer,

    // Current output info
    current_output: OutputInfo = .{},

    // Wayland socket name
    socket_name: [108]u8 = [_]u8{0} ** 108,
    socket_name_len: usize = 0,

    // Running game PID
    game_pid: ?std.posix.pid_t = null,

    /// Initialize the compositor
    pub fn init(allocator: std.mem.Allocator, config: Config) !*Compositor {
        const self = try allocator.create(Compositor);
        self.* = Compositor{
            .allocator = allocator,
            .config = config,
            .pacer = frame_pacing.FramePacer.init(if (config.fps_limit > 0) config.fps_limit else 60),
        };

        self.pacer.setMode(config.pacing_mode);

        // TODO: Initialize DRM device for mode queries when -Ddrm=true
        // For now, use stub output detection

        self.state = .stopped;
        return self;
    }

    /// Deinitialize the compositor
    pub fn deinit(self: *Compositor) void {
        if (self.state == .running) {
            self.stop() catch {};
        }

        self.allocator.destroy(self);
    }

    /// Start the compositor
    pub fn start(self: *Compositor) !void {
        if (self.state == .running) return;

        self.state = .starting;

        // In a full implementation, we would:
        // 1. Create wl_display
        // 2. Create wlr_backend
        // 3. Create wlr_renderer
        // 4. Set up outputs
        // 5. Create scene graph
        // 6. Set up XDG shell
        // 7. Start backend

        // For now, mark as running (stub)
        self.state = .running;
    }

    /// Stop the compositor
    pub fn stop(self: *Compositor) !void {
        if (self.state != .running) return;

        // Kill running game if any
        if (self.game_pid) |pid| {
            std.posix.kill(pid, std.posix.SIG.TERM) catch {};
            self.game_pid = null;
        }

        self.state = .stopped;
    }

    /// Run a game within the compositor
    pub fn runGame(self: *Compositor, argv: []const []const u8, env: ?*const std.process.EnvMap) !void {
        if (self.state != .running) {
            try self.start();
        }

        // Set up environment for the game
        var child_env = if (env) |e| e.* else try std.process.getEnvMap(self.allocator);
        defer if (env == null) child_env.deinit();

        // Set WAYLAND_DISPLAY to our socket
        if (self.socket_name_len > 0) {
            try child_env.put("WAYLAND_DISPLAY", self.socket_name[0..self.socket_name_len]);
        }

        // Set gaming-related env vars
        try child_env.put("__GL_GSYNC_ALLOWED", if (self.config.vrr) "1" else "0");
        try child_env.put("__GL_VRR_ALLOWED", if (self.config.vrr) "1" else "0");

        if (self.config.allow_tearing) {
            try child_env.put("__GL_ALLOW_FAKED_GLXSWAPINTERVAL", "1");
        }

        // Spawn the game process
        var child = std.process.Child.init(argv, self.allocator);
        child.env_map = &child_env;

        try child.spawn();
        self.game_pid = child.id;
    }

    /// Get current state
    pub fn getState(self: *const Compositor) CompositorState {
        return self.state;
    }

    /// Get output info
    pub fn getOutputInfo(self: *const Compositor) OutputInfo {
        return self.current_output;
    }

    /// Get latency stats
    pub fn getLatencyStats(self: *const Compositor) LatencyStats {
        return LatencyStats{
            .total_latency_ms = self.pacer.getAverageLatencyMs(),
            .cpu_frame_ms = self.pacer.getAverageFrameTimeMs(),
        };
    }

    /// Get performance stats
    pub fn getPerfStats(self: *const Compositor) PerfStats {
        return PerfStats{
            .fps = self.pacer.getCurrentFps(),
            .frame_time_ms = self.pacer.getAverageFrameTimeMs(),
            .one_percent_low_fps = self.pacer.getOnePercentLowFps(),
            .vrr_hz = self.pacer.getOptimalVrrHz(),
            .frame_count = self.pacer.frame_number,
        };
    }

    /// Set VRR enabled
    pub fn setVrr(self: *Compositor, enabled: bool) void {
        self.config.vrr = enabled;
        // TODO: When DRM backend is enabled (-Ddrm=true), set VRR on hardware
    }

    /// Set frame limit
    pub fn setFrameLimit(self: *Compositor, fps: u32) void {
        self.config.fps_limit = fps;
        self.pacer.setTargetFps(fps);
        if (fps > 0) {
            self.pacer.setMode(.limited);
        }
    }

    /// Set upscaler
    pub fn setUpscaler(self: *Compositor, upscaler: Upscaler) void {
        self.config.upscaler = upscaler;
    }

    /// Check if game is still running
    pub fn isGameRunning(self: *const Compositor) bool {
        if (self.game_pid) |pid| {
            // Check if process exists
            const result = std.posix.kill(pid, 0);
            return result != error.NoSuchProcess;
        }
        return false;
    }

    /// Wait for game to exit
    pub fn waitForGame(self: *Compositor) !u32 {
        if (self.game_pid) |pid| {
            const result = std.posix.waitpid(pid, 0);
            self.game_pid = null;
            return result.status;
        }
        return 0;
    }
};

// ============================================================================
// Module-level convenience functions
// ============================================================================

var global_compositor: ?*Compositor = null;

/// Get global compositor state
pub fn getState() CompositorState {
    if (global_compositor) |comp| {
        return comp.getState();
    }
    return .uninitialized;
}

/// Initialize global compositor
pub fn init(allocator: std.mem.Allocator, config: Config) !void {
    if (global_compositor != null) return error.AlreadyInitialized;
    global_compositor = try Compositor.init(allocator, config);
}

/// Deinitialize global compositor
pub fn deinit() void {
    if (global_compositor) |comp| {
        comp.deinit();
        global_compositor = null;
    }
}

/// Start global compositor
pub fn start(config: Config) !void {
    if (global_compositor) |comp| {
        comp.config = config;
        try comp.start();
    } else {
        return error.NotInitialized;
    }
}

/// Stop global compositor
pub fn stop() !void {
    if (global_compositor) |comp| {
        try comp.stop();
    }
}

/// Run a game
pub fn run(command: []const u8) !void {
    if (global_compositor) |comp| {
        const argv = [_][]const u8{command};
        try comp.runGame(&argv, null);
    } else {
        return error.NotInitialized;
    }
}

/// Get latency stats from global compositor
pub fn getLatencyStats() !LatencyStats {
    if (global_compositor) |comp| {
        return comp.getLatencyStats();
    }
    return error.NotInitialized;
}

/// Get performance stats from global compositor
pub fn getPerfStats() !PerfStats {
    if (global_compositor) |comp| {
        return comp.getPerfStats();
    }
    return error.NotInitialized;
}

// ============================================================================
// Tests
// ============================================================================

test "compositor config" {
    const config = Config{
        .width = 2560,
        .height = 1440,
        .refresh_hz = 165,
        .vrr = true,
    };
    try std.testing.expect(config.vrr);
    try std.testing.expectEqual(@as(u32, 165), config.refresh_hz);
}

test "upscaler descriptions" {
    try std.testing.expectEqualStrings("NVIDIA Image Scaling", Upscaler.nis.description());
    try std.testing.expectEqualStrings("Native (no upscaling)", Upscaler.none.description());
}

test "compositor state" {
    try std.testing.expectEqual(CompositorState.uninitialized, getState());
}
