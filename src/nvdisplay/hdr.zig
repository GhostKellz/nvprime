//! nvdisplay/hdr - HDR Management
//!
//! High Dynamic Range display configuration and control.

const std = @import("std");

/// HDR format/standard
pub const HdrFormat = enum {
    sdr, // Standard Dynamic Range
    hdr10, // HDR10 (static metadata)
    hdr10_plus, // HDR10+ (dynamic metadata)
    dolby_vision, // Dolby Vision
    hlg, // Hybrid Log-Gamma (broadcast)

    pub fn description(self: HdrFormat) []const u8 {
        return switch (self) {
            .sdr => "Standard Dynamic Range",
            .hdr10 => "HDR10 (static metadata)",
            .hdr10_plus => "HDR10+ (dynamic metadata)",
            .dolby_vision => "Dolby Vision",
            .hlg => "Hybrid Log-Gamma",
        };
    }

    pub fn minBitDepth(self: HdrFormat) u32 {
        return switch (self) {
            .sdr => 8,
            .hdr10, .hdr10_plus, .hlg => 10,
            .dolby_vision => 12,
        };
    }

    pub fn supportsWideGamut(self: HdrFormat) bool {
        return self != .sdr;
    }
};

/// HDR state for a display
pub const HdrState = struct {
    supported: bool,
    enabled: bool,
    format: HdrFormat,
    // Display capabilities
    max_luminance_nits: u32,
    min_luminance_nits: f32,
    max_frame_avg_luminance_nits: u32,
    // Color
    bit_depth: u32,
    color_primaries: ColorPrimaries,
    // Current output
    output_luminance_nits: u32,
    tone_mapping_active: bool,

    pub fn isHdrActive(self: HdrState) bool {
        return self.enabled and self.format != .sdr;
    }

    pub fn dynamicRange(self: HdrState) f32 {
        if (self.min_luminance_nits <= 0) return 0;
        return @as(f32, @floatFromInt(self.max_luminance_nits)) / self.min_luminance_nits;
    }
};

/// Color primaries
pub const ColorPrimaries = enum {
    bt709, // sRGB/Rec.709
    bt2020, // Wide gamut for HDR
    dci_p3, // Digital Cinema
    adobe_rgb,

    pub fn isWideGamut(self: ColorPrimaries) bool {
        return self != .bt709;
    }
};

/// Get HDR state for a display
pub fn getState(display_name: []const u8) !HdrState {
    _ = display_name;
    // TODO: Query via libdrm or nvidia-settings
    return error.NotSupported;
}

/// Enable HDR on a display
pub fn enable(display_name: []const u8, format: HdrFormat) !void {
    _ = display_name;
    _ = format;
    // TODO: Implement via nvidia-settings or libdrm
    // On Wayland: compositor must support HDR
    // On X11: nvidia-settings or direct mode setting
    return error.NotSupported;
}

/// Disable HDR on a display
pub fn disable(display_name: []const u8) !void {
    _ = display_name;
    return error.NotSupported;
}

/// HDR configuration
pub const HdrConfig = struct {
    format: HdrFormat = .hdr10,
    /// Output max luminance (nits)
    max_luminance: u32 = 1000,
    /// SDR content brightness boost (for mixed content)
    sdr_brightness_percent: u32 = 100,
    /// Enable desktop HDR (not just fullscreen apps)
    desktop_hdr: bool = true,
    /// Bit depth
    bit_depth: u32 = 10,
};

/// Apply HDR configuration
pub fn configure(display_name: []const u8, config: HdrConfig) !void {
    _ = display_name;
    _ = config;
    return error.NotSupported;
}

/// SDR-in-HDR handling
pub const SdrHandling = enum {
    /// Boost SDR content to HDR levels
    boost,
    /// Keep SDR content at reference level
    reference,
    /// Match display max brightness
    match_display,
};

/// Set SDR content handling when HDR is active
pub fn setSdrHandling(display_name: []const u8, handling: SdrHandling) !void {
    _ = display_name;
    _ = handling;
    return error.NotSupported;
}

/// Tone mapping mode
pub const ToneMappingMode = enum {
    /// GPU tone mapping (recommended)
    gpu,
    /// Display tone mapping
    display,
    /// No tone mapping (clipping)
    none,
};

/// Set tone mapping mode
pub fn setToneMapping(display_name: []const u8, mode: ToneMappingMode) !void {
    _ = display_name;
    _ = mode;
    return error.NotSupported;
}

/// HDR video enhancement (RTX Video HDR)
pub const VideoHdr = struct {
    /// Enable SDR to HDR conversion for video
    enabled: bool,
    /// AI-enhanced conversion (RTX feature)
    ai_enhanced: bool,
    /// Target peak brightness
    peak_brightness: u32,
};

/// Configure RTX Video HDR
pub fn configureVideoHdr(config: VideoHdr) !void {
    _ = config;
    // RTX Video HDR requires NVIDIA driver 545+
    return error.NotSupported;
}

test "hdr format" {
    const hdr10 = HdrFormat.hdr10;
    try std.testing.expectEqual(@as(u32, 10), hdr10.minBitDepth());
    try std.testing.expect(hdr10.supportsWideGamut());

    const sdr = HdrFormat.sdr;
    try std.testing.expect(!sdr.supportsWideGamut());
}
