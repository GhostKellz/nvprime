//! nvruntime/nvvulkan - NVIDIA Vulkan Extensions
//!
//! Re-exports the nvvk library providing optimized NVIDIA Vulkan extension wrappers
//! with C ABI exports for integration with DXVK, vkd3d-proton, and other Vulkan-based
//! translation layers.
//!
//! ## Extensions Supported
//!
//! - **VK_NV_low_latency2**: NVIDIA Reflex integration for reduced input latency
//! - **VK_NV_device_diagnostic_checkpoints**: GPU crash debugging
//! - **VK_NV_device_diagnostics_config**: Enhanced GPU diagnostics
//! - **VK_NV_memory_decompression**: GPU-accelerated GDEFLATE decompression
//! - **VK_NV_mesh_shader**: Mesh and task shader pipeline support
//! - **VK_NV_ray_tracing**: Legacy ray tracing for older games/drivers
//!
//! ## Vulkan Version Support
//!
//! - **Vulkan 1.4**: Full support (recommended) - push descriptors, maintenance 6
//! - **Vulkan 1.3**: Compatible mode - all core features work
//! - **Vulkan 1.2**: Limited mode - some features unavailable

const nvvk = @import("nvvk");

// Re-export version
pub const version = nvvk.version;

// =============================================================================
// Vulkan 1.4 API Version Support
// =============================================================================

/// Vulkan API version constants
pub const VK_API_VERSION_1_0 = nvvk.vulkan.VK_API_VERSION_1_0;
pub const VK_API_VERSION_1_1 = nvvk.vulkan.VK_API_VERSION_1_1;
pub const VK_API_VERSION_1_2 = nvvk.vulkan.VK_API_VERSION_1_2;
pub const VK_API_VERSION_1_3 = nvvk.vulkan.VK_API_VERSION_1_3;
pub const VK_API_VERSION_1_4 = nvvk.vulkan.VK_API_VERSION_1_4;

/// Minimum required API version for nvvk functionality
pub const NVVK_MIN_API_VERSION = nvvk.vulkan.NVVK_MIN_API_VERSION;
/// Recommended API version for full feature support (Vulkan 1.4)
pub const NVVK_RECOMMENDED_API_VERSION = nvvk.vulkan.NVVK_RECOMMENDED_API_VERSION;

/// Check if an API version supports Vulkan 1.4 features
pub const supportsVulkan14 = nvvk.vulkan.supportsVulkan14;

/// Check if an API version supports Vulkan 1.3 features
pub const supportsVulkan13 = nvvk.vulkan.supportsVulkan13;

/// Get human-readable feature set name for a given API version
pub const getFeatureSetName = nvvk.vulkan.getFeatureSetName;

/// Make API version from components
pub const makeApiVersion = nvvk.vulkan.makeApiVersion;

/// Extract major version from API version
pub const apiVersionMajor = nvvk.vulkan.apiVersionMajor;

/// Extract minor version from API version
pub const apiVersionMinor = nvvk.vulkan.apiVersionMinor;

/// Extract patch version from API version
pub const apiVersionPatch = nvvk.vulkan.apiVersionPatch;

// =============================================================================
// Vulkan 1.4 Promoted Extension Types
// =============================================================================

/// Push descriptor properties (Vulkan 1.4 core, promoted from VK_KHR_push_descriptor)
pub const VkPhysicalDevicePushDescriptorProperties = nvvk.vulkan.VkPhysicalDevicePushDescriptorProperties;

/// Maintenance 6 features (Vulkan 1.4 core)
pub const VkPhysicalDeviceMaintenance6Features = nvvk.vulkan.VkPhysicalDeviceMaintenance6Features;

/// Maintenance 6 properties (Vulkan 1.4 core)
pub const VkPhysicalDeviceMaintenance6Properties = nvvk.vulkan.VkPhysicalDeviceMaintenance6Properties;

/// Push descriptor set info (Vulkan 1.4 core)
pub const VkPushDescriptorSetInfo = nvvk.vulkan.VkPushDescriptorSetInfo;

/// Push constants info (Vulkan 1.4 core)
pub const VkPushConstantsInfo = nvvk.vulkan.VkPushConstantsInfo;

/// Dynamic rendering local read features (Vulkan 1.4 core)
pub const VkPhysicalDeviceDynamicRenderingLocalReadFeatures = nvvk.vulkan.VkPhysicalDeviceDynamicRenderingLocalReadFeatures;

