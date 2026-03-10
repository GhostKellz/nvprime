//! nvdisplay/vrr - Variable Refresh Rate Control
//!
//! Generic VRR control (FreeSync, Adaptive Sync) beyond G-Sync specific features.
//! Uses DRM sysfs for capability detection and nvidia-settings for control.
//!
//! Driver 595+ provides enhanced VRR range detection via DRM properties.

const std = @import("std");
const Io = std.Io;
const Dir = Io.Dir;
const File = Io.File;
const mem = std.mem;
const posix = std.posix;

// Re-export VrrSource from DRM module for tracking detection method
pub const VrrSource = @import("../nvruntime/primetime/drm.zig").VrrSource;

/// VRR technology type
pub const VrrType = enum {
    none,
    gsync, // Native G-Sync
    gsync_compatible, // G-Sync Compatible / Adaptive Sync
    freesync, // AMD FreeSync (on NVIDIA via Adaptive Sync)
    vesa_adaptive_sync, // VESA Adaptive Sync standard

    pub fn description(self: VrrType) []const u8 {
        return switch (self) {
            .none => "No VRR support",
            .gsync => "NVIDIA G-Sync",
            .gsync_compatible => "G-Sync Compatible",
            .freesync => "AMD FreeSync",
            .vesa_adaptive_sync => "VESA Adaptive Sync",
        };
    }
};

/// VRR state
pub const VrrState = struct {
    vrr_type: VrrType,
    enabled: bool,
    min_hz: u32,
    max_hz: u32,
    current_hz: u32,
    // Advanced features
    lfc_supported: bool, // Low Framerate Compensation
    lfc_active: bool,
    vrr_in_use: bool, // Currently varying refresh rate
    // Driver 595+ source tracking
    source: VrrSource = .default,

    pub fn range(self: VrrState) u32 {
        return self.max_hz - self.min_hz;
    }

    pub fn inVrrRange(self: VrrState, fps: u32) bool {
        return fps >= self.min_hz and fps <= self.max_hz;
    }

    pub fn lfcThreshold(self: VrrState) u32 {
        return self.min_hz;
    }

    /// Check if VRR range info is from a reliable source (DRM property)
    pub fn isRangeReliable(self: VrrState) bool {
        return self.source.isReliable();
    }
};

/// DRM sysfs path
const DRM_SYS_DIR = "/sys/class/drm";

/// Read sysfs file value using posix API
fn readSysfs(allocator: mem.Allocator, path: []const u8) ?[]const u8 {
    // Convert to null-terminated path
    var path_buf: [512]u8 = undefined;
    if (path.len >= path_buf.len) return null;
    @memcpy(path_buf[0..path.len], path);
    path_buf[path.len] = 0;
    const path_z: [*:0]const u8 = @ptrCast(path_buf[0..path.len :0].ptr);

    const fd = posix.openatZ(posix.AT.FDCWD, path_z, .{ .ACCMODE = .RDONLY }, 0) catch return null;
    defer std.Io.Threaded.closeFd(fd);

    var buf: [256]u8 = undefined;
    const len = posix.read(fd, &buf) catch return null;
    return allocator.dupe(u8, buf[0..len]) catch null;
}

/// Read sysfs binary file (for EDID) using posix API
fn readSysfsBinary(allocator: mem.Allocator, path: []const u8) ?[]const u8 {
    // Convert to null-terminated path
    var path_buf: [512]u8 = undefined;
    if (path.len >= path_buf.len) return null;
    @memcpy(path_buf[0..path.len], path);
    path_buf[path.len] = 0;
    const path_z: [*:0]const u8 = @ptrCast(path_buf[0..path.len :0].ptr);

    const fd = posix.openatZ(posix.AT.FDCWD, path_z, .{ .ACCMODE = .RDONLY }, 0) catch return null;
    defer std.Io.Threaded.closeFd(fd);

    var buf: [512]u8 = undefined;
    const len = posix.read(fd, &buf) catch return null;
    return allocator.dupe(u8, buf[0..len]) catch null;
}

/// VRR range from EDID
const VrrRange = struct { min: u32, max: u32 };

