//! nvdisplay/vrr - Variable Refresh Rate Control
//!
//! Generic VRR control (FreeSync, Adaptive Sync) beyond G-Sync specific features.

const std = @import("std");

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

    pub fn range(self: VrrState) u32 {
        return self.max_hz - self.min_hz;
    }

    pub fn inVrrRange(self: VrrState, fps: u32) bool {
        return fps >= self.min_hz and fps <= self.max_hz;
    }

    pub fn lfcThreshold(self: VrrState) u32 {
        return self.min_hz;
    }
};

/// Get VRR state for a display
pub fn getState(display_name: []const u8) !VrrState {
    _ = display_name;
    // TODO: Query via libdrm or nvidia-settings
    return error.NotSupported;
}

/// Enable VRR on a display
pub fn enable(display_name: []const u8) !void {
    _ = display_name;
    // TODO: Implement
    return error.NotSupported;
}

/// Disable VRR on a display
pub fn disable(display_name: []const u8) !void {
    _ = display_name;
    return error.NotSupported;
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
pub fn setMode(display_name: []const u8, mode: VrrMode) !void {
    _ = display_name;
    _ = mode;
    return error.NotSupported;
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
pub fn getFrameTiming(display_name: []const u8) !FrameTiming {
    _ = display_name;
    return error.NotSupported;
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

/// Get VRR statistics
pub fn getStats(display_name: []const u8) !VrrStats {
    _ = display_name;
    return error.NotSupported;
}

/// Reset VRR statistics
pub fn resetStats(display_name: []const u8) !void {
    _ = display_name;
    return error.NotSupported;
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
    };
    try std.testing.expectEqual(@as(u32, 96), state.range());
    try std.testing.expect(state.inVrrRange(100));
    try std.testing.expect(!state.inVrrRange(30));
}
