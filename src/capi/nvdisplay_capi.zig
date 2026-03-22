//! nvdisplay C API exports
//!
//! Provides C ABI-compatible functions for display and VRR control.

const std = @import("std");
const nvprime = @import("nvprime");
const nvdisplay = nvprime.nvdisplay;

// Global allocator for C API
var gpa: std.heap.DebugAllocator(.{}) = .init;

/// C-compatible VRR source enum
pub const NvVrrType = enum(c_int) {
    none = 0,
    gsync = 1,
    gsync_compatible = 2,
    freesync = 3,
    vesa_adaptive_sync = 4,
};

/// C-compatible connection type
pub const NvConnectionType = enum(c_int) {
    displayport = 0,
    hdmi = 1,
    dvi = 2,
    vga = 3,
    usb_c = 4,
    internal = 5,
    unknown = 6,
};

/// C-compatible display info structure
pub const NvDisplayInfo = extern struct {
    name: [32]u8,
    manufacturer: [16]u8,
    model: [64]u8,
    connection: NvConnectionType,
    native_width: u32,
    native_height: u32,
    current_width: u32,
    current_height: u32,
    current_refresh_hz: u32,
    max_refresh_hz: u32,
    min_vrr_hz: u32,
    max_vrr_hz: u32,
    supports_gsync: bool,
    supports_gsync_compatible: bool,
    supports_vrr: bool,
    supports_hdr: bool,
    hdr_active: bool,
    vrr_active: bool,
};

/// C-compatible VRR state structure
pub const NvVrrState = extern struct {
    vrr_type: NvVrrType,
    enabled: bool,
    min_hz: u32,
    max_hz: u32,
    current_hz: u32,
    lfc_supported: bool,
    lfc_active: bool,
    vrr_in_use: bool,
};

/// C-compatible display configuration
pub const NvDisplayConfig = extern struct {
    width: u32,
    height: u32,
    refresh_hz: u32,
    enable_vrr: bool,
    enable_hdr: bool,
};

// ============================================================================
// C ABI Exports
// ============================================================================

/// Get number of connected displays
export fn nvdisplay_get_count() c_int {
    const allocator = gpa.allocator();
    const state = nvdisplay.getState(allocator) catch return -1;
    return @intCast(state.display_count);
}

/// Get display info by index
export fn nvdisplay_get_info(index: u32, out_info: *NvDisplayInfo) c_int {
    const allocator = gpa.allocator();
    const state = nvdisplay.getState(allocator) catch return -1;

    if (index >= state.display_count) return -1;

    const info = state.displays[index];
    out_info.* = NvDisplayInfo{
        .name = info.name,
        .manufacturer = info.manufacturer,
        .model = info.model,
        .connection = switch (info.connection) {
            .displayport => .displayport,
            .hdmi => .hdmi,
            .dvi => .dvi,
            .vga => .vga,
            .usb_c => .usb_c,
            .internal => .internal,
            .unknown => .unknown,
        },
        .native_width = info.native_width,
        .native_height = info.native_height,
        .current_width = info.current_width,
        .current_height = info.current_height,
        .current_refresh_hz = info.current_refresh_hz,
        .max_refresh_hz = info.max_refresh_hz,
        .min_vrr_hz = info.min_vrr_hz,
        .max_vrr_hz = info.max_vrr_hz,
        .supports_gsync = info.supports_gsync,
        .supports_gsync_compatible = info.supports_gsync_compatible,
        .supports_vrr = info.supports_vrr,
        .supports_hdr = info.supports_hdr,
        .hdr_active = info.hdr_active,
        .vrr_active = info.vrr_active,
    };

    return 0;
}

/// Get primary display info
export fn nvdisplay_get_primary(out_info: *NvDisplayInfo) c_int {
    const allocator = gpa.allocator();
    const state = nvdisplay.getState(allocator) catch return -1;

    if (state.getPrimary()) |info| {
        out_info.* = NvDisplayInfo{
            .name = info.name,
            .manufacturer = info.manufacturer,
            .model = info.model,
            .connection = switch (info.connection) {
                .displayport => .displayport,
                .hdmi => .hdmi,
                .dvi => .dvi,
                .vga => .vga,
                .usb_c => .usb_c,
                .internal => .internal,
                .unknown => .unknown,
            },
            .native_width = info.native_width,
            .native_height = info.native_height,
            .current_width = info.current_width,
            .current_height = info.current_height,
            .current_refresh_hz = info.current_refresh_hz,
            .max_refresh_hz = info.max_refresh_hz,
            .min_vrr_hz = info.min_vrr_hz,
            .max_vrr_hz = info.max_vrr_hz,
            .supports_gsync = info.supports_gsync,
            .supports_gsync_compatible = info.supports_gsync_compatible,
            .supports_vrr = info.supports_vrr,
            .supports_hdr = info.supports_hdr,
            .hdr_active = info.hdr_active,
            .vrr_active = info.vrr_active,
        };
        return 0;
    }

    return -1;
}

