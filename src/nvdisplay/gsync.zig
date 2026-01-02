//! nvdisplay/gsync - G-Sync / G-Sync Compatible Control
//!
//! NVIDIA's adaptive sync technology for tear-free gaming.

const std = @import("std");

/// G-Sync mode
pub const GsyncMode = enum {
    /// G-Sync disabled
    disabled,
    /// Native G-Sync (G-Sync module in monitor)
    native,
    /// G-Sync Compatible (Adaptive Sync / FreeSync monitor)
    compatible,
    /// G-Sync Ultimate (HDR + native)
    ultimate,

    pub fn description(self: GsyncMode) []const u8 {
        return switch (self) {
            .disabled => "G-Sync disabled",
            .native => "Native G-Sync (hardware module)",
            .compatible => "G-Sync Compatible (Adaptive Sync)",
            .ultimate => "G-Sync Ultimate (HDR capable)",
        };
    }

    pub fn supportsHdr(self: GsyncMode) bool {
        return self == .ultimate;
    }
};

/// G-Sync state for a display
pub const GsyncState = struct {
    mode: GsyncMode,
    enabled: bool,
    min_refresh_hz: u32,
    max_refresh_hz: u32,
    current_refresh_hz: u32,
    lfc_supported: bool, // Low Framerate Compensation
    lfc_active: bool,
    pulsar_supported: bool, // G-Sync Pulsar (strobing)
    pulsar_active: bool,

    pub fn vrrRange(self: GsyncState) u32 {
        return self.max_refresh_hz - self.min_refresh_hz;
    }

    pub fn lfcThreshold(self: GsyncState) u32 {
        // LFC kicks in when framerate drops below min VRR range
        // by using integer multiples of the frame time
        return self.min_refresh_hz;
    }
};

/// Run nvidia-settings query and return output
fn runNvidiaSettingsQuery(query: []const u8) !?[]const u8 {
    const allocator = std.heap.page_allocator;

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "nvidia-settings", "-q", query },
    }) catch return null;
    defer allocator.free(result.stderr);

    if (result.term != .Exited or result.term.Exited != 0) {
        allocator.free(result.stdout);
        return null;
    }

    return if (result.stdout.len > 0) result.stdout else null;
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

/// Get G-Sync state for a display
pub fn getState(display_name: []const u8) !GsyncState {
    _ = display_name;

    // Query G-Sync status via nvidia-settings
    var state = GsyncState{
        .mode = .disabled,
        .enabled = false,
        .min_refresh_hz = 0,
        .max_refresh_hz = 0,
        .current_refresh_hz = 0,
        .lfc_supported = false,
        .lfc_active = false,
        .pulsar_supported = false,
        .pulsar_active = false,
    };

    // Check if G-Sync is enabled
    if (runNvidiaSettingsQuery("AllowGSYNC")) |output| {
        defer std.heap.page_allocator.free(output);
        if (std.mem.indexOf(u8, output, "1")) |_| {
            state.enabled = true;
            state.mode = .native;
        }
    } else |_| {}

    // Check G-Sync Compatible mode
    if (runNvidiaSettingsQuery("AllowGSYNCCompatible")) |output| {
        defer std.heap.page_allocator.free(output);
        if (std.mem.indexOf(u8, output, "1")) |_| {
            if (state.mode == .disabled) {
                state.mode = .compatible;
            }
            state.enabled = true;
        }
    } else |_| {}

    return state;
}

/// Enable G-Sync on a display
pub fn enable(display_name: []const u8) !void {
    _ = display_name;
    try runNvidiaSettingsAssign("AllowGSYNC=1");
    try runNvidiaSettingsAssign("AllowGSYNCCompatible=1");
}

/// Disable G-Sync on a display
pub fn disable(display_name: []const u8) !void {
    _ = display_name;
    try runNvidiaSettingsAssign("AllowGSYNC=0");
}

/// G-Sync configuration options
pub const GsyncConfig = struct {
    /// Enable G-Sync
    enabled: bool = true,
    /// Enable on windowed mode (not just fullscreen)
    windowed_mode: bool = true,
    /// Allow G-Sync Compatible monitors
    allow_compatible: bool = true,
    /// Enable indicator overlay
    show_indicator: bool = false,
};

