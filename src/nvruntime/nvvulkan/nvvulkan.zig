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

const nvvk = @import("nvvk");

// Re-export version
pub const version = nvvk.version;

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

// Re-export extension names
pub const ext_names = nvvk.ext_names;

// Re-export utility functions
pub const isNvidiaGpu = nvvk.isNvidiaGpu;
pub const getNvidiaDriverVersion = nvvk.getNvidiaDriverVersion;

/// Vulkan layer status (for layer management)
pub const LayerStatus = enum {
    not_installed,
    installed_disabled,
    installed_enabled,
};

/// Get layer installation status
pub fn getLayerStatus() LayerStatus {
    // TODO: Check /usr/share/vulkan/implicit_layer.d/ or equivalent
    return .not_installed;
}
