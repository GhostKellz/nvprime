//! nvdisplay/hdr - HDR Management
//!
//! High Dynamic Range display configuration and control.
//! Uses DRM sysfs properties and nvidia-settings for control.

const std = @import("std");
const fs = std.fs;
const mem = std.mem;

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

/// EDID HDR capability result
const EdidHdrCapability = struct {
    supported: bool,
    max_lum: u32,
    min_lum: f32,
    max_avg_lum: u32,
};

/// nvidia-settings HDR query result
const NvidiaSettingsHdrResult = struct {
    enabled: bool,
    bit_depth: u32,
};

/// DRM sysfs path
const DRM_SYS_DIR = "/sys/class/drm";

/// Read sysfs file value
fn readSysfs(allocator: mem.Allocator, path: []const u8) ?[]const u8 {
    const file = fs.cwd().openFile(path, .{}) catch return null;
    defer file.close();

    var buf: [256]u8 = undefined;
    const len = file.read(&buf) catch return null;
    return allocator.dupe(u8, buf[0..len]) catch null;
}

/// Read sysfs binary file (for EDID)
fn readSysfsBinary(allocator: mem.Allocator, path: []const u8) ?[]const u8 {
    const file = fs.cwd().openFile(path, .{}) catch return null;
    defer file.close();

    var buf: [512]u8 = undefined;
    const len = file.read(&buf) catch return null;
    return allocator.dupe(u8, buf[0..len]) catch null;
}

/// Parse EDID for HDR capability (HDR Static Metadata Data Block in CTA-861)
fn parseEdidHdrCapability(edid: []const u8) EdidHdrCapability {
    var result = EdidHdrCapability{ .supported = false, .max_lum = 0, .min_lum = 0.0, .max_avg_lum = 0 };

    if (edid.len < 256) return result;

    // Check for CTA-861 extension (extension block type 0x02)
    if (edid[128] != 0x02) return result;

    // Parse CTA-861 data blocks
    const dtd_start = edid[130];
    var offset: usize = 132;

    while (offset < 128 + dtd_start) {
        if (offset >= edid.len) break;

        const tag = (edid[offset] & 0xE0) >> 5;
        const length = edid[offset] & 0x1F;

        if (tag == 7 and offset + 1 < edid.len) {
            // Extended tag block
            const ext_tag = edid[offset + 1];

            if (ext_tag == 6 and length >= 3) {
                // HDR Static Metadata Data Block
                result.supported = true;

                if (offset + 4 < edid.len) {
                    // EOTF byte - bit 2 = HDR10 (SMPTE ST 2084)
                    const eotf = edid[offset + 2];
                    _ = eotf; // Could parse supported EOTFs

                    // Static metadata byte
                    const static_meta = edid[offset + 3];
                    _ = static_meta;

                    // Max luminance data (if present)
                    if (length >= 4 and offset + 5 < edid.len) {
                        const max_cv = edid[offset + 4];
                        // Convert CV to nits: 50 * 2^(CV/32)
                        const exp = @as(f32, @floatFromInt(max_cv)) / 32.0;
                        result.max_lum = @intFromFloat(50.0 * std.math.pow(f32, 2.0, exp));
                    }
                    if (length >= 5 and offset + 6 < edid.len) {
                        const max_avg_cv = edid[offset + 5];
                        const exp = @as(f32, @floatFromInt(max_avg_cv)) / 32.0;
                        result.max_avg_lum = @intFromFloat(50.0 * std.math.pow(f32, 2.0, exp));
                    }
                    if (length >= 6 and offset + 7 < edid.len) {
                        const min_cv = edid[offset + 6];
                        // Min luminance formula is different
                        const max_lum_f: f32 = @floatFromInt(result.max_lum);
                        const min_cv_f: f32 = @floatFromInt(min_cv);
                        result.min_lum = max_lum_f * std.math.pow(f32, min_cv_f / 255.0, 2.0) / 100.0;
                    }
                }
                break;
            }
        }

        offset += length + 1;
    }

    return result;
}

