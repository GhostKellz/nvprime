//! nvhud - Overlay & Telemetry System
//!
//! In-game overlay, performance metrics, and telemetry logging.
//! Phase 9 implementation - currently stubbed.

const std = @import("std");

pub const version = "0.1.0-dev";

/// HUD visibility state
pub const HudState = enum {
    hidden,
    minimal, // FPS only
    compact, // FPS + basic stats
    full, // All metrics
    custom, // User-defined layout
};

/// Get current HUD state
pub fn getState() HudState {
    return .hidden;
}

/// Toggle HUD visibility
pub fn toggle() void {
    // TODO: Implement
}

/// Metrics snapshot
pub const Metrics = struct {
    fps: f32,
    frametime_ms: f32,
    frametime_1_percent: f32,
    frametime_0_1_percent: f32,
    gpu_usage: u32,
    gpu_temp: u32,
    gpu_clock: u32,
    mem_usage: u32,
    mem_clock: u32,
    cpu_usage: u32,
    ram_usage: u32,
    latency_ms: f32,
};

/// Get current metrics
pub fn getMetrics() Metrics {
    return Metrics{
        .fps = 0,
        .frametime_ms = 0,
        .frametime_1_percent = 0,
        .frametime_0_1_percent = 0,
        .gpu_usage = 0,
        .gpu_temp = 0,
        .gpu_clock = 0,
        .mem_usage = 0,
        .mem_clock = 0,
        .cpu_usage = 0,
        .ram_usage = 0,
        .latency_ms = 0,
    };
}

test "nvhud stub" {
    try std.testing.expectEqual(HudState.hidden, getState());
}
