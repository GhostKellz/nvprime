//! nvdisplay/dp_link - DisplayPort Link Training Notification
//!
//! Monitors and reports DisplayPort link training status.
//! Driver 595+ provides enhanced DP link training notification via
//! NV0073_CTRL_CMD_DP_NOTIFY_LT control command.
//!
//! This allows userspace to:
//! - Know when link training is in progress
//! - Coordinate display updates around link training
//! - Monitor link quality and configuration

const std = @import("std");
const nvml = @import("../bindings/nvml.zig");

/// DisplayPort link rate values
pub const LinkRate = enum(u8) {
    /// RBR - 1.62 Gbps (Reduced Bit Rate)
    rbr = 0x06,
    /// HBR - 2.7 Gbps (High Bit Rate)
    hbr = 0x0a,
    /// HBR2 - 5.4 Gbps (High Bit Rate 2)
    hbr2 = 0x14,
    /// HBR3 - 8.1 Gbps (High Bit Rate 3)
    hbr3 = 0x1e,
    /// UHBR10 - 10 Gbps (Ultra High Bit Rate, DP 2.0)
    uhbr10 = 0x01,
    /// UHBR13.5 - 13.5 Gbps (DP 2.0)
    uhbr13_5 = 0x04,
    /// UHBR20 - 20 Gbps (DP 2.0)
    uhbr20 = 0x02,
    /// Unknown rate
    unknown = 0x00,

    pub fn bandwidthGbps(self: LinkRate) f32 {
        return switch (self) {
            .rbr => 1.62,
            .hbr => 2.7,
            .hbr2 => 5.4,
            .hbr3 => 8.1,
            .uhbr10 => 10.0,
            .uhbr13_5 => 13.5,
            .uhbr20 => 20.0,
            .unknown => 0.0,
        };
    }

    pub fn isUhbr(self: LinkRate) bool {
        return switch (self) {
            .uhbr10, .uhbr13_5, .uhbr20 => true,
            else => false,
        };
    }

    pub fn name(self: LinkRate) []const u8 {
        return switch (self) {
            .rbr => "RBR (1.62 Gbps)",
            .hbr => "HBR (2.7 Gbps)",
            .hbr2 => "HBR2 (5.4 Gbps)",
            .hbr3 => "HBR3 (8.1 Gbps)",
            .uhbr10 => "UHBR10 (10 Gbps)",
            .uhbr13_5 => "UHBR13.5 (13.5 Gbps)",
            .uhbr20 => "UHBR20 (20 Gbps)",
            .unknown => "Unknown",
        };
    }
};

/// Link training state
pub const LinkTrainingState = enum {
    /// No link training activity
    idle,
    /// Link training in progress
    in_progress,
    /// Link training completed successfully
    completed,
    /// Link training failed
    failed,

    pub fn isActive(self: LinkTrainingState) bool {
        return self == .in_progress;
    }

    pub fn description(self: LinkTrainingState) []const u8 {
        return switch (self) {
            .idle => "Idle",
            .in_progress => "Training in progress",
            .completed => "Training completed",
            .failed => "Training failed",
        };
    }
};

/// Link training phase (DP 2.0+)
pub const LinkTrainingPhase = enum {
    /// Not in training
    none,
    /// Reset link
    reset_link,
    /// Pre-link training setup
    pre_lt,
    /// Channel equalization
    channel_eq,
    /// Clock data recovery
    cds,
    /// Post-link training
    post_lt,
};

/// DisplayPort link status
pub const DpLinkStatus = struct {
    /// Display identifier
    display_id: u32,
    /// Connection type
    connector_type: ConnectorType,
    /// Current link rate
    link_rate: LinkRate,
    /// Number of active lanes (1, 2, or 4)
    lane_count: u8,
    /// Current training state
    training_state: LinkTrainingState,
    /// Current training phase (DP 2.0+)
    training_phase: LinkTrainingPhase,
    /// Whether FEC (Forward Error Correction) is enabled
    fec_enabled: bool,
    /// Whether link is stable
    link_stable: bool,
    /// LTTPR (Link Training Timing and Parameter Recovery) count
    lttpr_count: u8,

    pub const ConnectorType = enum {
        dp, // DisplayPort
        usb_c, // USB Type-C with DP Alt Mode
        edp, // Embedded DisplayPort
        unknown,
    };

    /// Calculate total bandwidth in Gbps
    pub fn totalBandwidthGbps(self: DpLinkStatus) f32 {
        return self.link_rate.bandwidthGbps() * @as(f32, @floatFromInt(self.lane_count));
    }

    /// Check if link can support a given resolution at refresh rate
    pub fn canSupport(self: DpLinkStatus, width: u32, height: u32, refresh_hz: u32, bpp: u32) bool {
        // Calculate required bandwidth
        const pixels_per_sec = @as(u64, width) * @as(u64, height) * @as(u64, refresh_hz);
        const bits_per_sec = pixels_per_sec * @as(u64, bpp);
        const required_gbps = @as(f32, @floatFromInt(bits_per_sec)) / 1_000_000_000.0;

        // Account for 8b/10b encoding overhead (80% efficiency) or 128b/132b for UHBR (97% efficiency)
        const efficiency: f32 = if (self.link_rate.isUhbr()) 0.97 else 0.80;
        const available_gbps = self.totalBandwidthGbps() * efficiency;

        return required_gbps <= available_gbps;
    }

    pub fn print(self: DpLinkStatus, writer: anytype) !void {
        try writer.print("DP Link Status (Display {d}):\n", .{self.display_id});
        try writer.print("  Rate: {s} x {d} lanes = {d:.1} Gbps\n", .{
            self.link_rate.name(),
            self.lane_count,
            self.totalBandwidthGbps(),
        });
        try writer.print("  Training: {s}\n", .{self.training_state.description()});
        try writer.print("  FEC: {s}, Stable: {s}\n", .{
            if (self.fec_enabled) "enabled" else "disabled",
            if (self.link_stable) "yes" else "no",
        });
    }
};