/// Parse EDID for VRR range from Display Range Limits or CTA-861
fn parseEdidVrrRange(edid: []const u8) VrrRange {
    var result = VrrRange{ .min = 48, .max = 60 };

    if (edid.len < 128) return result;

    // Look for Display Range Limits descriptor (tag 0xFD) in base EDID
    var offset: usize = 54;
    while (offset + 18 <= 126) : (offset += 18) {
        if (edid[offset] == 0 and edid[offset + 1] == 0 and edid[offset + 2] == 0 and edid[offset + 3] == 0xFD) {
            result.min = edid[offset + 5];
            result.max = edid[offset + 6];

            // Check for extended timing (offset flags)
            if (edid[offset + 4] & 0x02 != 0) {
                result.max += 255;
            }
            break;
        }
    }

    // Check CTA-861 extension for FreeSync/VRR range
    if (edid.len >= 256 and edid[128] == 0x02) {
        const dtd_start = edid[130];
        var ext_offset: usize = 132;

        while (ext_offset < 128 + dtd_start) {
            if (ext_offset >= edid.len) break;

            const tag = (edid[ext_offset] & 0xE0) >> 5;
            const length = edid[ext_offset] & 0x1F;

            if (tag == 7 and ext_offset + 1 < edid.len) {
                const ext_tag = edid[ext_offset + 1];
                // Vendor-Specific Video Data Block for FreeSync (AMD) or Adaptive Sync
                if (ext_tag == 0x1A and length >= 4) {
                    // VFPDB - Video Format Preference Data Block
                    // Contains VRR range info
                    if (ext_offset + 4 < edid.len) {
                        result.min = edid[ext_offset + 2];
                        result.max = edid[ext_offset + 3];
                    }
                }
            }

            ext_offset += length + 1;
        }
    }

    return result;
}

/// Query nvidia-settings for VRR state
fn queryNvidiaSettingsVrr() struct { gsync_enabled: bool, gsync_compat: bool } {
    const allocator = std.heap.page_allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    var gsync_enabled = false;
    var gsync_compat = false;

    // Query AllowGSYNC
    const result1 = std.process.run(allocator, io, .{
        .argv = &.{ "nvidia-settings", "-t", "-q", "AllowGSYNC" },
    }) catch return .{ .gsync_enabled = false, .gsync_compat = false };
    defer allocator.free(result1.stdout);
    defer allocator.free(result1.stderr);

    if (mem.indexOf(u8, result1.stdout, "1") != null) {
        gsync_enabled = true;
    }

    // Query AllowGSYNCCompatible
    const result2 = std.process.run(allocator, io, .{
        .argv = &.{ "nvidia-settings", "-t", "-q", "AllowGSYNCCompatible" },
    }) catch return .{ .gsync_enabled = gsync_enabled, .gsync_compat = false };
    defer allocator.free(result2.stdout);
    defer allocator.free(result2.stderr);

    if (mem.indexOf(u8, result2.stdout, "1") != null) {
        gsync_compat = true;
    }

    return .{ .gsync_enabled = gsync_enabled, .gsync_compat = gsync_compat };
}

