//! NVPrime C API
//!
//! Root module for C ABI exports. This aggregates all subsystem C APIs.

pub const nvcaps_capi = @import("nvcaps_capi.zig");
pub const nvcore_capi = @import("nvcore_capi.zig");
pub const nvpower_capi = @import("nvpower_capi.zig");
pub const nvdisplay_capi = @import("nvdisplay_capi.zig");
pub const nvdlss_capi = @import("nvdlss_capi.zig");
pub const nvruntime_capi = @import("nvruntime_capi.zig");

// Re-export types - nvcaps
pub const NvArchitecture = nvcaps_capi.NvArchitecture;
pub const NvGpuCapabilities = nvcaps_capi.NvGpuCapabilities;
pub const NvSystemSummary = nvcaps_capi.NvSystemSummary;

// Re-export types - nvcore
pub const NvPerformanceProfile = nvcore_capi.NvPerformanceProfile;
pub const NvCoreState = nvcore_capi.NvCoreState;
pub const NvClockLimits = nvcore_capi.NvClockLimits;

// Re-export types - nvpower
pub const NvFanMode = nvpower_capi.NvFanMode;
pub const NvPowerHealth = nvpower_capi.NvPowerHealth;
pub const NvEfficiencyMode = nvpower_capi.NvEfficiencyMode;
pub const NvPowerState = nvpower_capi.NvPowerState;

// Re-export types - nvdisplay
pub const NvVrrType = nvdisplay_capi.NvVrrType;
pub const NvConnectionType = nvdisplay_capi.NvConnectionType;
pub const NvDisplayInfo = nvdisplay_capi.NvDisplayInfo;
pub const NvVrrState = nvdisplay_capi.NvVrrState;
pub const NvDisplayConfig = nvdisplay_capi.NvDisplayConfig;

// Re-export types - nvdlss
pub const NvDlssQuality = nvdlss_capi.NvDlssQuality;
pub const NvDlssMode = nvdlss_capi.NvDlssMode;
pub const NvFrameGenMode = nvdlss_capi.NvFrameGenMode;
pub const NvGpuGeneration = nvdlss_capi.NvGpuGeneration;
pub const NvReflexMode = nvdlss_capi.NvReflexMode;
pub const NvDlssVersion = nvdlss_capi.NvDlssVersion;
pub const NvDlssCapabilities = nvdlss_capi.NvDlssCapabilities;
pub const NvDlssConfig = nvdlss_capi.NvDlssConfig;
pub const NvRenderResolution = nvdlss_capi.NvRenderResolution;
pub const NvDlssStats = nvdlss_capi.NvDlssStats;
pub const NvReflexStats = nvdlss_capi.NvReflexStats;

// Re-export types - nvruntime (primetime)
pub const NvCompositorState = nvruntime_capi.NvCompositorState;
pub const NvUpscaler = nvruntime_capi.NvUpscaler;
pub const NvPacingMode = nvruntime_capi.NvPacingMode;
pub const NvPresentMode = nvruntime_capi.NvPresentMode;
pub const NvOverlayPosition = nvruntime_capi.NvOverlayPosition;
pub const NvCompositorConfig = nvruntime_capi.NvCompositorConfig;
pub const NvOutputInfo = nvruntime_capi.NvOutputInfo;
pub const NvLatencyStats = nvruntime_capi.NvLatencyStats;
pub const NvPerfStats = nvruntime_capi.NvPerfStats;
pub const NvSwapchainInfo = nvruntime_capi.NvSwapchainInfo;
pub const NvCompositor = nvruntime_capi.NvCompositor;

/// Library version components
pub const NVPRIME_VERSION_MAJOR: c_int = 0;
pub const NVPRIME_VERSION_MINOR: c_int = 1;
pub const NVPRIME_VERSION_PATCH: c_int = 0;

/// Get library version string
export fn nvprime_version() [*:0]const u8 {
    return "0.1.0";
}

/// Get library version as packed integer (major * 10000 + minor * 100 + patch)
export fn nvprime_version_int() c_int {
    return NVPRIME_VERSION_MAJOR * 10000 + NVPRIME_VERSION_MINOR * 100 + NVPRIME_VERSION_PATCH;
}

// Force the linker to include the C API exports from submodules
comptime {
    // Reference entire modules to force inclusion of all exports
    _ = nvcaps_capi;
    _ = nvcore_capi;
    _ = nvpower_capi;
    _ = nvdisplay_capi;
    _ = nvdlss_capi;
    _ = nvruntime_capi;
}
