//! NVPrime C API
//!
//! Root module for C ABI exports. This aggregates all subsystem C APIs.

pub const nvcaps_capi = @import("nvcaps_capi.zig");
pub const nvcore_capi = @import("nvcore_capi.zig");
pub const nvpower_capi = @import("nvpower_capi.zig");

// Re-export types
pub const NvArchitecture = nvcaps_capi.NvArchitecture;
pub const NvGpuCapabilities = nvcaps_capi.NvGpuCapabilities;
pub const NvSystemSummary = nvcaps_capi.NvSystemSummary;
pub const NvPerformanceProfile = nvcore_capi.NvPerformanceProfile;
pub const NvCoreState = nvcore_capi.NvCoreState;
pub const NvClockLimits = nvcore_capi.NvClockLimits;
pub const NvFanMode = nvpower_capi.NvFanMode;
pub const NvPowerHealth = nvpower_capi.NvPowerHealth;
pub const NvEfficiencyMode = nvpower_capi.NvEfficiencyMode;
pub const NvPowerState = nvpower_capi.NvPowerState;

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
}
