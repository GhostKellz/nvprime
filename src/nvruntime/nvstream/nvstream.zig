//! nvruntime/nvstream - Low-Latency Game Streaming
//!
//! NVENC-based game streaming with Moonlight compatibility.
//! Phase 8 implementation - currently stubbed.

const std = @import("std");

pub const version = "0.1.0-dev";

/// Stream state
pub const StreamState = enum {
    idle,
    streaming,
    paused,
    error_state,
};

pub fn getState() StreamState {
    return .idle;
}

/// Streaming quality preset
pub const QualityPreset = enum {
    low_latency, // Lowest latency, lower quality
    balanced, // Balance of latency and quality
    high_quality, // Higher quality, more latency
};

test "nvstream stub" {
    try std.testing.expectEqual(StreamState.idle, getState());
}