/// Get VRR state for a display
pub fn getState(display_name: []const u8) !VrrState {
    const allocator = std.heap.page_allocator;
    const io = Io.Threaded.global_single_threaded.io();

    // Find connector in DRM sysfs
    var dir = Dir.openDirAbsolute(io, DRM_SYS_DIR, .{ .iterate = true }) catch return error.NotSupported;
    defer dir.close(io);

    var found_card: ?[]const u8 = null;
    var iter = dir.iterate();
    while (iter.next(io) catch null) |entry| {
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

    var path_buf: [512]u8 = undefined;

    // Read vrr_capable from sysfs
    const vrr_cap_path = std.fmt.bufPrint(&path_buf, "{s}/{s}/vrr_capable", .{ DRM_SYS_DIR, found_card.? }) catch "";
    var vrr_capable = false;
    if (vrr_cap_path.len > 0) {
        if (readSysfs(allocator, vrr_cap_path)) |v| {
            defer allocator.free(v);
            vrr_capable = mem.eql(u8, mem.trim(u8, v, "\n \t\r"), "1");
        }
    }

    // Try DRM properties first (Driver 595+)
    var vrr_range = VrrRange{ .min = 48, .max = 60 };
    var source: VrrSource = .default;

    // Read vrr_min_hz from sysfs (DRM property exposed by 595+ driver)
    const vrr_min_path = std.fmt.bufPrint(&path_buf, "{s}/{s}/vrr_min_hz", .{ DRM_SYS_DIR, found_card.? }) catch "";
    var min_from_drm: ?u32 = null;
    if (vrr_min_path.len > 0) {
        if (readSysfs(allocator, vrr_min_path)) |v| {
            defer allocator.free(v);
            min_from_drm = std.fmt.parseInt(u32, mem.trim(u8, v, "\n \t\r"), 10) catch null;
        }
    }

    // Read vrr_max_hz from sysfs (DRM property exposed by 595+ driver)
    const vrr_max_path = std.fmt.bufPrint(&path_buf, "{s}/{s}/vrr_max_hz", .{ DRM_SYS_DIR, found_card.? }) catch "";
    var max_from_drm: ?u32 = null;
    if (vrr_max_path.len > 0) {
        if (readSysfs(allocator, vrr_max_path)) |v| {
            defer allocator.free(v);
            max_from_drm = std.fmt.parseInt(u32, mem.trim(u8, v, "\n \t\r"), 10) catch null;
        }
    }

    // Use DRM properties if available (most accurate)
    if (min_from_drm != null and max_from_drm != null) {
        vrr_range.min = min_from_drm.?;
        vrr_range.max = max_from_drm.?;
        source = .drm_property;
    } else if (max_from_drm != null) {
        vrr_range.max = max_from_drm.?;
        source = .drm_property;
    } else {
        // Fallback to EDID parsing
        const edid_path = std.fmt.bufPrint(&path_buf, "{s}/{s}/edid", .{ DRM_SYS_DIR, found_card.? }) catch "";
        const edid = if (edid_path.len > 0) readSysfsBinary(allocator, edid_path) else null;
        defer if (edid) |e| allocator.free(e);

        if (edid) |e| {
            vrr_range = parseEdidVrrRange(e);
            source = .edid_parsed;
        }
    }

    // Query nvidia-settings for current state
    const nv_state = queryNvidiaSettingsVrr();

    // Determine VRR type
    var vrr_type: VrrType = .none;
    if (nv_state.gsync_enabled) {
        vrr_type = .gsync;
    } else if (nv_state.gsync_compat) {
        vrr_type = .gsync_compatible;
    } else if (vrr_capable) {
        vrr_type = .vesa_adaptive_sync;
    }

    // Update source to nvidia_settings if that's how we detected the type
    if (source == .default and (nv_state.gsync_enabled or nv_state.gsync_compat)) {
        source = .nvidia_settings;
    }

    // LFC is supported when VRR range is at least 2:1 (conservative)
    const lfc_supported = vrr_capable and (vrr_range.max >= vrr_range.min * 2);

    return VrrState{
        .vrr_type = vrr_type,
        .enabled = nv_state.gsync_enabled or nv_state.gsync_compat,
        .min_hz = vrr_range.min,
        .max_hz = vrr_range.max,
        .current_hz = vrr_range.max, // Can't easily query current without DRM
        .lfc_supported = lfc_supported,
        .lfc_active = false, // Would need real-time monitoring
        .vrr_in_use = nv_state.gsync_enabled or nv_state.gsync_compat,
        .source = source,
    };
}

/// Run nvidia-settings assignment
fn runNvidiaSettingsAssign(assignment: []const u8) !void {
    const allocator = std.heap.page_allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const result = std.process.run(allocator, io, .{
        .argv = &.{ "nvidia-settings", "-a", assignment },
    }) catch return error.NvidiaSettingsError;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term != .exited or result.term.exited != 0) {
        return error.NvidiaSettingsError;
    }
}

/// Enable VRR on a display
/// Uses nvidia-settings to enable G-Sync and G-Sync Compatible mode
pub fn enable(display_name: []const u8) !void {
    _ = display_name;

    // Enable G-Sync
    try runNvidiaSettingsAssign("AllowGSYNC=1");

    // Enable G-Sync Compatible (Adaptive Sync)
    try runNvidiaSettingsAssign("AllowGSYNCCompatible=1");
}

/// Disable VRR on a display
pub fn disable(display_name: []const u8) !void {
    _ = display_name;

    // Disable G-Sync
    try runNvidiaSettingsAssign("AllowGSYNC=0");
    try runNvidiaSettingsAssign("AllowGSYNCCompatible=0");
}

/// VRR mode for gaming
pub const VrrMode = enum {
    /// VRR disabled, fixed refresh
    fixed,
    /// VRR with vsync on (no tearing, some latency)
    adaptive_vsync,
    /// VRR with vsync off (tearing above max, lower latency)
    adaptive_no_vsync,
    /// VRR with NVIDIA Reflex for minimum latency
    low_latency,

    pub fn description(self: VrrMode) []const u8 {
        return switch (self) {
            .fixed => "Fixed refresh rate (VRR off)",
            .adaptive_vsync => "Adaptive VSync (no tearing)",
            .adaptive_no_vsync => "Adaptive (tearing above max)",
            .low_latency => "Low latency mode with Reflex",
        };
    }

    pub fn latencyPriority(self: VrrMode) u32 {
        return switch (self) {
            .fixed => 0,
            .adaptive_vsync => 1,
            .adaptive_no_vsync => 2,
            .low_latency => 3,
        };
    }
};

