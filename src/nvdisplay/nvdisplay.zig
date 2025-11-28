//! nvdisplay - Display Pipeline Management
//!
//! G-Sync, HDR, VRR, and multi-monitor orchestration.
//! This is the display management core of NVPrime.

const std = @import("std");
const nvml = @import("../bindings/nvml.zig");

pub const gsync = @import("gsync.zig");
pub const hdr = @import("hdr.zig");
pub const vrr = @import("vrr.zig");
pub const multimon = @import("multimon.zig");

/// Display connection type
pub const ConnectionType = enum {
    displayport,
    hdmi,
    dvi,
    vga,
    usb_c,
    internal,
    unknown,

    pub fn supportsVrr(self: ConnectionType) bool {
        return switch (self) {
            .displayport, .hdmi, .usb_c => true,
            else => false,
        };
    }

    pub fn supportsHdr(self: ConnectionType) bool {
        return switch (self) {
            .displayport, .hdmi, .usb_c => true,
            else => false,
        };
    }

    pub fn maxBandwidthGbps(self: ConnectionType) f32 {
        return switch (self) {
            .displayport => 80.0, // DP 2.1
            .hdmi => 48.0, // HDMI 2.1
            .usb_c => 80.0, // DP Alt mode
            .dvi => 7.92, // Dual-link DVI
            .vga => 0, // Analog
            .internal => 100.0, // Direct
            .unknown => 0,
        };
    }
};

/// Display info
pub const DisplayInfo = struct {
    /// Display identifier (e.g., "DP-1", "HDMI-1")
    name: [32]u8,
    /// EDID manufacturer name
    manufacturer: [16]u8,
    /// EDID model name
    model: [64]u8,
    /// Serial number
    serial: [32]u8,
    /// Connection type
    connection: ConnectionType,
    /// Native resolution
    native_width: u32,
    native_height: u32,
    /// Current resolution
    current_width: u32,
    current_height: u32,
    /// Refresh rates
    current_refresh_hz: u32,
    max_refresh_hz: u32,
    min_vrr_hz: u32,
    max_vrr_hz: u32,
    /// Feature support
    supports_gsync: bool,
    supports_gsync_compatible: bool,
    supports_vrr: bool,
    supports_hdr: bool,
    hdr_active: bool,
    vrr_active: bool,

    pub fn getName(self: *const DisplayInfo) []const u8 {
        return std.mem.sliceTo(&self.name, 0);
    }

    pub fn getModel(self: *const DisplayInfo) []const u8 {
        return std.mem.sliceTo(&self.model, 0);
    }

    pub fn print(self: DisplayInfo, writer: anytype) !void {
        try writer.print("{s}: {s} {s}\n", .{
            self.getName(),
            std.mem.sliceTo(&self.manufacturer, 0),
            self.getModel(),
        });
        try writer.print("  {d}x{d} @ {d}Hz ({s})\n", .{
            self.current_width,
            self.current_height,
            self.current_refresh_hz,
            @tagName(self.connection),
        });
        try writer.print("  VRR: {d}-{d}Hz | G-Sync: {} | HDR: {}\n", .{
            self.min_vrr_hz,
            self.max_vrr_hz,
            self.supports_gsync or self.supports_gsync_compatible,
            self.supports_hdr,
        });
    }
};

/// Complete display state
pub const DisplayState = struct {
    displays: [8]DisplayInfo,
    display_count: usize,
    primary_display: usize,

    pub fn getPrimary(self: *const DisplayState) ?*const DisplayInfo {
        if (self.display_count == 0) return null;
        return &self.displays[self.primary_display];
    }

    pub fn getByName(self: *const DisplayState, name: []const u8) ?*const DisplayInfo {
        for (self.displays[0..self.display_count]) |*display| {
            if (std.mem.eql(u8, display.getName(), name)) {
                return display;
            }
        }
        return null;
    }
};

/// Get current display state
/// Note: This requires querying X11/Wayland, not just NVML
pub fn getState() !DisplayState {
    // TODO: Implement via:
    // - xrandr / libdrm for X11
    // - wlr-output-management for Wayland
    // - nvidia-settings for NVIDIA-specific features

    const state = DisplayState{
        .displays = undefined,
        .display_count = 0,
        .primary_display = 0,
    };

    // Placeholder - would need actual display enumeration
    return state;
}

/// Display configuration
pub const DisplayConfig = struct {
    width: u32,
    height: u32,
    refresh_hz: u32,
    enable_vrr: bool = false,
    enable_hdr: bool = false,
    color_depth: ColorDepth = .bpc8,
    color_format: ColorFormat = .rgb,
};

pub const ColorDepth = enum {
    bpc6,
    bpc8,
    bpc10,
    bpc12,

    pub fn bits(self: ColorDepth) u32 {
        return switch (self) {
            .bpc6 => 6,
            .bpc8 => 8,
            .bpc10 => 10,
            .bpc12 => 12,
        };
    }
};

pub const ColorFormat = enum {
    rgb,
    ycbcr444,
    ycbcr422,
    ycbcr420,

    pub fn forHdr(self: ColorFormat) bool {
        return self == .rgb or self == .ycbcr444;
    }
};

/// Apply display configuration
pub fn configure(display_name: []const u8, config: DisplayConfig) !void {
    _ = display_name;
    _ = config;
    // TODO: Implement via xrandr/wlr-output-management
    return error.NotSupported;
}

/// Display profile for quick switching
pub const DisplayProfile = enum {
    gaming, // VRR on, max refresh
    movie, // HDR on, 24Hz sync if available
    productivity, // Native res, 60Hz, power save
    presentation, // Optimal for external display

    pub fn getConfig(self: DisplayProfile, display: DisplayInfo) DisplayConfig {
        return switch (self) {
            .gaming => .{
                .width = display.native_width,
                .height = display.native_height,
                .refresh_hz = display.max_refresh_hz,
                .enable_vrr = display.supports_vrr,
                .enable_hdr = false, // HDR in gaming can add latency
                .color_depth = .bpc8,
            },
            .movie => .{
                .width = display.native_width,
                .height = display.native_height,
                .refresh_hz = 60, // Or 24 if supported
                .enable_vrr = false,
                .enable_hdr = display.supports_hdr,
                .color_depth = .bpc10,
            },
            .productivity => .{
                .width = display.native_width,
                .height = display.native_height,
                .refresh_hz = 60,
                .enable_vrr = false,
                .enable_hdr = false,
                .color_depth = .bpc8,
            },
            .presentation => .{
                .width = 1920,
                .height = 1080,
                .refresh_hz = 60,
                .enable_vrr = false,
                .enable_hdr = false,
                .color_depth = .bpc8,
            },
        };
    }
};

test "display types" {
    const dp = ConnectionType.displayport;
    try std.testing.expect(dp.supportsVrr());
    try std.testing.expect(dp.supportsHdr());
    try std.testing.expectEqual(@as(f32, 80.0), dp.maxBandwidthGbps());
}