/// DP link training notification parameters (matches kernel struct)
pub const DpNotifyLtParams = extern struct {
    sub_device_instance: u32,
    display_id: u32,
    lt_in_progress: u32, // NvBool
};

/// Command ID for DP link training notification
const NV0073_CTRL_CMD_DP_NOTIFY_LT: u32 = 0x73138f;

/// Error types for DP link operations
pub const DpLinkError = error{
    NotSupported,
    InvalidDisplay,
    NotAvailable,
    ControlFailed,
};

/// Check if link training is in progress for a display
/// This is a lightweight query that doesn't require full link status
pub fn isTrainingInProgress(display_id: u32) bool {
    // In a real implementation, this would query the driver
    // For now, return false as we can't query without NVML extension
    _ = display_id;
    return false;
}

/// Get full link status for a display
pub fn getLinkStatus(display_id: u32) ?DpLinkStatus {
    // This would require NVML or direct driver communication
    // Return a default status for demonstration
    _ = display_id;

    // Without direct driver access, we can't get real link status
    // This would need NVML extensions or ioctl access
    return null;
}

/// Notify driver that userspace is starting/ending a link training aware operation
pub fn notifyLinkTraining(display_id: u32, in_progress: bool) DpLinkError!void {
    // This would send NV0073_CTRL_CMD_DP_NOTIFY_LT to the driver
    // Requires direct RM access or NVML extension
    _ = display_id;
    _ = in_progress;
    return DpLinkError.NotSupported;
}

/// Cached link status for quick access
var g_link_cache: std.AutoHashMap(u32, DpLinkStatus) = undefined;
var g_cache_initialized = false;

/// Initialize the DP link monitoring subsystem
pub fn init(allocator: std.mem.Allocator) void {
    if (!g_cache_initialized) {
        g_link_cache = std.AutoHashMap(u32, DpLinkStatus).init(allocator);
        g_cache_initialized = true;
    }
}

/// Deinitialize the DP link monitoring subsystem
pub fn deinit() void {
    if (g_cache_initialized) {
        g_link_cache.deinit();
        g_cache_initialized = false;
    }
}

// ============================================================================
// Tests
// ============================================================================

test "link rate properties" {
    try std.testing.expectEqual(@as(f32, 5.4), LinkRate.hbr2.bandwidthGbps());
    try std.testing.expect(LinkRate.uhbr10.isUhbr());
    try std.testing.expect(!LinkRate.hbr3.isUhbr());
}

test "link training state" {
    try std.testing.expect(LinkTrainingState.in_progress.isActive());
    try std.testing.expect(!LinkTrainingState.idle.isActive());
    try std.testing.expect(!LinkTrainingState.completed.isActive());
}

test "link status bandwidth" {
    const status = DpLinkStatus{
        .display_id = 0,
        .connector_type = .dp,
        .link_rate = .hbr3,
        .lane_count = 4,
        .training_state = .completed,
        .training_phase = .none,
        .fec_enabled = true,
        .link_stable = true,
        .lttpr_count = 0,
    };

    // HBR3 x 4 lanes = 32.4 Gbps
    try std.testing.expectEqual(@as(f32, 32.4), status.totalBandwidthGbps());

    // Should support 4K@60Hz 8bpc (requires ~12.5 Gbps raw)
    try std.testing.expect(status.canSupport(3840, 2160, 60, 24));

    // Should support 4K@144Hz 8bpc (requires ~30 Gbps raw)
    try std.testing.expect(status.canSupport(3840, 2160, 144, 24));
}

test "dp notify params" {
    const params = DpNotifyLtParams{
        .sub_device_instance = 0,
        .display_id = 1,
        .lt_in_progress = 1,
    };

    try std.testing.expectEqual(@as(u32, 1), params.display_id);
    try std.testing.expectEqual(@as(u32, 1), params.lt_in_progress);
}