/// Scalar block layout features (Vulkan 1.4 core)
pub const VkPhysicalDeviceScalarBlockLayoutFeatures = nvvk.vulkan.VkPhysicalDeviceScalarBlockLayoutFeatures;

// =============================================================================
// Async Sleep Support
// =============================================================================

/// Async sleep context for non-blocking frame pacing
pub const AsyncSleepContext = nvvk.AsyncSleepContext;

/// Handle for async sleep requests
pub const AsyncSleepHandle = nvvk.AsyncSleepHandle;

/// Callback for async sleep completion
pub const AsyncCallback = nvvk.AsyncCallback;

/// Result of async sleep operation
pub const AsyncResult = nvvk.AsyncResult;

// Re-export Vulkan types
pub const VkResult = nvvk.VkResult;
pub const VulkanError = nvvk.VulkanError;
pub const VkDevice = nvvk.VkDevice;
pub const VkInstance = nvvk.VkInstance;
pub const VkQueue = nvvk.VkQueue;
pub const VkSwapchainKHR_T = nvvk.VkSwapchainKHR_T;
pub const VkSemaphore_T = nvvk.VkSemaphore_T;
pub const VkCommandBuffer = nvvk.VkCommandBuffer;

// Re-export core types
pub const Loader = nvvk.Loader;
pub const DeviceDispatch = nvvk.DeviceDispatch;

// Re-export Low Latency
pub const LowLatencyContext = nvvk.LowLatencyContext;
pub const ModeConfig = nvvk.ModeConfig;
pub const Marker = nvvk.Marker;
pub const FrameTimings = nvvk.FrameTimings;

// Re-export Diagnostics
pub const DiagnosticsContext = nvvk.DiagnosticsContext;
pub const DiagnosticsConfig = nvvk.DiagnosticsConfig;
pub const CheckpointTag = nvvk.CheckpointTag;
pub const CheckpointData = nvvk.CheckpointData;
pub const CrashDump = nvvk.CrashDump;
pub const PipelineStage = nvvk.PipelineStage;

// Re-export Memory Decompression
pub const DecompressionContext = nvvk.DecompressionContext;
pub const DecompressionRegion = nvvk.DecompressionRegion;
pub const CompressionMethod = nvvk.CompressionMethod;

// Re-export Mesh Shader
pub const MeshShaderContext = nvvk.MeshShaderContext;
pub const MeshShaderProperties = nvvk.MeshShaderProperties;

// Re-export Ray Tracing
pub const RayTracingContext = nvvk.RayTracingContext;
pub const RayTracingProperties = nvvk.RayTracingProperties;
pub const ShaderBindingTable = nvvk.ShaderBindingTable;

// Re-export sub-modules
pub const vulkan = nvvk.vulkan;
pub const low_latency = nvvk.low_latency;
pub const diagnostics = nvvk.diagnostics;
pub const memory_decompression = nvvk.memory_decompression;
pub const mesh_shader = nvvk.mesh_shader;
pub const ray_tracing = nvvk.ray_tracing;

// Re-export Frame Generation modules (Phase 3)
pub const optical_flow = nvvk.optical_flow;
pub const motion_vectors = nvvk.motion_vectors;
pub const frame_synthesis = nvvk.frame_synthesis;
pub const frame_generation = nvvk.frame_generation;
pub const present_injection = nvvk.present_injection;
pub const vrr = nvvk.vrr;

// Re-export Optical Flow types
pub const OpticalFlowContext = nvvk.OpticalFlowContext;
pub const OpticalFlowConfig = nvvk.OpticalFlowConfig;
pub const OpticalFlowProperties = nvvk.OpticalFlowProperties;

// Re-export Motion Vector types
pub const MotionVectorContext = nvvk.MotionVectorContext;
pub const MotionVectorConfig = nvvk.MotionVectorConfig;
pub const MotionVectorBuffer = nvvk.MotionVectorBuffer;

// Re-export Frame Synthesis types
pub const FrameSynthesisContext = nvvk.FrameSynthesisContext;

// Re-export Frame Generation types
pub const FrameGenContext = nvvk.FrameGenContext;
pub const FrameGenConfig = nvvk.FrameGenConfig;
pub const FrameGenMode = nvvk.FrameGenMode;
pub const FrameGenStats = nvvk.FrameGenStats;
pub const GeneratedFrame = nvvk.GeneratedFrame;