/// Apply G-Sync configuration
pub fn configure(display_name: []const u8, config: GsyncConfig) !void {
    _ = display_name;

    // Set main G-Sync toggle
    if (config.enabled) {
        try runNvidiaSettingsAssign("AllowGSYNC=1");
    } else {
        try runNvidiaSettingsAssign("AllowGSYNC=0");
    }

    // Set G-Sync Compatible (Adaptive Sync) support
    if (config.allow_compatible) {
        try runNvidiaSettingsAssign("AllowGSYNCCompatible=1");
    } else {
        try runNvidiaSettingsAssign("AllowGSYNCCompatible=0");
    }

    // Set G-Sync indicator
    if (config.show_indicator) {
        try runNvidiaSettingsAssign("ShowGSYNCIndicator=1");
    } else {
        try runNvidiaSettingsAssign("ShowGSYNCIndicator=0");
    }

    // Note: Windowed G-Sync is typically enabled via:
    // nvidia-settings -a AllowGSYNCVisualIndicator=1 (for windowed apps)
    // This may require additional X11 configuration
}

/// Set VRR range (if monitor supports custom ranges)
pub fn setVrrRange(display_name: []const u8, min_hz: u32, max_hz: u32) !void {
    _ = display_name;
    _ = min_hz;
    _ = max_hz;
    // Most monitors don't support custom VRR ranges
    // Some high-end models allow override via OSD or driver
    return error.NotSupported;
}

/// Check if display is G-Sync validated
/// A validated display has been tested by NVIDIA for G-Sync Compatible certification
pub fn isValidated(display_name: []const u8) !bool {
    // Query nvidia-settings for G-Sync validation status
    // Validated monitors report as "G-Sync Compatible (Validated)" vs just "Compatible"
    const allocator = std.heap.page_allocator;

    // Build query for specific display
    var query_buf: [128]u8 = undefined;
    const query = std.fmt.bufPrint(&query_buf, "[{s}]/GsyncCompatible", .{display_name}) catch {
        // Fallback to global query
        return isValidatedGlobal();
    };

    if (runNvidiaSettingsQuery(query)) |output| {
        defer allocator.free(output);
        // Validated monitors show specific attributes
        // Check for validation indicators in output
        if (std.mem.indexOf(u8, output, "validated") != null or
            std.mem.indexOf(u8, output, "Validated") != null)
        {
            return true;
        }
        // Native G-Sync monitors are always "validated" by definition
        if (std.mem.indexOf(u8, output, "G-SYNC") != null and
            std.mem.indexOf(u8, output, "Compatible") == null)
        {
            return true;
        }
        return false;
    } else |_| {}

    return isValidatedGlobal();
}

fn isValidatedGlobal() bool {
    // Check global AllowGSYNC attribute - native G-Sync is always validated
    if (runNvidiaSettingsQuery("AllowGSYNC")) |output| {
        defer std.heap.page_allocator.free(output);
        // If AllowGSYNC reports native (not compatible), it's validated
        if (std.mem.indexOf(u8, output, "native") != null or
            std.mem.indexOf(u8, output, "Native") != null)
        {
            return true;
        }
    } else |_| {}
    return false;
}

/// G-Sync indicator mode
pub const IndicatorMode = enum {
    off,
    on_when_active,
    always,
};

/// Set G-Sync indicator
pub fn setIndicator(mode: IndicatorMode) !void {
    switch (mode) {
        .off => try runNvidiaSettingsAssign("ShowGSYNCIndicator=0"),
        .on_when_active, .always => try runNvidiaSettingsAssign("ShowGSYNCIndicator=1"),
    }
}

/// G-Sync pendulum test info
pub const PendulumTest = struct {
    running: bool,
    fps: u32,
    vrr_active: bool,
    tearing_detected: bool,
};

/// Run G-Sync pendulum demo/test
pub fn runPendulumTest() !PendulumTest {
    // The pendulum demo is a separate application
    // nvidia-settings has it built in
    return error.NotSupported;
}

test "gsync mode" {
    const mode = GsyncMode.ultimate;
    try std.testing.expect(mode.supportsHdr());

    const compat = GsyncMode.compatible;
    try std.testing.expect(!compat.supportsHdr());
}
