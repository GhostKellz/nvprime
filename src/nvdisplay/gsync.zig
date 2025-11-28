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

/// Get G-Sync state for a display
pub fn getState(display_name: []const u8) !GsyncState {
    _ = display_name;
    // TODO: Query via nvidia-settings or NVAPI
    // nvidia-settings -q CurrentMetaMode
    // nvidia-settings -q AllowGSYNCCompatible
    return error.NotSupported;
}

/// Enable G-Sync on a display
pub fn enable(display_name: []const u8) !void {
    _ = display_name;
    // TODO: nvidia-settings or NVAPI
    return error.NotSupported;
}

/// Disable G-Sync on a display
pub fn disable(display_name: []const u8) !void {
    _ = display_name;
    // TODO: nvidia-settings or NVAPI
    return error.NotSupported;
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
    _ = config;
    // TODO: Apply via nvidia-settings
    // nvidia-settings -a AllowGSYNC=1
    // nvidia-settings -a AllowGSYNCCompatible=1
    return error.NotSupported;
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
pub fn isValidated(display_name: []const u8) !bool {
    _ = display_name;
    // TODO: Check against NVIDIA's validated display list
    // Could fetch from: https://www.nvidia.com/en-us/geforce/products/g-sync-monitors/specs/
    return error.NotSupported;
}

/// G-Sync indicator mode
pub const IndicatorMode = enum {
    off,
    on_when_active,
    always,
};

/// Set G-Sync indicator
pub fn setIndicator(mode: IndicatorMode) !void {
    _ = mode;
    // nvidia-settings -a ShowGSyncIndicator=1
    return error.NotSupported;
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