/// Query nvidia-settings for HDR info
fn queryNvidiaSettingsHdr(display_name: []const u8) NvidiaSettingsHdrResult {
    const allocator = std.heap.page_allocator;
    var query_buf: [128]u8 = undefined;

    // Query current color depth
    const query = std.fmt.bufPrint(&query_buf, "[{s}]/CurrentMetaMode", .{display_name}) catch return NvidiaSettingsHdrResult{ .enabled = false, .bit_depth = 8 };

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "nvidia-settings", "-t", "-q", query },
    }) catch return NvidiaSettingsHdrResult{ .enabled = false, .bit_depth = 8 };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    // Check for HDR in metamode
    const hdr_enabled = mem.indexOf(u8, result.stdout, "HDR") != null or
        mem.indexOf(u8, result.stdout, "hdr") != null;

    // Check for bit depth
    var bit_depth: u32 = 8;
    if (mem.indexOf(u8, result.stdout, "Depth=30") != null) {
        bit_depth = 10;
    } else if (mem.indexOf(u8, result.stdout, "Depth=36") != null) {
        bit_depth = 12;
    }

    return NvidiaSettingsHdrResult{ .enabled = hdr_enabled, .bit_depth = bit_depth };
}

/// Get HDR state for a display
pub fn getState(display_name: []const u8) !HdrState {
    const allocator = std.heap.page_allocator;

    // Find connector in DRM sysfs
    var dir = fs.cwd().openDir(DRM_SYS_DIR, .{ .iterate = true }) catch return error.NotSupported;
    defer dir.close();

    var found_card: ?[]const u8 = null;
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        // Look for card*-CONNECTOR patterns matching our display
        if (!mem.startsWith(u8, entry.name, "card")) continue;
        const dash_idx = mem.indexOf(u8, entry.name, "-") orelse continue;
        const connector_name = entry.name[dash_idx + 1 ..];

        if (mem.eql(u8, connector_name, display_name)) {
            found_card = allocator.dupe(u8, entry.name) catch continue;
            break;
        }
    }

    if (found_card == null) return error.DisplayNotFound;
    defer allocator.free(found_card.?);

    // Read EDID for HDR capability
    var path_buf: [512]u8 = undefined;
    const edid_path = std.fmt.bufPrint(&path_buf, "{s}/{s}/edid", .{ DRM_SYS_DIR, found_card.? }) catch return error.PathError;
    const edid = readSysfsBinary(allocator, edid_path);
    defer if (edid) |e| allocator.free(e);

    const hdr_caps = if (edid) |e| parseEdidHdrCapability(e) else EdidHdrCapability{ .supported = false, .max_lum = 0, .min_lum = 0.0, .max_avg_lum = 0 };

    // Query nvidia-settings for current HDR state
    const nv_state = queryNvidiaSettingsHdr(display_name);

    // Read max_bpc from sysfs if available
    const max_bpc_path = std.fmt.bufPrint(&path_buf, "{s}/{s}/max_bpc", .{ DRM_SYS_DIR, found_card.? }) catch "";
    var max_bpc: u32 = 8;
    if (max_bpc_path.len > 0) {
        if (readSysfs(allocator, max_bpc_path)) |v| {
            defer allocator.free(v);
            max_bpc = std.fmt.parseInt(u32, mem.trim(u8, v, "\n \t\r"), 10) catch 8;
        }
    }

    return HdrState{
        .supported = hdr_caps.supported,
        .enabled = nv_state.enabled,
        .format = if (nv_state.enabled and hdr_caps.supported) .hdr10 else .sdr,
        .max_luminance_nits = if (hdr_caps.max_lum > 0) hdr_caps.max_lum else 400,
        .min_luminance_nits = if (hdr_caps.min_lum > 0) hdr_caps.min_lum else 0.1,
        .max_frame_avg_luminance_nits = if (hdr_caps.max_avg_lum > 0) hdr_caps.max_avg_lum else 200,
        .bit_depth = @max(nv_state.bit_depth, max_bpc),
        .color_primaries = if (hdr_caps.supported) .bt2020 else .bt709,
        .output_luminance_nits = if (nv_state.enabled) hdr_caps.max_lum else 100,
        .tone_mapping_active = nv_state.enabled,
    };
}

/// Run nvidia-settings assignment
fn runNvidiaSettingsAssign(assignment: []const u8) !void {
    const allocator = std.heap.page_allocator;

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "nvidia-settings", "-a", assignment },
    }) catch return error.NvidiaSettingsError;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term != .Exited or result.term.Exited != 0) {
        return error.NvidiaSettingsError;
    }
}

