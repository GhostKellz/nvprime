//! nvhud - Overlay & Telemetry System
//!
//! Re-exports the nvhud library for in-game overlay, performance metrics,
//! and telemetry logging. This is a MangoHud alternative optimized for NVIDIA.
//!
//! Features:
//! - Direct NVML integration (no nvidia-smi subprocess)
//! - GPU-accelerated Vulkan overlay (<1% overhead)
//! - Full NVIDIA telemetry (Reflex latency, NVENC, etc.)
//! - Configurable via TOML or environment variables
//!
//! Uses Zeus for high-performance GPU text rendering.

const nvhud_lib = @import("nvhud");
const zeus_lib = @import("zeus");

// Re-export key types and functions from nvhud
pub const version = nvhud_lib.version;
pub const version_string = nvhud_lib.version_string;

// Core types
pub const GpuMetrics = nvhud_lib.GpuMetrics;
pub const GpuInfo = nvhud_lib.GpuInfo;
pub const FrameMetrics = nvhud_lib.FrameMetrics;
pub const FrameTimeBuffer = nvhud_lib.FrameTimeBuffer;
pub const Collector = nvhud_lib.Collector;
pub const Config = nvhud_lib.Config;
pub const Position = nvhud_lib.Position;
pub const Color = nvhud_lib.Color;
pub const Overlay = nvhud_lib.Overlay;
pub const RenderCommand = nvhud_lib.RenderCommand;

// Sub-modules
pub const nvml = nvhud_lib.nvml;
pub const metrics = nvhud_lib.metrics;
pub const config = nvhud_lib.config;
pub const overlay = nvhud_lib.overlay;

// Functions
pub const isNvidiaAvailable = nvhud_lib.isNvidiaAvailable;
pub const createCollector = nvhud_lib.createCollector;
pub const createOverlay = nvhud_lib.createOverlay;
pub const createOverlayWithConfig = nvhud_lib.createOverlayWithConfig;
pub const loadConfig = nvhud_lib.loadConfig;
pub const isOverlayEnabled = nvhud_lib.isOverlayEnabled;
pub const getConfigFromEnv = nvhud_lib.getConfigFromEnv;

// Environment variables
pub const ENV_ENABLE = nvhud_lib.ENV_ENABLE;
pub const ENV_POSITION = nvhud_lib.ENV_POSITION;
pub const ENV_FPS = nvhud_lib.ENV_FPS;
pub const ENV_CONFIG = nvhud_lib.ENV_CONFIG;

/// Check if nvhud overlay is available and can be enabled
pub fn isOverlayAvailable() bool {
    return nvhud_lib.isNvidiaAvailable();
}

// =============================================================================
// Zeus Text Rendering Integration
// =============================================================================

/// Zeus text rendering module for GPU-accelerated overlay text
pub const text = struct {
    /// Zeus library re-export for advanced text rendering
    pub const zeus = zeus_lib;

    // Re-export key Zeus types when they're needed
    // pub const TextRenderer = zeus_lib.TextRenderer;
    // pub const Font = zeus_lib.Font;
    // pub const GlyphCache = zeus_lib.GlyphCache;
};
