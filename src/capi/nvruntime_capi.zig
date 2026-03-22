//! nvruntime C API exports
//!
//! Provides C ABI-compatible functions for PrimeTime compositor control.

const std = @import("std");
const nvprime = @import("nvprime");
const primetime = nvprime.nvruntime.primetime;

// ============================================================================
// C-compatible enums
// ============================================================================

/// C-compatible compositor state
pub const NvCompositorState = enum(c_int) {
    uninitialized = 0,
    stopped = 1,
    starting = 2,
    running = 3,
    error_state = 4,
};

/// C-compatible upscaler type
pub const NvUpscaler = enum(c_int) {
    none = 0,
    fsr1 = 1,
    fsr2 = 2,
    nis = 3,
    dlss = 4,
};

/// C-compatible pacing mode
pub const NvPacingMode = enum(c_int) {
    none = 0,
    vsync = 1,
    adaptive = 2,
    vrr = 3,
    limited = 4,
};

/// C-compatible present mode
pub const NvPresentMode = enum(c_int) {
    none = 0,
    ghostvk = 1,
    external = 2,
};

/// C-compatible overlay position
pub const NvOverlayPosition = enum(c_int) {
    top_left = 0,
    top_right = 1,
    bottom_left = 2,
    bottom_right = 3,
};

// ============================================================================
// C-compatible structures
// ============================================================================

/// C-compatible compositor configuration
pub const NvCompositorConfig = extern struct {
    width: u32,
    height: u32,
    render_width: u32,
    render_height: u32,
    refresh_hz: u32,
    vrr: bool,
    hdr: bool,
    allow_tearing: bool,
    upscaler: NvUpscaler,
    fps_limit: u32,
    pacing_mode: NvPacingMode,
    show_overlay: bool,
    grab_keyboard: bool,
    grab_mouse: bool,
};

/// C-compatible output info
pub const NvOutputInfo = extern struct {
    name: [32]u8,
    width: u32,
    height: u32,
    refresh_hz: u32,
    vrr_capable: bool,
    hdr_capable: bool,
    connected: bool,
};

/// C-compatible latency statistics
pub const NvLatencyStats = extern struct {
    total_latency_ms: f32,
    cpu_frame_ms: f32,
    gpu_render_ms: f32,
    compositor_ms: f32,
    scanout_ms: f32,
};

/// C-compatible performance statistics
pub const NvPerfStats = extern struct {
    fps: f32,
    frame_time_ms: f32,
    one_percent_low_fps: f32,
    point_one_percent_low_fps: f32,
    vrr_hz: u32,
    frame_count: u64,
};

/// C-compatible swapchain info
pub const NvSwapchainInfo = extern struct {
    image_count: u32,
    format: u32,
    width: u32,
    height: u32,
    current_image: u32,
    hdr_enabled: bool,
};

/// C-compatible VRR config
pub const NvPrimetimeVrrConfig = extern struct {
    enabled: bool,
    min_hz: u32,
    max_hz: u32,
    lfc_supported: bool,
};

// ============================================================================
// Opaque handle
// ============================================================================

/// Opaque handle to compositor instance
pub const NvCompositor = opaque {};

// Global allocator for C API
var gpa: std.heap.DebugAllocator(.{}) = .init;

// ============================================================================
// C ABI Exports - Compositor Lifecycle
// ============================================================================

/// Create a new compositor instance with default config
export fn nvprimetime_create() ?*NvCompositor {
    const allocator = gpa.allocator();
    const compositor = primetime.Compositor.init(allocator, .{}) catch return null;
    return @ptrCast(compositor);
}

/// Create a new compositor instance with config
export fn nvprimetime_create_with_config(config: *const NvCompositorConfig) ?*NvCompositor {
    const allocator = gpa.allocator();

    const zig_config = primetime.Config{
        .width = config.width,
        .height = config.height,
        .render_width = config.render_width,
        .render_height = config.render_height,
        .refresh_hz = config.refresh_hz,
        .vrr = config.vrr,
        .hdr = config.hdr,
        .allow_tearing = config.allow_tearing,
        .upscaler = switch (config.upscaler) {
            .none => .none,
            .fsr1 => .fsr1,
            .fsr2 => .fsr2,
            .nis => .nis,
            .dlss => .dlss,
        },
        .fps_limit = config.fps_limit,
        .pacing_mode = switch (config.pacing_mode) {
            .none => primetime.ConfigPacingMode.none,
            .vsync => primetime.ConfigPacingMode.vsync,
            .adaptive => primetime.ConfigPacingMode.adaptive,
            .vrr => primetime.ConfigPacingMode.vrr,
            .limited => primetime.ConfigPacingMode.limited,
        },
        .show_overlay = config.show_overlay,
        .grab_keyboard = config.grab_keyboard,
        .grab_mouse = config.grab_mouse,
    };

    const compositor = primetime.Compositor.init(allocator, zig_config) catch return null;
    return @ptrCast(compositor);
}

/// Destroy compositor instance
export fn nvprimetime_destroy(compositor: ?*NvCompositor) void {
    if (compositor) |c| {
        const ptr: *primetime.Compositor = @ptrCast(@alignCast(c));
        ptr.deinit();
    }
}

