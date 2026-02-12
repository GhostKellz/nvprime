//! PrimeTime - NVIDIA-Native Gaming Compositor
//!
//! A wlroots-based gaming compositor designed as a Gamescope alternative.
//! Built to surpass and supersede Gamescope with NVIDIA-first optimizations.
//!
//! Features:
//! - NVIDIA-optimized (direct scanout, VRR, HDR)
//! - Low latency frame pacing via ghostVK
//! - VRR-aware frame injection via nvvk
//! - FSR/NIS upscaling support
//! - Integration with nvlatency, nvsync, nvhud
//! - Vulkan 1.4 support for push descriptors
//!
//! This is the compositor core that VENOM builds upon.

const std = @import("std");
const frame_pacing = @import("frame_pacing.zig");
const drm = @import("drm.zig");
const nvvk = @import("nvvk");
const nvsync = @import("nvsync");
const ghostvk = @import("ghostvk");
const nvhud = @import("nvhud");

// Vulkan constants (from Vulkan 1.4 spec)
const VK_IMAGE_LAYOUT_PRESENT_SRC_KHR: u32 = 1000001002;

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

/// Config pacing mode (high-level, maps to ghostVK's PacingMode)
pub const ConfigPacingMode = enum {
    /// No frame pacing (unlimited)
    none,
    /// VSync-like CPU sleep
    vsync,
    /// Adaptive sync (hybrid pacing)
    adaptive,
    /// VRR-optimized (hybrid pacing with VRR awareness)
    vrr,
    /// FPS limited (CPU sleep to target)
    limited,
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
    pacing_mode: ConfigPacingMode = .vrr,
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

/// Swapchain presentation mode
pub const PresentMode = enum {
    /// No Vulkan presentation (DRM direct scanout only)
    none,
    /// Use ghostVK for Vulkan swapchain management
    ghostvk,
    /// External swapchain (provided by application)
    external,
};

/// Swapchain info for compositor-managed presentation
pub const SwapchainInfo = struct {
    /// Swapchain image count
    image_count: u32 = 0,
    /// Swapchain format
    format: u32 = 0,
    /// Swapchain extent
    width: u32 = 0,
    height: u32 = 0,
    /// HDR color space
    hdr_colorspace: ghostvk.hdr.HdrColorSpace = .srgb,
    /// Current image index
    current_image: u32 = 0,
};

/// The compositor instance
pub const Compositor = struct {
    allocator: std.mem.Allocator,
    config: Config,
    state: CompositorState = .uninitialized,

    // Frame pacing (ghostVK-powered with VRR awareness)
    pacer: ?frame_pacing.FramePacer = null,

    // DRM backend for display control
    drm_backend: ?drm.DrmBackend = null,

    // Current output info
    current_output: OutputInfo = .{},

    // VRR state from nvvk
    vrr_config: ?nvvk.VrrConfig = null,

    // GhostVK runtime for Vulkan swapchain management
    ghostvk_runtime: ?ghostvk.GhostVK = null,
    present_mode: PresentMode = .none,
    swapchain_info: SwapchainInfo = .{},

    // nvhud overlay integration
    overlay: ?*nvhud.Overlay = null,
    metrics_collector: ?*nvhud.Collector = null,
    overlay_config: nvhud.Config = .{},
    overlay_enabled: bool = false,

    // Wayland socket name
    socket_name: [108]u8 = [_]u8{0} ** 108,
    socket_name_len: usize = 0,

    // Running game PID
    game_pid: ?std.posix.pid_t = null,

    // Frame injection state
    frame_count: u64 = 0,
    last_frame_time_ns: u64 = 0,

    /// Initialize the compositor
    pub fn init(allocator: std.mem.Allocator, config: Config) !*Compositor {
        const self = try allocator.create(Compositor);
        self.* = Compositor{
            .allocator = allocator,
            .config = config,
        };

        // Initialize ghostVK-powered frame pacer with VRR awareness
        const pacing_mode: frame_pacing.PacingMode = switch (config.pacing_mode) {
            .none => .unlimited,
            .vsync => .cpu_sleep,
            .adaptive => .hybrid,
            .vrr => .hybrid,
            .limited => .cpu_sleep,
        };

        self.pacer = frame_pacing.FramePacer.init(allocator, .{
            .target_fps = config.fps_limit,
            .mode = pacing_mode,
            .vrr_enabled = config.vrr,
        });

        // Initialize DRM backend for display control
        self.drm_backend = drm.DrmBackend.init(allocator) catch |err| blk: {
            std.log.warn("DRM backend unavailable: {} - using fallback", .{err});
            break :blk null;
        };

        // Get VRR config from DRM backend or query directly
        if (self.drm_backend) |*backend| {
            self.vrr_config = backend.getVrrConfig();

            // Populate output info from DRM
            if (backend.getPrimaryOutput()) |output| {
                if (output.mode) |mode| {
                    self.current_output.width = mode.width;
                    self.current_output.height = mode.height;
                    self.current_output.refresh_hz = mode.refresh_hz;
                }
                self.current_output.vrr_capable = output.vrr.supported;
                self.current_output.connected = output.active;
            }
        } else {
            // Fallback: try to get VRR config directly from nvvk
            self.vrr_config = nvvk.vrr.queryFirstDisplay(allocator) catch null;
        }

        self.state = .stopped;
        return self;
    }

    /// Deinitialize the compositor
    pub fn deinit(self: *Compositor) void {
        if (self.state == .running) {
            self.stop() catch {};
        }

        // Clean up nvhud overlay
        if (self.overlay) |overlay_ptr| {
            overlay_ptr.deinit();
            self.allocator.destroy(overlay_ptr);
            self.overlay = null;
        }
        if (self.metrics_collector) |collector| {
            collector.deinit();
            self.allocator.destroy(collector);
            self.metrics_collector = null;
        }

        // Clean up ghostVK runtime
        if (self.ghostvk_runtime) |*gvk| {
            gvk.deinit();
            self.ghostvk_runtime = null;
        }

        // Clean up DRM backend
        if (self.drm_backend) |*backend| {
            backend.deinit();
        }

        // Clean up VRR config if not from DRM backend
        if (self.drm_backend == null) {
            if (self.vrr_config) |vrr| {
                if (vrr.display_name) |name| {
                    self.allocator.free(name);
                }
            }
        }

        // Clean up frame pacer
        if (self.pacer) |*p| {
            p.deinit();
        }

        self.allocator.destroy(self);
    }

    // =========================================================================
    // GhostVK Swapchain Integration
    // =========================================================================

    /// Initialize ghostVK runtime for Vulkan swapchain management
    /// This enables the compositor to manage presentation via ghostVK
    pub fn initGhostVK(self: *Compositor) !void {
        if (self.ghostvk_runtime != null) return; // Already initialized

        const gvk_options = ghostvk.InitOptions{
            .enable_validation = false, // Disable for production
            .application_name = "PrimeTime",
            .prefer_hdr = self.config.hdr,
            .enable_frame_pacing = true,
            .target_fps = self.config.fps_limit,
            .pacing_mode = switch (self.config.pacing_mode) {
                .none => .unlimited,
                .vsync => .cpu_sleep,
                .adaptive, .vrr => .hybrid,
                .limited => .cpu_sleep,
            },
        };

        self.ghostvk_runtime = ghostvk.GhostVK.init(self.allocator, gvk_options) catch |err| {
            std.log.err("Failed to initialize ghostVK: {}", .{err});
            return err;
        };

        // Update swapchain info from ghostVK
        if (self.ghostvk_runtime) |gvk| {
            self.swapchain_info = .{
                .image_count = @intCast(gvk.swapchain_images.len),
                .format = @intFromEnum(gvk.swapchain_format),
                .width = gvk.swapchain_extent.width,
                .height = gvk.swapchain_extent.height,
                .hdr_colorspace = gvk.swapchain_colorspace,
            };
            self.present_mode = .ghostvk;

            // Register swapchain images with nvvk layer for frame injection
            if (gvk.device) |device| {
                if (gvk.swapchain_images.len > 0) {
                    const registered = nvvk.nvvk_register_swapchain_images(
                        @ptrCast(device),
                        @intFromPtr(gvk.swapchain),
                        @ptrCast(gvk.swapchain_images.ptr),
                        @intCast(gvk.swapchain_images.len),
                        gvk.swapchain_extent.width,
                        gvk.swapchain_extent.height,
                        @intFromEnum(gvk.swapchain_format),
                    );
                    if (registered) {
                        std.log.info("Registered {} swapchain images with nvvk for frame injection", .{gvk.swapchain_images.len});
                    } else {
                        std.log.warn("Failed to register swapchain images with nvvk - frame injection unavailable", .{});
                    }
                }
            }

            std.log.info("ghostVK swapchain initialized: {}x{} ({} images, HDR: {s})", .{
                gvk.swapchain_extent.width,
                gvk.swapchain_extent.height,
                gvk.swapchain_images.len,
                @tagName(gvk.swapchain_colorspace),
            });
        }
    }

    /// Check if ghostVK swapchain is available
    pub fn hasGhostVKSwapchain(self: *const Compositor) bool {
        return self.ghostvk_runtime != null and self.present_mode == .ghostvk;
    }

    /// Get ghostVK swapchain info
    pub fn getSwapchainInfo(self: *const Compositor) SwapchainInfo {
        return self.swapchain_info;
    }

    /// Begin a frame with ghostVK
    /// Returns the acquired swapchain image index, or null if using external presentation
    pub fn beginFrame(self: *Compositor) ?u32 {
        // Start frame pacing
        if (self.pacer) |*p| {
            p.beginFrame();
        }

        // If using ghostVK, acquire next image
        if (self.ghostvk_runtime) |*gvk| {
            // ghostVK handles image acquisition internally
            self.swapchain_info.current_image = gvk.current_frame;
            return gvk.current_frame;
        }

        return null;
    }

    /// End a frame with ghostVK
    /// Handles frame pacing and presentation
    pub fn endFrame(self: *Compositor) void {
        self.frame_count += 1;
        // Use clock_gettime for the current time
        var ts: std.os.linux.timespec = undefined;
        _ = std.os.linux.clock_gettime(.MONOTONIC, &ts);
        const sec_ns: u64 = @intCast(@max(0, ts.sec) * std.time.ns_per_s);
        const nsec: u64 = @intCast(@max(0, ts.nsec));
        self.last_frame_time_ns = sec_ns + nsec;

        // End frame pacing
        if (self.pacer) |*p| {
            p.endFrame();
        }

        // ghostVK handles presentation internally via its render loop

        // Notify nvvk of the last rendered image for frame injection
        if (self.ghostvk_runtime) |gvk| {
            if (gvk.device) |device| {
                if (gvk.swapchain != null and gvk.swapchain_images.len > 0) {
                    // Get the last presented image from ghostVK using the index
                    const image_idx = gvk.last_presented_image;
                    if (image_idx < gvk.swapchain_images.len) {
                        nvvk.nvvk_notify_rendered_image(
                            @ptrCast(device),
                            @intFromPtr(gvk.swapchain),
                            @ptrCast(gvk.swapchain_images[image_idx]),
                            VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
                        );
                    }
                }
            }
        }
    }

    /// Get the ghostVK frame pacer stats
    pub fn getGhostVKPacerStats(self: *const Compositor) ?ghostvk.frame_pacer.FramePacerStats {
        if (self.ghostvk_runtime) |gvk| {
            if (gvk.pacer) |*pacer| {
                return pacer.getStats();
            }
        }
        return null;
    }

    /// Synchronize VRR settings between DRM backend and ghostVK
    pub fn syncVrrSettings(self: *Compositor) void {
        // Get VRR config from DRM backend if available
        var vrr_enabled = self.config.vrr;
        var min_hz: u32 = 48;
        var max_hz: u32 = 165;

        if (self.drm_backend) |*backend| {
            if (backend.getVrrConfig()) |vrr| {
                vrr_enabled = vrr.enabled;
                min_hz = vrr.min_hz;
                max_hz = vrr.max_hz;
            }
        } else if (self.vrr_config) |vrr| {
            vrr_enabled = vrr.enabled;
            min_hz = vrr.min_hz;
            max_hz = vrr.max_hz;
        }

        // Update ghostVK pacer if available
        if (self.ghostvk_runtime) |*gvk| {
            if (gvk.pacer) |*pacer| {
                pacer.config.vrr_enabled = vrr_enabled;
                pacer.config.vrr_min_hz = min_hz;
                pacer.config.vrr_max_hz = max_hz;
            }
        }

        // Update primetime pacer if available
        if (self.pacer) |*pacer| {
            pacer.config.vrr_enabled = vrr_enabled;
            pacer.config.vrr_min_hz = min_hz;
            pacer.config.vrr_max_hz = max_hz;
        }
    }

    // =========================================================================
    // nvhud Overlay Integration
    // =========================================================================

    /// Initialize the nvhud overlay system
    pub fn initOverlay(self: *Compositor) !void {
        if (self.overlay != null) return; // Already initialized

        // Check if overlay should be enabled
        if (!self.config.show_overlay and !nvhud.isOverlayEnabled()) {
            return;
        }

        // Load default config with standard gaming HUD options
        self.overlay_config = nvhud.Config{
            .position = .top_left,
            .show_fps = true,
            .show_frametime = true,
            .show_gpu_temp = true,
            .show_gpu_util = true,
            .show_vram = true,
            .show_cpu = false,
            .font_size = 16,
        };

        // Create metrics collector
        const collector = try self.allocator.create(nvhud.Collector);
        collector.* = nvhud.createCollector();
        self.metrics_collector = collector;

        // Create overlay (Vulkan context from ghostVK for future GPU-accelerated rendering)
        const overlay_ptr = try self.allocator.create(nvhud.Overlay);
        if (self.ghostvk_runtime) |_| {
            // TODO: Pass Vulkan context when nvhud supports GPU-accelerated overlay
            // gvk.device, gvk.physical_device, gvk.graphics_queue_family
            overlay_ptr.* = nvhud.createOverlayWithConfig(self.allocator, self.overlay_config);
        } else {
            // Create overlay without Vulkan context
            overlay_ptr.* = nvhud.createOverlayWithConfig(self.allocator, self.overlay_config);
        }
        self.overlay = overlay_ptr;
        self.overlay_enabled = true;

        std.log.info("nvhud overlay initialized (position: {s})", .{
            @tagName(self.overlay_config.position),
        });
    }

    /// Enable or disable the overlay
    pub fn setOverlayEnabled(self: *Compositor, enabled: bool) void {
        self.overlay_enabled = enabled;
        self.config.show_overlay = enabled;
    }

    /// Check if overlay is enabled and available
    pub fn isOverlayActive(self: *const Compositor) bool {
        return self.overlay_enabled and self.overlay != null;
    }

    /// Update overlay metrics (collect current GPU stats)
    pub fn updateOverlayMetrics(self: *Compositor) void {
        if (self.metrics_collector) |collector| {
            // Collector.collect() returns GpuMetrics, which we can use for overlay
            _ = collector.collect();
        }
    }

    /// Render the overlay
    /// Should be called after the main scene is rendered
    pub fn renderOverlay(self: *Compositor) void {
        if (!self.overlay_enabled) return;

        const overlay_ptr = self.overlay orelse return;

        // Record frame timing and update metrics
        overlay_ptr.recordFrame();
        overlay_ptr.updateMetrics();

        // Build HUD content based on current metrics
        overlay_ptr.buildHud();
    }

    /// Get overlay configuration
    pub fn getOverlayConfig(self: *const Compositor) nvhud.Config {
        return self.overlay_config;
    }

    /// Set overlay position
    pub fn setOverlayPosition(self: *Compositor, position: nvhud.Position) void {
        self.overlay_config.position = position;
        if (self.overlay) |overlay_ptr| {
            // Update the overlay's internal config directly
            overlay_ptr.cfg.position = position;
        }
    }

    /// Get VRR configuration
    pub fn getVrrConfig(self: *const Compositor) ?nvvk.VrrConfig {
        return self.vrr_config;
    }

    /// Check if VRR is available and enabled
    pub fn isVrrActive(self: *const Compositor) bool {
        if (self.vrr_config) |vrr| {
            return vrr.enabled;
        }
        return false;
    }

    /// Get optimal frame injection interval for current VRR state
    pub fn getFrameInjectionInterval(self: *const Compositor, avg_frame_time_us: u64) u64 {
        if (self.drm_backend) |*backend| {
            return backend.getInjectionInterval(avg_frame_time_us);
        }
        if (self.vrr_config) |vrr| {
            return vrr.calculateInjectionInterval(avg_frame_time_us);
        }
        // Default: half frame at 60Hz
        return 8333;
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
    pub fn runGame(self: *Compositor, argv: []const []const u8, env: ?*const std.process.Environ.Map) !void {
        if (self.state != .running) {
            try self.start();
        }

        const io = std.Io.Threaded.global_single_threaded.io();

        // Set up environment for the game
        var child_env = std.process.Environ.Map.init(self.allocator);
        defer child_env.deinit();

        // Copy existing environment if provided
        if (env) |e| {
            var iter = e.array_hash_map.iterator();
            while (iter.next()) |entry| {
                try child_env.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }

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
        const child = std.process.spawn(io, .{
            .argv = argv,
            .environ_map = &child_env,
        }) catch return error.SpawnError;

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
        if (self.pacer) |*p| {
            const stats = p.getStats();
            const frame_time_ms = if (stats.average_fps > 0) 1000.0 / stats.average_fps else 0;
            return LatencyStats{
                .total_latency_ms = @floatCast(frame_time_ms),
                .cpu_frame_ms = @floatCast(frame_time_ms),
            };
        }
        return LatencyStats{};
    }

    /// Get performance stats
    pub fn getPerfStats(self: *const Compositor) PerfStats {
        if (self.pacer) |*p| {
            const stats = p.getStats();
            const frame_time_ms = if (stats.average_fps > 0) 1000.0 / stats.average_fps else 0;
            return PerfStats{
                .fps = @floatCast(stats.average_fps),
                .frame_time_ms = @floatCast(frame_time_ms),
                .one_percent_low_fps = @floatCast(stats.average_fps * 0.9), // Estimate
                .vrr_hz = if (stats.vrr_enabled) stats.vrr_range[1] else 0,
                .frame_count = stats.frames_paced,
            };
        }
        return PerfStats{};
    }

    /// Set VRR enabled
    /// Uses nvsync to control VRR on hardware (DRM, Wayland compositor, nvidia-settings)
    pub fn setVrr(self: *Compositor, enabled: bool) void {
        self.config.vrr = enabled;

        // Update frame pacer VRR awareness
        if (self.pacer) |*p| {
            p.config.vrr_enabled = enabled;
        }

        // Use nvsync to enable/disable VRR on hardware
        if (enabled) {
            nvsync.enableVrr(self.allocator, null) catch |err| {
                std.log.warn("Failed to enable VRR via nvsync: {}", .{err});
                // Try DRM backend directly as fallback
                if (self.drm_backend) |*backend| {
                    if (backend.getPrimaryOutput()) |output| {
                        backend.enableVrr(output.connector_id) catch {};
                    }
                }
            };
        } else {
            nvsync.disableVrr(self.allocator, null) catch |err| {
                std.log.warn("Failed to disable VRR via nvsync: {}", .{err});
                if (self.drm_backend) |*backend| {
                    if (backend.getPrimaryOutput()) |output| {
                        backend.disableVrr(output.connector_id) catch {};
                    }
                }
            };
        }
    }

    /// Set frame limit
    pub fn setFrameLimit(self: *Compositor, fps: u32) void {
        self.config.fps_limit = fps;
        if (self.pacer) |*p| {
            p.setTargetFps(fps);
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