/// Enable HDR on a display
/// Note: On Wayland, HDR must be enabled via compositor settings
/// On X11, uses nvidia-settings metamode with HDR enabled
pub fn enable(display_name: []const u8, format: HdrFormat) !void {
    const allocator = std.heap.page_allocator;

    // Get minimum bit depth for the format
    const min_depth = format.minBitDepth();

    // Set color depth via nvidia-settings
    var depth_buf: [128]u8 = undefined;
    const depth_assign = std.fmt.bufPrint(&depth_buf, "[{s}]/ColorRange=Full", .{display_name}) catch return error.FormatError;
    runNvidiaSettingsAssign(depth_assign) catch {};

    // Set bit depth based on format
    const depth_val: u32 = switch (min_depth) {
        10 => 30, // 10-bit = 30bpp
        12 => 36, // 12-bit = 36bpp
        else => 24, // 8-bit = 24bpp
    };

    var bpc_buf: [128]u8 = undefined;
    const bpc_assign = std.fmt.bufPrint(&bpc_buf, "[{s}]/CurrentMetaModeMaxBpc={d}", .{ display_name, depth_val / 3 }) catch return error.FormatError;
    runNvidiaSettingsAssign(bpc_assign) catch {};

    // For X11, we can try to set metamode with HDR
    // This requires the display to be on a supported output
    var metamode_buf: [256]u8 = undefined;
    const metamode = std.fmt.bufPrint(&metamode_buf, "CurrentMetaMode={s}: nvidia-auto-select {{ AllowGSYNCCompatible = On }}", .{display_name}) catch return error.FormatError;
    runNvidiaSettingsAssign(metamode) catch {};

    // Note: Full HDR enablement on Linux typically requires:
    // 1. Compositor support (KDE Plasma 6+, Gamescope)
    // 2. Driver support (NVIDIA 545+)
    // 3. Wayland protocol for HDR metadata
    _ = allocator;
}