/// Start the compositor
export fn nvprimetime_start(compositor: ?*NvCompositor) c_int {
    if (compositor) |c| {
        const ptr: *primetime.Compositor = @ptrCast(@alignCast(c));
        ptr.start() catch return -1;
        return 0;
    }
    return -1;
}

/// Stop the compositor
export fn nvprimetime_stop(compositor: ?*NvCompositor) c_int {
    if (compositor) |c| {
        const ptr: *primetime.Compositor = @ptrCast(@alignCast(c));
        ptr.stop() catch return -1;
        return 0;
    }
    return -1;
}

/// Get compositor state
export fn nvprimetime_get_state(compositor: ?*NvCompositor) NvCompositorState {
    if (compositor) |c| {
        const ptr: *primetime.Compositor = @ptrCast(@alignCast(c));
        return switch (ptr.getState()) {
            .uninitialized => .uninitialized,
            .stopped => .stopped,
            .starting => .starting,
            .running => .running,
            .error_state => .error_state,
        };
    }
    return .uninitialized;
}

// ============================================================================
// C ABI Exports - Display/Output
// ============================================================================

/// Get output info
export fn nvprimetime_get_output_info(compositor: ?*NvCompositor, out_info: *NvOutputInfo) c_int {
    if (compositor) |c| {
        const ptr: *primetime.Compositor = @ptrCast(@alignCast(c));
        const info = ptr.getOutputInfo();

        out_info.* = NvOutputInfo{
            .name = info.name,
            .width = info.width,
            .height = info.height,
            .refresh_hz = info.refresh_hz,
            .vrr_capable = info.vrr_capable,
            .hdr_capable = info.hdr_capable,
            .connected = info.connected,
        };
        return 0;
    }
    return -1;
}

// ============================================================================
// C ABI Exports - VRR Control
// ============================================================================

/// Check if VRR is active
export fn nvprimetime_is_vrr_active(compositor: ?*NvCompositor) bool {
    if (compositor) |c| {
        const ptr: *primetime.Compositor = @ptrCast(@alignCast(c));
        return ptr.isVrrActive();
    }
    return false;
}

/// Set VRR enabled
export fn nvprimetime_set_vrr(compositor: ?*NvCompositor, enabled: bool) void {
    if (compositor) |c| {
        const ptr: *primetime.Compositor = @ptrCast(@alignCast(c));
        ptr.setVrr(enabled);
    }
}

/// Get VRR configuration
export fn nvprimetime_get_vrr_config(compositor: ?*NvCompositor, out_config: *NvPrimetimeVrrConfig) c_int {
    if (compositor) |c| {
        const ptr: *primetime.Compositor = @ptrCast(@alignCast(c));
        if (ptr.getVrrConfig()) |vrr| {
            out_config.* = NvPrimetimeVrrConfig{
                .enabled = vrr.enabled,
                .min_hz = vrr.min_hz,
                .max_hz = vrr.max_hz,
                .lfc_supported = vrr.lfc_supported,
            };
            return 0;
        }
    }
    return -1;
}

/// Sync VRR settings between components
export fn nvprimetime_sync_vrr(compositor: ?*NvCompositor) void {
    if (compositor) |c| {
        const ptr: *primetime.Compositor = @ptrCast(@alignCast(c));
        ptr.syncVrrSettings();
    }
}

// ============================================================================
// C ABI Exports - Performance Stats
// ============================================================================

/// Get latency statistics
export fn nvprimetime_get_latency_stats(compositor: ?*NvCompositor, out_stats: *NvLatencyStats) c_int {
    if (compositor) |c| {
        const ptr: *primetime.Compositor = @ptrCast(@alignCast(c));
        const stats = ptr.getLatencyStats();

        out_stats.* = NvLatencyStats{
            .total_latency_ms = stats.total_latency_ms,
            .cpu_frame_ms = stats.cpu_frame_ms,
            .gpu_render_ms = stats.gpu_render_ms,
            .compositor_ms = stats.compositor_ms,
            .scanout_ms = stats.scanout_ms,
        };
        return 0;
    }
    return -1;
}

/// Get performance statistics
export fn nvprimetime_get_perf_stats(compositor: ?*NvCompositor, out_stats: *NvPerfStats) c_int {
    if (compositor) |c| {
        const ptr: *primetime.Compositor = @ptrCast(@alignCast(c));
        const stats = ptr.getPerfStats();

        out_stats.* = NvPerfStats{
            .fps = stats.fps,
            .frame_time_ms = stats.frame_time_ms,
            .one_percent_low_fps = stats.one_percent_low_fps,
            .point_one_percent_low_fps = stats.point_one_percent_low_fps,
            .vrr_hz = stats.vrr_hz,
            .frame_count = stats.frame_count,
        };
        return 0;
    }
    return -1;
}

/// Get current FPS
export fn nvprimetime_get_fps(compositor: ?*NvCompositor) f32 {
    if (compositor) |c| {
        const ptr: *primetime.Compositor = @ptrCast(@alignCast(c));
        const stats = ptr.getPerfStats();
        return stats.fps;
    }
    return 0;
}