/// Set VRR mode
/// Configures VRR behavior including vsync and latency settings
pub fn setMode(display_name: []const u8, mode: VrrMode) !void {
    _ = display_name;

    switch (mode) {
        .fixed => {
            // Disable VRR
            try runNvidiaSettingsAssign("AllowGSYNC=0");
            try runNvidiaSettingsAssign("AllowGSYNCCompatible=0");
        },
        .adaptive_vsync => {
            // Enable VRR with vsync on
            try runNvidiaSettingsAssign("AllowGSYNC=1");
            try runNvidiaSettingsAssign("AllowGSYNCCompatible=1");
            try runNvidiaSettingsAssign("SyncToVBlank=1");
        },
        .adaptive_no_vsync => {
            // Enable VRR with vsync off (allows tearing above max)
            try runNvidiaSettingsAssign("AllowGSYNC=1");
            try runNvidiaSettingsAssign("AllowGSYNCCompatible=1");
            try runNvidiaSettingsAssign("SyncToVBlank=0");
        },
        .low_latency => {
            // Enable VRR with low latency mode
            try runNvidiaSettingsAssign("AllowGSYNC=1");
            try runNvidiaSettingsAssign("AllowGSYNCCompatible=1");
            try runNvidiaSettingsAssign("SyncToVBlank=0");
            // Ultra low latency mode
            try runNvidiaSettingsAssign("AllowFlipping=1");
        },
    }
}

/// Frame timing info
pub const FrameTiming = struct {
    /// Last frame time in microseconds
    frame_time_us: u64,
    /// Target frame time based on VRR
    target_frame_time_us: u64,
    /// Current effective refresh rate
    effective_hz: f32,
    /// Frames in flight
    frames_in_flight: u32,

    pub fn fps(self: FrameTiming) f32 {
        if (self.frame_time_us == 0) return 0;
        return 1_000_000.0 / @as(f32, @floatFromInt(self.frame_time_us));
    }
};

/// Get current frame timing
/// Note: Accurate frame timing requires Vulkan/OpenGL instrumentation
/// This provides estimates based on display refresh rate
pub fn getFrameTiming(display_name: []const u8) !FrameTiming {
    // Get VRR state for refresh rate info
    const state = try getState(display_name);

    // Estimate frame time from max refresh (worst case)
    const target_hz: f32 = @floatFromInt(state.max_hz);
    const target_frame_time_us: u64 = @intFromFloat(1_000_000.0 / target_hz);

    // Current frame time would need real-time measurement
    // For now, estimate based on current_hz
    const current_hz: f32 = @floatFromInt(state.current_hz);
    const frame_time_us: u64 = @intFromFloat(1_000_000.0 / current_hz);

    return FrameTiming{
        .frame_time_us = frame_time_us,
        .target_frame_time_us = target_frame_time_us,
        .effective_hz = current_hz,
        .frames_in_flight = 2, // Typical double buffering
    };
}

/// VRR statistics
pub const VrrStats = struct {
    /// Total frames with VRR active
    vrr_frames: u64,
    /// Frames where LFC was used
    lfc_frames: u64,
    /// Average refresh rate
    avg_refresh_hz: f32,
    /// Min/max refresh used
    min_refresh_hz: u32,
    max_refresh_hz: u32,
    /// Frames with tearing (above max or VRR off)
    torn_frames: u64,
};

/// VRR stats storage (per-session, not persistent)
var g_vrr_stats = VrrStats{
    .vrr_frames = 0,
    .lfc_frames = 0,
    .avg_refresh_hz = 0,
    .min_refresh_hz = 0,
    .max_refresh_hz = 0,
    .torn_frames = 0,
};

/// Get VRR statistics
/// Note: Real-time VRR statistics require continuous monitoring
/// This provides session-based estimates
pub fn getStats(display_name: []const u8) !VrrStats {
    // Get current state to populate range info
    const state = getState(display_name) catch return g_vrr_stats;

    // Update stats with current state info
    if (state.enabled) {
        g_vrr_stats.min_refresh_hz = state.min_hz;
        g_vrr_stats.max_refresh_hz = state.max_hz;
        if (g_vrr_stats.avg_refresh_hz == 0) {
            g_vrr_stats.avg_refresh_hz = @floatFromInt(state.current_hz);
        }
    }

    return g_vrr_stats;
}

/// Reset VRR statistics
pub fn resetStats(display_name: []const u8) !void {
    _ = display_name;

    g_vrr_stats = VrrStats{
        .vrr_frames = 0,
        .lfc_frames = 0,
        .avg_refresh_hz = 0,
        .min_refresh_hz = 0,
        .max_refresh_hz = 0,
        .torn_frames = 0,
    };
}

test "vrr state" {
    const state = VrrState{
        .vrr_type = .gsync_compatible,
        .enabled = true,
        .min_hz = 48,
        .max_hz = 144,
        .current_hz = 120,
        .lfc_supported = true,
        .lfc_active = false,
        .vrr_in_use = true,
        .source = .drm_property,
    };
    try std.testing.expectEqual(@as(u32, 96), state.range());
    try std.testing.expect(state.inVrrRange(100));
    try std.testing.expect(!state.inVrrRange(30));
    try std.testing.expect(state.isRangeReliable());
}
