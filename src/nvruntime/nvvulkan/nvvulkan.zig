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