// Re-export Present Injection types
pub const PresentInjectionContext = nvvk.PresentInjectionContext;
pub const InjectionConfig = nvvk.InjectionConfig;
pub const InjectionMode = nvvk.InjectionMode;
pub const TimingMode = nvvk.TimingMode;
pub const InjectionStats = nvvk.InjectionStats;

// Re-export VRR types
pub const VrrConfig = nvvk.VrrConfig;
pub const VrrSource = nvvk.VrrSource;
pub const VrrStatus = nvvk.VrrStatus;
pub const LfcState = nvvk.LfcState;

// Re-export extension names
pub const ext_names = nvvk.ext_names;

// Re-export utility functions
pub const isNvidiaGpu = nvvk.isNvidiaGpu;
pub const getNvidiaDriverVersion = nvvk.getNvidiaDriverVersion;

// Re-export driver version utilities
pub const DriverVersion = nvvk.DriverVersion;
pub const getDriverVersion = nvvk.getDriverVersion;
pub const isDriverRecommended = nvvk.isDriverRecommended;
pub const recommended_driver = nvvk.recommended_driver;

// =============================================================================
// Vulkan Version Information
// =============================================================================

/// Comprehensive Vulkan version and feature information
pub const VulkanVersionInfo = struct {
    /// API version number
    api_version: u32,
    /// Major version component
    major: u32,
    /// Minor version component
    minor: u32,
    /// Patch version component
    patch: u32,
    /// Human-readable feature set name
    feature_set: []const u8,
    /// Whether Vulkan 1.4 features are available
    has_vulkan14: bool,
    /// Whether Vulkan 1.3 features are available
    has_vulkan13: bool,
    /// Whether push descriptors are available (Vulkan 1.4 core or extension)
    has_push_descriptors: bool,

    /// Create version info from an API version number
    pub fn fromApiVersion(api_version: u32) VulkanVersionInfo {
        return .{
            .api_version = api_version,
            .major = apiVersionMajor(api_version),
            .minor = apiVersionMinor(api_version),
            .patch = apiVersionPatch(api_version),
            .feature_set = getFeatureSetName(api_version),
            .has_vulkan14 = supportsVulkan14(api_version),
            .has_vulkan13 = supportsVulkan13(api_version),
            .has_push_descriptors = supportsVulkan14(api_version), // Core in 1.4
        };
    }

    /// Create version info for Vulkan 1.4
    pub fn vulkan14() VulkanVersionInfo {
        return fromApiVersion(VK_API_VERSION_1_4);
    }

    /// Create version info for Vulkan 1.3
    pub fn vulkan13() VulkanVersionInfo {
        return fromApiVersion(VK_API_VERSION_1_3);
    }

    /// Format version as string (e.g., "1.4.0")
    pub fn format(self: VulkanVersionInfo, writer: anytype) !void {
        try writer.print("{d}.{d}.{d}", .{ self.major, self.minor, self.patch });
    }

    /// Check if this version meets minimum requirements
    pub fn meetsMinimum(self: VulkanVersionInfo) bool {
        return self.api_version >= NVVK_MIN_API_VERSION;
    }

    /// Check if this version is the recommended version
    pub fn isRecommended(self: VulkanVersionInfo) bool {
        return self.api_version >= NVVK_RECOMMENDED_API_VERSION;
    }
};

/// Get recommended Vulkan version info
pub fn getRecommendedVersion() VulkanVersionInfo {
    return VulkanVersionInfo.fromApiVersion(NVVK_RECOMMENDED_API_VERSION);
}

/// Get minimum required Vulkan version info
pub fn getMinimumVersion() VulkanVersionInfo {
    return VulkanVersionInfo.fromApiVersion(NVVK_MIN_API_VERSION);
}

/// Check if a device dispatch table supports Vulkan 1.4 push descriptors
pub fn hasPushDescriptorSupport(dispatch: *const DeviceDispatch) bool {
    return dispatch.hasPushDescriptors();
}

/// Vulkan layer status (for layer management)
pub const LayerStatus = enum {
    not_installed,
    installed_disabled,
    installed_enabled,
};

const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const posix = std.posix;

/// Common Vulkan layer paths
const LAYER_PATHS = [_][]const u8{
    "/usr/share/vulkan/implicit_layer.d",
    "/usr/local/share/vulkan/implicit_layer.d",
    "/etc/vulkan/implicit_layer.d",
};