/// Get frame time in milliseconds
export fn nvprimetime_get_frame_time_ms(compositor: ?*NvCompositor) f32 {
    if (compositor) |c| {
        const ptr: *primetime.Compositor = @ptrCast(@alignCast(c));
        const stats = ptr.getPerfStats();
        return stats.frame_time_ms;
    }
    return 0;
}

// ============================================================================
// C ABI Exports - Swapchain (ghostVK integration)
// ============================================================================

/// Initialize ghostVK swapchain
export fn nvprimetime_init_ghostvk(compositor: ?*NvCompositor) c_int {
    if (compositor) |c| {
        const ptr: *primetime.Compositor = @ptrCast(@alignCast(c));
        ptr.initGhostVK() catch return -1;
        return 0;
    }
    return -1;
}

/// Check if ghostVK swapchain is available
export fn nvprimetime_has_ghostvk(compositor: ?*NvCompositor) bool {
    if (compositor) |c| {
        const ptr: *primetime.Compositor = @ptrCast(@alignCast(c));
        return ptr.hasGhostVKSwapchain();
    }
    return false;
}

/// Get swapchain info
export fn nvprimetime_get_swapchain_info(compositor: ?*NvCompositor, out_info: *NvSwapchainInfo) c_int {
    if (compositor) |c| {
        const ptr: *primetime.Compositor = @ptrCast(@alignCast(c));
        const info = ptr.getSwapchainInfo();

        out_info.* = NvSwapchainInfo{
            .image_count = info.image_count,
            .format = info.format,
            .width = info.width,
            .height = info.height,
            .current_image = info.current_image,
            .hdr_enabled = info.hdr_colorspace != .srgb,
        };
        return 0;
    }
    return -1;
}

/// Begin frame (acquire swapchain image)
export fn nvprimetime_begin_frame(compositor: ?*NvCompositor) c_int {
    if (compositor) |c| {
        const ptr: *primetime.Compositor = @ptrCast(@alignCast(c));
        if (ptr.beginFrame()) |image_index| {
            return @intCast(image_index);
        }
        return -1;
    }
    return -1;
}

/// End frame (present)
export fn nvprimetime_end_frame(compositor: ?*NvCompositor) void {
    if (compositor) |c| {
        const ptr: *primetime.Compositor = @ptrCast(@alignCast(c));
        ptr.endFrame();
    }
}

// ============================================================================
// C ABI Exports - Overlay (nvhud integration)
// ============================================================================

/// Initialize nvhud overlay
export fn nvprimetime_init_overlay(compositor: ?*NvCompositor) c_int {
    if (compositor) |c| {
        const ptr: *primetime.Compositor = @ptrCast(@alignCast(c));
        ptr.initOverlay() catch return -1;
        return 0;
    }
    return -1;
}

/// Enable or disable overlay
export fn nvprimetime_set_overlay_enabled(compositor: ?*NvCompositor, enabled: bool) void {
    if (compositor) |c| {
        const ptr: *primetime.Compositor = @ptrCast(@alignCast(c));
        ptr.setOverlayEnabled(enabled);
    }
}

/// Check if overlay is active
export fn nvprimetime_is_overlay_active(compositor: ?*NvCompositor) bool {
    if (compositor) |c| {
        const ptr: *primetime.Compositor = @ptrCast(@alignCast(c));
        return ptr.isOverlayActive();
    }
    return false;
}

/// Update and render overlay
export fn nvprimetime_render_overlay(compositor: ?*NvCompositor) void {
    if (compositor) |c| {
        const ptr: *primetime.Compositor = @ptrCast(@alignCast(c));
        ptr.updateOverlayMetrics();
        ptr.renderOverlay();
    }
}

/// Set overlay position
export fn nvprimetime_set_overlay_position(compositor: ?*NvCompositor, position: NvOverlayPosition) void {
    if (compositor) |c| {
        const ptr: *primetime.Compositor = @ptrCast(@alignCast(c));
        // Map to nvhud.Position via nvprime re-export
        const nvhud_lib = nvprime.deps.nvhud_lib;
        const nvhud_pos: nvhud_lib.Position = switch (position) {
            .top_left => .top_left,
            .top_right => .top_right,
            .bottom_left => .bottom_left,
            .bottom_right => .bottom_right,
        };
        ptr.setOverlayPosition(nvhud_pos);
    }
}

// ============================================================================
// C ABI Exports - Frame Injection
// ============================================================================

/// Get optimal frame injection interval in microseconds
export fn nvprimetime_get_injection_interval(compositor: ?*NvCompositor, avg_frame_time_us: u64) u64 {
    if (compositor) |c| {
        const ptr: *primetime.Compositor = @ptrCast(@alignCast(c));
        return ptr.getFrameInjectionInterval(avg_frame_time_us);
    }
    return 8333; // Default 60Hz half-frame
}

// ============================================================================
// C ABI Exports - Version Info
// ============================================================================

/// Get PrimeTime version string
export fn nvprimetime_version() [*:0]const u8 {
    return primetime.version;
}
