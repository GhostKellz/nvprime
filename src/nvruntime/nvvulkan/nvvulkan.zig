//! nvruntime/nvvulkan - NVIDIA Vulkan Extensions
//!
//! Vulkan layer framework and VK_NV_low_latency2 integration.
//! Phase 5 implementation - currently stubbed.

const std = @import("std");

pub const version = "0.1.0-dev";

/// Vulkan layer status
pub const LayerStatus = enum {
    not_installed,
    installed_disabled,
    installed_enabled,
};

/// Get layer status
pub fn getLayerStatus() LayerStatus {
    return .not_installed;
}

/// Low latency mode
pub const LowLatencyMode = enum {
    disabled,
    enabled,
    boost, // Enabled with boost

    pub fn description(self: LowLatencyMode) []const u8 {
        return switch (self) {
            .disabled => "Low latency disabled",
            .enabled => "Low latency enabled",
            .boost => "Low latency with boost",
        };
    }
};

test "nvvulkan stub" {
    try std.testing.expectEqual(LayerStatus.not_installed, getLayerStatus());
}
