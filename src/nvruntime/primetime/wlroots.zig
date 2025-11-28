//! wlroots C bindings for PrimeTime compositor
//!
//! Provides Zig bindings to libwlroots for Wayland compositor functionality.
//! This is the low-level layer that primetime.zig builds upon.

const std = @import("std");
const c = @cImport({
    @cDefine("WLR_USE_UNSTABLE", "1");
    @cInclude("wlr/backend.h");
    @cInclude("wlr/backend/drm.h");
    @cInclude("wlr/backend/libinput.h");
    @cInclude("wlr/render/allocator.h");
    @cInclude("wlr/render/wlr_renderer.h");
    @cInclude("wlr/types/wlr_compositor.h");
    @cInclude("wlr/types/wlr_output.h");
    @cInclude("wlr/types/wlr_output_layout.h");
    @cInclude("wlr/types/wlr_scene.h");
    @cInclude("wlr/types/wlr_xdg_shell.h");
    @cInclude("wlr/types/wlr_cursor.h");
    @cInclude("wlr/types/wlr_seat.h");
    @cInclude("wlr/types/wlr_keyboard.h");
    @cInclude("wlr/types/wlr_pointer.h");
    @cInclude("wlr/util/log.h");
    @cInclude("wayland-server-core.h");
});

// Re-export C types
pub const wl_display = c.wl_display;
pub const wl_event_loop = c.wl_event_loop;
pub const wl_listener = c.wl_listener;
pub const wl_signal = c.wl_signal;

pub const wlr_backend = c.wlr_backend;
pub const wlr_renderer = c.wlr_renderer;
pub const wlr_allocator = c.wlr_allocator;
pub const wlr_compositor = c.wlr_compositor;
pub const wlr_output = c.wlr_output;
pub const wlr_output_layout = c.wlr_output_layout;
pub const wlr_scene = c.wlr_scene;
pub const wlr_scene_output = c.wlr_scene_output;
pub const wlr_xdg_shell = c.wlr_xdg_shell;
pub const wlr_xdg_toplevel = c.wlr_xdg_toplevel;
pub const wlr_cursor = c.wlr_cursor;
pub const wlr_seat = c.wlr_seat;
pub const wlr_keyboard = c.wlr_keyboard;

/// Log levels for wlroots
pub const LogLevel = enum(c_int) {
    silent = c.WLR_SILENT,
    err = c.WLR_ERROR,
    info = c.WLR_INFO,
    debug = c.WLR_DEBUG,
};

/// Initialize wlroots logging
pub fn initLog(level: LogLevel) void {
    c.wlr_log_init(@intFromEnum(level), null);
}

/// Create a new Wayland display
pub fn createDisplay() ?*wl_display {
    return c.wl_display_create();
}

/// Get the event loop from a display
pub fn getEventLoop(display: *wl_display) ?*wl_event_loop {
    return c.wl_display_get_event_loop(display);
}

/// Create wlroots backend (auto-detects DRM, libinput, etc.)
pub fn createBackend(display: *wl_display) ?*wlr_backend {
    return c.wlr_backend_autocreate(display, null);
}

/// Create a renderer for the backend
pub fn createRenderer(backend: *wlr_backend) ?*wlr_renderer {
    return c.wlr_renderer_autocreate(backend);
}

/// Create an allocator
pub fn createAllocator(backend: *wlr_backend, renderer: *wlr_renderer) ?*wlr_allocator {
    return c.wlr_allocator_autocreate(backend, renderer);
}

/// Create compositor
pub fn createCompositor(display: *wl_display, version: u32, renderer: *wlr_renderer) ?*wlr_compositor {
    return c.wlr_compositor_create(display, version, renderer);
}

/// Create output layout
pub fn createOutputLayout() ?*wlr_output_layout {
    return c.wlr_output_layout_create();
}

/// Create scene graph
pub fn createScene() ?*wlr_scene {
    return c.wlr_scene_create();
}

/// Create XDG shell
pub fn createXdgShell(display: *wl_display, version: u32) ?*wlr_xdg_shell {
    return c.wlr_xdg_shell_create(display, version);
}

/// Create cursor
pub fn createCursor() ?*wlr_cursor {
    return c.wlr_cursor_create();
}

/// Create seat
pub fn createSeat(display: *wl_display, name: [*:0]const u8) ?*wlr_seat {
    return c.wlr_seat_create(display, name);
}

/// Start the backend
pub fn startBackend(backend: *wlr_backend) bool {
    return c.wlr_backend_start(backend);
}

/// Run the display event loop
pub fn runDisplay(display: *wl_display) void {
    c.wl_display_run(display);
}

/// Destroy the display
pub fn destroyDisplay(display: *wl_display) void {
    c.wl_display_destroy(display);
}

/// Add socket to display
pub fn addSocketAuto(display: *wl_display) ?[*:0]const u8 {
    return c.wl_display_add_socket_auto(display);
}

/// Output mode structure
pub const OutputMode = struct {
    width: i32,
    height: i32,
    refresh: i32, // mHz
};

/// Get preferred output mode
pub fn getPreferredMode(output: *wlr_output) ?*c.wlr_output_mode {
    return c.wlr_output_preferred_mode(output);
}

/// Set output mode
pub fn setOutputMode(output: *wlr_output, mode: *c.wlr_output_mode) void {
    c.wlr_output_set_mode(output, mode);
}

/// Enable output
pub fn enableOutput(output: *wlr_output, enable: bool) void {
    c.wlr_output_enable(output, enable);
}

/// Commit output state
pub fn commitOutput(output: *wlr_output) bool {
    return c.wlr_output_commit(output);
}

/// Listener helper - container_of equivalent
pub fn containerOf(comptime T: type, comptime field: []const u8, ptr: anytype) *T {
    const field_ptr = @as([*]u8, @ptrCast(ptr));
    const offset = @offsetOf(T, field);
    return @ptrCast(@alignCast(field_ptr - offset));
}

test "wlroots bindings compile" {
    // Just verify types exist
    _ = LogLevel.debug;
}