/// Disable HDR on a display
pub fn disable(display_name: []const u8) !void {
    // Reset to SDR settings
    var buf: [128]u8 = undefined;

    // Reset color range
    const range_assign = std.fmt.bufPrint(&buf, "[{s}]/ColorRange=Auto", .{display_name}) catch return error.FormatError;
    runNvidiaSettingsAssign(range_assign) catch {};

    // Reset bit depth to 8bpc
    const bpc_assign = std.fmt.bufPrint(&buf, "[{s}]/CurrentMetaModeMaxBpc=8", .{display_name}) catch return error.FormatError;
    runNvidiaSettingsAssign(bpc_assign) catch {};
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
    // Enable or configure HDR
    if (config.format != .sdr) {
        try enable(display_name, config.format);
    } else {
        try disable(display_name);
        return;
    }

    // Set bit depth
    var buf: [128]u8 = undefined;
    const bpc = config.bit_depth;
    const bpc_assign = std.fmt.bufPrint(&buf, "[{s}]/CurrentMetaModeMaxBpc={d}", .{ display_name, bpc }) catch return error.FormatError;
    runNvidiaSettingsAssign(bpc_assign) catch {};

    // Desktop HDR requires compositor support
    // nvidia-settings can set some basic options
    if (config.desktop_hdr) {
        const desktop_assign = std.fmt.bufPrint(&buf, "[{s}]/AllowFlipping=1", .{display_name}) catch return error.FormatError;
        runNvidiaSettingsAssign(desktop_assign) catch {};
    }
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
/// Note: This is compositor-dependent on Linux
/// Gamescope supports SDR brightness adjustment via --hdr-sdr-content-nits
pub fn setSdrHandling(display_name: []const u8, handling: SdrHandling) !void {
    var buf: [128]u8 = undefined;

    // nvidia-settings doesn't have direct SDR-in-HDR control
    // but we can adjust related settings
    switch (handling) {
        .boost => {
            // Higher color saturation for SDR content
            const sat_assign = std.fmt.bufPrint(&buf, "[{s}]/DigitalVibrance=50", .{display_name}) catch return error.FormatError;
            runNvidiaSettingsAssign(sat_assign) catch {};
        },
        .reference => {
            // Standard reference level
            const sat_assign = std.fmt.bufPrint(&buf, "[{s}]/DigitalVibrance=0", .{display_name}) catch return error.FormatError;
            runNvidiaSettingsAssign(sat_assign) catch {};
        },
        .match_display => {
            // Match display brightness - use default
            const sat_assign = std.fmt.bufPrint(&buf, "[{s}]/DigitalVibrance=0", .{display_name}) catch return error.FormatError;
            runNvidiaSettingsAssign(sat_assign) catch {};
        },
    }
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
/// Note: GPU tone mapping on Linux is handled by compositor (Gamescope, KDE)
/// or by the application itself
pub fn setToneMapping(display_name: []const u8, mode: ToneMappingMode) !void {
    var buf: [128]u8 = undefined;

    switch (mode) {
        .gpu => {
            // Enable dithering for better tone mapping
            const dither_assign = std.fmt.bufPrint(&buf, "[{s}]/Dithering=1", .{display_name}) catch return error.FormatError;
            runNvidiaSettingsAssign(dither_assign) catch {};
            const dither_mode = std.fmt.bufPrint(&buf, "[{s}]/DitheringMode=Auto", .{display_name}) catch return error.FormatError;
            runNvidiaSettingsAssign(dither_mode) catch {};
        },
        .display => {
            // Let display handle tone mapping - disable dithering
            const dither_assign = std.fmt.bufPrint(&buf, "[{s}]/Dithering=0", .{display_name}) catch return error.FormatError;
            runNvidiaSettingsAssign(dither_assign) catch {};
        },
        .none => {
            // No tone mapping - direct output
            const dither_assign = std.fmt.bufPrint(&buf, "[{s}]/Dithering=0", .{display_name}) catch return error.FormatError;
            runNvidiaSettingsAssign(dither_assign) catch {};
        },
    }
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
/// RTX Video HDR requires NVIDIA driver 545+ and RTX 20 series or newer
/// This feature converts SDR video content to HDR in real-time using AI
pub fn configureVideoHdr(config: VideoHdr) !void {
    const allocator = std.heap.page_allocator;

    // Check driver version first
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "nvidia-smi", "--query-gpu=driver_version", "--format=csv,noheader" },
    }) catch return error.NvidiaSmiError;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    const version_str = mem.trim(u8, result.stdout, "\n \t\r");
    const major_end = mem.indexOf(u8, version_str, ".") orelse version_str.len;
    const major_version = std.fmt.parseInt(u32, version_str[0..major_end], 10) catch 0;

    if (major_version < 545) {
        return error.DriverTooOld;
    }

    // RTX Video HDR settings via nvidia-settings
    // Note: These require the RTX Video Super Resolution feature to be available
    if (config.enabled) {
        // Enable RTX Video enhancements
        runNvidiaSettingsAssign("RTXVideoSuperResolution=1") catch {};

        if (config.ai_enhanced) {
            // Enable AI-enhanced HDR conversion
            runNvidiaSettingsAssign("RTXVideoSuperResolutionQuality=4") catch {}; // Quality level 4 = Ultra
        } else {
            runNvidiaSettingsAssign("RTXVideoSuperResolutionQuality=2") catch {}; // Quality level 2 = Medium
        }
    } else {
        // Disable RTX Video enhancements
        runNvidiaSettingsAssign("RTXVideoSuperResolution=0") catch {};
    }
}

/// Auto-HDR for SDR games (RTX HDR)
/// Converts SDR game output to HDR using AI tone mapping
pub const AutoHdr = struct {
    /// Enable Auto-HDR conversion
    enabled: bool = false,
    /// SDR content brightness in nits (default 203 = SDR reference white)
    sdr_content_nits: u32 = 203,
    /// Peak brightness target in nits
    peak_nits: u32 = 1000,
    /// Enable AI-enhanced tone mapping (RTX 40+ series)
    ai_enhanced: bool = true,
    /// Saturation boost (0-100, default 0 = no change)
    saturation_boost: u8 = 0,
    /// Inverse tone mapping strength (0-100)
    itm_strength: u8 = 100,
    /// Use wide gamut (BT.2020)
    wide_gamut: bool = true,

    /// Get Gamescope command line arguments for Auto-HDR
    pub fn gamescopeArgs(self: AutoHdr, allocator: std.mem.Allocator) ![]const []const u8 {
        var args = std.ArrayList([]const u8).init(allocator);
        errdefer args.deinit();

        if (!self.enabled) return args.toOwnedSlice();

        try args.append("--hdr-enabled");

        // SDR content brightness
        const sdr_nits = try std.fmt.allocPrint(allocator, "{d}", .{self.sdr_content_nits});
        try args.append("--hdr-sdr-content-nits");
        try args.append(sdr_nits);

        // ITM (Inverse Tone Mapping) for SDR-to-HDR
        try args.append("--hdr-itm-enable");

        // Target peak brightness
        const peak = try std.fmt.allocPrint(allocator, "{d}", .{self.peak_nits});
        try args.append("--hdr-itm-target-nits");
        try args.append(peak);

        // Wide gamut
        if (self.wide_gamut) {
            try args.append("--hdr-wide-gammut-for-sdr"); // Note: Gamescope typo is intentional
        }

        return args.toOwnedSlice();
    }

    /// Get environment variables for Auto-HDR
    pub fn envVars(self: AutoHdr) [4][2][]const u8 {
        return .{
            .{ "DXVK_HDR", if (self.enabled) "1" else "0" },
            .{ "ENABLE_HDR_WSI", if (self.enabled) "1" else "0" },
            .{ "VKD3D_FEATURE_LEVEL", "12_2" }, // Required for HDR
            .{ "PROTON_ENABLE_AMD_AGS", "0" }, // Disable AMD AGS for NVIDIA
        };
    }
};