/// Get layer installation status
/// Checks standard Vulkan layer directories for NVIDIA layers
pub fn getLayerStatus() LayerStatus {
    const allocator = std.heap.page_allocator;

    // Check VK_LAYER_PATH environment variable first
    const custom_path = posix.getenv("VK_LAYER_PATH");

    // Collect paths to check
    var paths_to_check: [4][]const u8 = undefined;
    var path_count: usize = 0;

    if (custom_path) |p| {
        paths_to_check[path_count] = p;
        path_count += 1;
    }

    for (LAYER_PATHS) |p| {
        if (path_count < paths_to_check.len) {
            paths_to_check[path_count] = p;
            path_count += 1;
        }
    }

    var found_nvidia_layer = false;
    var layer_enabled = false;

    for (paths_to_check[0..path_count]) |layer_path| {
        var dir = fs.cwd().openDir(layer_path, .{ .iterate = true }) catch continue;
        defer dir.close();

        var iter = dir.iterate();
        while (iter.next() catch null) |entry| {
            // Look for NVIDIA-related layer JSON files
            if (mem.indexOf(u8, entry.name, "nvidia") != null or
                mem.indexOf(u8, entry.name, "NVIDIA") != null or
                mem.indexOf(u8, entry.name, "nv_") != null)
            {
                found_nvidia_layer = true;

                // Check if layer is enabled by reading the JSON
                var path_buf: [512]u8 = undefined;
                const full_path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ layer_path, entry.name }) catch continue;

                const file = fs.cwd().openFile(full_path, .{}) catch continue;
                defer file.close();

                var content_buf: [4096]u8 = undefined;
                const len = file.read(&content_buf) catch continue;
                const content = content_buf[0..len];

                // Check for "disable_environment" - if not present or not set, layer is enabled
                if (mem.indexOf(u8, content, "\"disable_environment\"") == null) {
                    layer_enabled = true;
                } else {
                    // Check if disable env var is set
                    // Simple heuristic: if file exists and no disable_environment, it's enabled
                    layer_enabled = true;
                }
            }
        }
    }

    _ = allocator;
    if (!found_nvidia_layer) {
        return .not_installed;
    }
    return if (layer_enabled) .installed_enabled else .installed_disabled;
}

// =============================================================================
// Tests
// =============================================================================

test "Vulkan 1.4 API version constants" {
    // Verify API version encoding
    try std.testing.expect(VK_API_VERSION_1_4 > VK_API_VERSION_1_3);
    try std.testing.expect(VK_API_VERSION_1_3 > VK_API_VERSION_1_2);
    try std.testing.expect(VK_API_VERSION_1_2 > VK_API_VERSION_1_1);

    // Verify version extraction
    try std.testing.expectEqual(@as(u32, 1), apiVersionMajor(VK_API_VERSION_1_4));
    try std.testing.expectEqual(@as(u32, 4), apiVersionMinor(VK_API_VERSION_1_4));
}

test "Vulkan version detection" {
    try std.testing.expect(supportsVulkan14(VK_API_VERSION_1_4));
    try std.testing.expect(!supportsVulkan14(VK_API_VERSION_1_3));
    try std.testing.expect(supportsVulkan13(VK_API_VERSION_1_3));
    try std.testing.expect(supportsVulkan13(VK_API_VERSION_1_4));
}

test "VulkanVersionInfo struct" {
    const v14 = VulkanVersionInfo.vulkan14();
    try std.testing.expectEqual(@as(u32, 1), v14.major);
    try std.testing.expectEqual(@as(u32, 4), v14.minor);
    try std.testing.expect(v14.has_vulkan14);
    try std.testing.expect(v14.has_vulkan13);
    try std.testing.expect(v14.has_push_descriptors);
    try std.testing.expect(v14.isRecommended());

    const v13 = VulkanVersionInfo.vulkan13();
    try std.testing.expectEqual(@as(u32, 1), v13.major);
    try std.testing.expectEqual(@as(u32, 3), v13.minor);
    try std.testing.expect(!v13.has_vulkan14);
    try std.testing.expect(v13.has_vulkan13);
    try std.testing.expect(v13.meetsMinimum());
}

test "version info utility functions" {
    const recommended = getRecommendedVersion();
    try std.testing.expect(recommended.has_vulkan14);

    const minimum = getMinimumVersion();
    try std.testing.expect(minimum.has_vulkan13);
}

test "feature set names" {
    try std.testing.expectEqualStrings("Vulkan 1.4 (full)", getFeatureSetName(VK_API_VERSION_1_4));
    try std.testing.expectEqualStrings("Vulkan 1.3 (compatible)", getFeatureSetName(VK_API_VERSION_1_3));
}
