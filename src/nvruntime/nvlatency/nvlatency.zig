//! nvruntime/nvlatency - NVIDIA Reflex & Frame Latency Tools
//!
//! Re-exports the nvlatency library for measuring, analyzing, and reducing
//! input-to-display latency on NVIDIA GPUs under Linux.
//!
//! ## Features
//!
//! - **Frame Latency Measurement** - Precise end-to-end latency tracking
//! - **NVIDIA Reflex Integration** - Low latency mode via VK_NV_low_latency2
//! - **Latency Visualization** - Real-time metrics and logging
//! - **Game Integration** - Automatic injection for supported games

const nvlatency_lib = @import("nvlatency");

// Re-export version
pub const version = nvlatency_lib.version;

// Re-export sub-modules
pub const timing = nvlatency_lib.timing;
pub const metrics = nvlatency_lib.metrics;
pub const reflex = nvlatency_lib.reflex;

// Re-export key types
pub const LatencyContext = nvlatency_lib.LatencyContext;
pub const ReflexMode = nvlatency_lib.ReflexMode;
pub const LatencyMetrics = nvlatency_lib.LatencyMetrics;
pub const FrameTimings = nvlatency_lib.FrameTimings;
pub const Timer = nvlatency_lib.Timer;

// Re-export utility functions
pub const isNvidiaGpu = nvlatency_lib.isNvidiaGpu;
pub const getNvidiaDriverVersion = nvlatency_lib.getNvidiaDriverVersion;
pub const required_extensions = nvlatency_lib.required_extensions;

/// Latency reduction mode presets
pub const LatencyPreset = enum {
    /// Default - no special latency reduction
    default,
    /// Balanced - Reflex enabled without boost
    balanced,
    /// Ultra - Reflex with boost, aggressive settings
    ultra,
    /// Competitive - Maximum latency reduction for esports
    competitive,

    pub fn getReflexMode(self: LatencyPreset) nvlatency_lib.ReflexMode {
        return switch (self) {
            .default => .off,
            .balanced => .on,
            .ultra => .boost,
            .competitive => .boost,
        };
    }

    pub fn description(self: LatencyPreset) []const u8 {
        return switch (self) {
            .default => "Default (no Reflex)",
            .balanced => "Balanced (Reflex on)",
            .ultra => "Ultra (Reflex + Boost)",
            .competitive => "Competitive (maximum latency reduction)",
        };
    }
};