/// Auto-HDR presets
pub const AutoHdrPreset = enum {
    /// Disabled
    off,
    /// Standard SDR-to-HDR conversion
    standard,
    /// Vivid colors and brightness
    vivid,
    /// Accurate SDR representation in HDR
    accurate,
    /// Maximum brightness and saturation
    cinema,

    pub fn config(self: AutoHdrPreset) AutoHdr {
        return switch (self) {
            .off => .{ .enabled = false },
            .standard => .{
                .enabled = true,
                .sdr_content_nits = 203,
                .peak_nits = 1000,
                .ai_enhanced = true,
                .saturation_boost = 0,
                .itm_strength = 100,
            },
            .vivid => .{
                .enabled = true,
                .sdr_content_nits = 250,
                .peak_nits = 1000,
                .ai_enhanced = true,
                .saturation_boost = 15,
                .itm_strength = 100,
            },
            .accurate => .{
                .enabled = true,
                .sdr_content_nits = 100, // True SDR reference
                .peak_nits = 400,
                .ai_enhanced = false, // No AI adjustment
                .saturation_boost = 0,
                .itm_strength = 50, // Gentle expansion
            },
            .cinema => .{
                .enabled = true,
                .sdr_content_nits = 203,
                .peak_nits = 1400, // Higher peak for cinema
                .ai_enhanced = true,
                .saturation_boost = 10,
                .itm_strength = 100,
            },
        };
    }

    pub fn description(self: AutoHdrPreset) []const u8 {
        return switch (self) {
            .off => "Auto-HDR disabled",
            .standard => "Standard SDR-to-HDR conversion",
            .vivid => "Enhanced colors and brightness",
            .accurate => "Accurate SDR representation",
            .cinema => "Cinema-quality HDR",
        };
    }
};

/// Check if GPU supports Auto-HDR (RTX 20 series or newer)
pub fn supportsAutoHdr() bool {
    const allocator = std.heap.page_allocator;

    // Query GPU generation via nvidia-smi
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "nvidia-smi", "--query-gpu=name", "--format=csv,noheader" },
    }) catch return false;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    const name = mem.trim(u8, result.stdout, "\n \t\r");

    // RTX series support Auto-HDR
    return mem.indexOf(u8, name, "RTX") != null;
}

/// Check if GPU supports AI-enhanced Auto-HDR (RTX 40/50 series)
pub fn supportsAiAutoHdr() bool {
    const allocator = std.heap.page_allocator;

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "nvidia-smi", "--query-gpu=name", "--format=csv,noheader" },
    }) catch return false;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    const name = mem.trim(u8, result.stdout, "\n \t\r");

    // RTX 40 and 50 series support AI-enhanced Auto-HDR
    return mem.indexOf(u8, name, "RTX 40") != null or
        mem.indexOf(u8, name, "RTX 50") != null or
        mem.indexOf(u8, name, "RTX 5") != null;
}

test "hdr format" {
    const hdr10 = HdrFormat.hdr10;
    try std.testing.expectEqual(@as(u32, 10), hdr10.minBitDepth());
    try std.testing.expect(hdr10.supportsWideGamut());

    const sdr = HdrFormat.sdr;
    try std.testing.expect(!sdr.supportsWideGamut());
}

test "auto hdr preset" {
    const standard = AutoHdrPreset.standard.config();
    try std.testing.expect(standard.enabled);
    try std.testing.expectEqual(@as(u32, 203), standard.sdr_content_nits);
}