/// Check if VRR is supported on display by name
export fn nvdisplay_vrr_supported(display_name: [*:0]const u8) bool {
    const name = std.mem.sliceTo(display_name, 0);
    const state = nvdisplay.vrr.getState(name) catch return false;
    return state.vrr_type != .none;
}

/// Check if VRR is enabled on display by name
export fn nvdisplay_vrr_enabled(display_name: [*:0]const u8) bool {
    const name = std.mem.sliceTo(display_name, 0);
    const state = nvdisplay.vrr.getState(name) catch return false;
    return state.enabled;
}

/// Get VRR state for display by name
export fn nvdisplay_get_vrr_state(display_name: [*:0]const u8, out_state: *NvVrrState) c_int {
    const name = std.mem.sliceTo(display_name, 0);
    const state = nvdisplay.vrr.getState(name) catch return -1;

    out_state.* = NvVrrState{
        .vrr_type = switch (state.vrr_type) {
            .none => .none,
            .gsync => .gsync,
            .gsync_compatible => .gsync_compatible,
            .freesync => .freesync,
            .vesa_adaptive_sync => .vesa_adaptive_sync,
        },
        .enabled = state.enabled,
        .min_hz = state.min_hz,
        .max_hz = state.max_hz,
        .current_hz = state.current_hz,
        .lfc_supported = state.lfc_supported,
        .lfc_active = state.lfc_active,
        .vrr_in_use = state.vrr_in_use,
    };

    return 0;
}

/// Enable VRR on display by name
export fn nvdisplay_vrr_enable(display_name: [*:0]const u8) c_int {
    const name = std.mem.sliceTo(display_name, 0);
    nvdisplay.vrr.enable(name) catch return -1;
    return 0;
}

/// Disable VRR on display by name
export fn nvdisplay_vrr_disable(display_name: [*:0]const u8) c_int {
    const name = std.mem.sliceTo(display_name, 0);
    nvdisplay.vrr.disable(name) catch return -1;
    return 0;
}

/// Get VRR min Hz for display by name
export fn nvdisplay_get_vrr_min(display_name: [*:0]const u8) c_int {
    const name = std.mem.sliceTo(display_name, 0);
    const state = nvdisplay.vrr.getState(name) catch return -1;
    return @intCast(state.min_hz);
}

/// Get VRR max Hz for display by name
export fn nvdisplay_get_vrr_max(display_name: [*:0]const u8) c_int {
    const name = std.mem.sliceTo(display_name, 0);
    const state = nvdisplay.vrr.getState(name) catch return -1;
    return @intCast(state.max_hz);
}

/// Check if HDR is supported on display by name
export fn nvdisplay_hdr_supported(display_name: [*:0]const u8) bool {
    const name = std.mem.sliceTo(display_name, 0);
    const state = nvdisplay.hdr.getState(name) catch return false;
    return state.supported;
}

/// Check if HDR is enabled on display by name
export fn nvdisplay_hdr_enabled(display_name: [*:0]const u8) bool {
    const name = std.mem.sliceTo(display_name, 0);
    const state = nvdisplay.hdr.getState(name) catch return false;
    return state.enabled;
}

/// Enable HDR on display by name (uses HDR10 format)
export fn nvdisplay_hdr_enable(display_name: [*:0]const u8) c_int {
    const name = std.mem.sliceTo(display_name, 0);
    nvdisplay.hdr.enable(name, .hdr10) catch return -1;
    return 0;
}

/// Disable HDR on display by name
export fn nvdisplay_hdr_disable(display_name: [*:0]const u8) c_int {
    const name = std.mem.sliceTo(display_name, 0);
    nvdisplay.hdr.disable(name) catch return -1;
    return 0;
}

/// Apply display configuration by name
export fn nvdisplay_configure(display_name: [*:0]const u8, config: *const NvDisplayConfig) c_int {
    const name = std.mem.sliceTo(display_name, 0);
    const zig_config = nvdisplay.DisplayConfig{
        .width = config.width,
        .height = config.height,
        .refresh_hz = config.refresh_hz,
        .enable_vrr = config.enable_vrr,
        .enable_hdr = config.enable_hdr,
    };
    nvdisplay.configure(name, zig_config) catch return -1;
    return 0;
}

/// Get display resolution by name
export fn nvdisplay_get_resolution(display_name: [*:0]const u8, out_width: *u32, out_height: *u32) c_int {
    const allocator = gpa.allocator();
    const name = std.mem.sliceTo(display_name, 0);
    const state = nvdisplay.getState(allocator) catch return -1;

    if (state.getByName(name)) |info| {
        out_width.* = info.current_width;
        out_height.* = info.current_height;
        return 0;
    }

    return -1;
}

/// Get display refresh rate by name
export fn nvdisplay_get_refresh_rate(display_name: [*:0]const u8) c_int {
    const allocator = gpa.allocator();
    const name = std.mem.sliceTo(display_name, 0);
    const state = nvdisplay.getState(allocator) catch return -1;

    if (state.getByName(name)) |info| {
        return @intCast(info.current_refresh_hz);
    }

    return -1;
}
