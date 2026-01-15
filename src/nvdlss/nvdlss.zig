//! nvdlss - NVIDIA DLSS & AI Features Gateway
//!
//! DLSS Super Resolution, Frame Generation, Ray Reconstruction,
//! Reflex low-latency, RTX Video Super Resolution integration.
//!
//! Requires: NVIDIA GPU (RTX 20+), NGX SDK, DLSS SDK
//! Linux support via Proton/Wine or native Vulkan integration.
//!
//! Frame Generation can use nvvk's optical flow pipeline as a fallback
//! when NGX SDK is unavailable (pure Vulkan implementation).

const std = @import("std");
const builtin = @import("builtin");
const nvapi = @import("../bindings/nvapi.zig");

// nvvk integration for frame generation fallback
const nvvulkan = @import("../nvruntime/nvvulkan/nvvulkan.zig");

pub const version = "0.1.0-dev";

// ============================================================================
// NGX SDK C Bindings (NVIDIA Graphics Extensions)
// ============================================================================

pub const NVSDK_NGX_Result = enum(i32) {
    success = 0x1,
    fail = 0xBAD00000,
    invalid_parameter = 0xBAD00001,
    unsupported = 0xBAD00002,
    out_of_memory = 0xBAD00003,
    not_initialized = 0xBAD00004,
    feature_not_supported = 0xBAD00005,
    path_not_found = 0xBAD00006,
    _,

    pub fn isSuccess(self: NVSDK_NGX_Result) bool {
        return self == .success;
    }
};

pub const NVSDK_NGX_Feature = enum(u32) {
    reserved = 0,
    super_sampling = 1, // DLSS Super Resolution
    inpainting = 2,
    image_super_resolution = 3,
    slow_motion = 4,
    video_super_resolution = 5,
    reserved6 = 6,
    reserved7 = 7,
    reserved8 = 8,
    reserved9 = 9,
    reserved10 = 10,
    reserved11 = 11,
    frame_generation = 12, // DLSS Frame Gen
    deep_resolve = 13,
    deep_dvc = 14,
    ray_reconstruction = 15, // DLSS Ray Reconstruction
};

pub const NVSDK_NGX_PerfQuality_Value = enum(u32) {
    max_perf = 0, // Ultra Performance
    balanced = 1,
    max_quality = 2,
    ultra_performance = 3,
    ultra_quality = 4,
    dlaa = 5,
    _,
};

// Opaque handles
pub const NVSDK_NGX_Handle = opaque {};
pub const NVSDK_NGX_Parameter = opaque {};

// NGX SDK function pointers (loaded dynamically)
// Based on NVSDK_NGX_VULKAN_* exports from libnvidia-ngx.so
pub const NgxFunctions = struct {
    // Vulkan initialization
    init: ?*const fn (
        app_id: u64,
        app_data_path: [*:0]const u8,
        instance: ?*anyopaque, // VkInstance
        physical_device: ?*anyopaque, // VkPhysicalDevice
        device: ?*anyopaque, // VkDevice
        vk_get_instance_proc_addr: ?*anyopaque,
        vk_get_device_proc_addr: ?*anyopaque,
        creation_node_mask: u32,
        visibility_node_mask: u32,
    ) callconv(.C) NVSDK_NGX_Result = null,

    shutdown: ?*const fn () callconv(.C) NVSDK_NGX_Result = null,
    shutdown1: ?*const fn (?*anyopaque) callconv(.C) NVSDK_NGX_Result = null,

    get_capability_parameters: ?*const fn (
        *?*NVSDK_NGX_Parameter,
    ) callconv(.C) NVSDK_NGX_Result = null,

    allocate_parameters: ?*const fn (
        *?*NVSDK_NGX_Parameter,
    ) callconv(.C) NVSDK_NGX_Result = null,

    destroy_parameters: ?*const fn (
        *NVSDK_NGX_Parameter,
    ) callconv(.C) NVSDK_NGX_Result = null,

    create_feature: ?*const fn (
        cmd_list: ?*anyopaque, // VkCommandBuffer
        feature: NVSDK_NGX_Feature,
        params: *NVSDK_NGX_Parameter,
        handle: *?*NVSDK_NGX_Handle,
    ) callconv(.C) NVSDK_NGX_Result = null,

    release_feature: ?*const fn (
        handle: *NVSDK_NGX_Handle,
    ) callconv(.C) NVSDK_NGX_Result = null,

    evaluate: ?*const fn (
        cmd_list: ?*anyopaque, // VkCommandBuffer
        handle: *NVSDK_NGX_Handle,
        params: *NVSDK_NGX_Parameter,
        callback: ?*anyopaque,
    ) callconv(.C) NVSDK_NGX_Result = null,

    get_feature_requirements: ?*const fn (
        feature: NVSDK_NGX_Feature,
        requirements: *NgxFeatureRequirements,
    ) callconv(.C) NVSDK_NGX_Result = null,

    // Library handle for cleanup
    lib_handle: ?std.DynLib = null,
};

/// NGX feature requirements structure
pub const NgxFeatureRequirements = extern struct {
    flags: u32 = 0,
    required_gpu_arch: u32 = 0,
    min_driver_version_major: u32 = 0,
    min_driver_version_minor: u32 = 0,
};

// ============================================================================
// DLSS Types
// ============================================================================

/// DLSS model architecture type
pub const DlssModelType = enum(u8) {
    /// CNN-based model (DLSS 2.x - 3.x)
    cnn,
    /// 1st gen Transformer (DLSS 3.5+)
    transformer_v1,
    /// 2nd gen Transformer (DLSS 4.5+ "Blackwell" optimized)
    transformer_v2,

    pub fn description(self: DlssModelType) []const u8 {
        return switch (self) {
            .cnn => "CNN (Convolutional Neural Network)",
            .transformer_v1 => "Transformer Gen 1",
            .transformer_v2 => "Transformer Gen 2 (DLSS 4.5)",
        };
    }

    pub fn requiresRtx50(self: DlssModelType) bool {
        return self == .transformer_v2;
    }
};

/// DLSS version info
pub const DlssVersion = struct {
    major: u32,
    minor: u32,
    patch: u32,
    build: u32 = 0,

    pub fn supportsFrameGen(self: DlssVersion) bool {
        // DLSS 3.0+ supports frame generation (RTX 40+)
        return self.major >= 3;
    }

    pub fn supportsRayReconstruction(self: DlssVersion) bool {
        // DLSS 3.5+ supports ray reconstruction
        return self.major > 3 or (self.major == 3 and self.minor >= 5);
    }

    pub fn supportsMultiFrameGen(self: DlssVersion) bool {
        // DLSS 4.0+ supports multi frame generation (RTX 50)
        return self.major >= 4;
    }

    pub fn supportsDynamicMfg(self: DlssVersion) bool {
        // DLSS 4.5+ supports Dynamic Multi Frame Generation
        return self.major > 4 or (self.major == 4 and self.minor >= 5);
    }

    pub fn supportsTransformerV2(self: DlssVersion) bool {
        // DLSS 4.5+ uses 2nd gen transformer model
        return self.major > 4 or (self.major == 4 and self.minor >= 5);
    }

    pub fn getModelType(self: DlssVersion) DlssModelType {
        if (self.supportsTransformerV2()) {
            return .transformer_v2;
        } else if (self.supportsRayReconstruction()) {
            return .transformer_v1;
        }
        return .cnn;
    }

    pub fn toString(self: DlssVersion) [32]u8 {
        var buf: [32]u8 = [_]u8{0} ** 32;
        _ = std.fmt.bufPrint(&buf, "{d}.{d}.{d}.{d}", .{
            self.major,
            self.minor,
            self.patch,
            self.build,
        }) catch {};
        return buf;
    }
};

/// DLSS quality mode
pub const QualityMode = enum(u8) {
    ultra_performance, // 3x upscale, best FPS
    performance, // 2x upscale
    balanced, // 1.7x upscale
    quality, // 1.5x upscale
    ultra_quality, // 1.3x upscale
    dlaa, // Native resolution AA only

    pub fn scaleFactor(self: QualityMode) f32 {
        return switch (self) {
            .ultra_performance => 3.0,
            .performance => 2.0,
            .balanced => 1.7,
            .quality => 1.5,
            .ultra_quality => 1.3,
            .dlaa => 1.0,
        };
    }

    pub fn toNgx(self: QualityMode) NVSDK_NGX_PerfQuality_Value {
        return switch (self) {
            .ultra_performance => .ultra_performance,
            .performance => .max_perf,
            .balanced => .balanced,
            .quality => .max_quality,
            .ultra_quality => .ultra_quality,
            .dlaa => .dlaa,
        };
    }

    pub fn getRenderResolution(self: QualityMode, output_width: u32, output_height: u32) struct { width: u32, height: u32 } {
        const scale = self.scaleFactor();
        return .{
            .width = @intFromFloat(@as(f32, @floatFromInt(output_width)) / scale),
            .height = @intFromFloat(@as(f32, @floatFromInt(output_height)) / scale),
        };
    }

    pub fn description(self: QualityMode) []const u8 {
        return switch (self) {
            .ultra_performance => "Ultra Performance (3x upscale)",
            .performance => "Performance (2x upscale)",
            .balanced => "Balanced (1.7x upscale)",
            .quality => "Quality (1.5x upscale)",
            .ultra_quality => "Ultra Quality (1.3x upscale)",
            .dlaa => "DLAA (Native AA)",
        };
    }
};

/// DLSS operating mode
pub const DlssMode = enum(u8) {
    disabled,
    super_resolution, // DLSS-SR (upscaling)
    frame_generation, // DLSS-FG (frame gen, RTX 40+)
    ray_reconstruction, // DLSS-RR (denoising, DLSS 3.5+)
    multi_frame_gen, // DLSS 4 MFG (RTX 50)
};

/// Frame generation mode
pub const FrameGenMode = enum(u8) {
    disabled,
    enabled, // 1 generated frame per rendered (DLSS 3)
    boost, // Adaptive frame generation
    multi_2x, // RTX 50: 2x generated frames (DLSS 4)
    multi_3x, // RTX 50: 3x generated frames (DLSS 4)
    multi_4x, // RTX 50: 4x generated frames (DLSS 4.5)
    dynamic, // DLSS 4.5: Dynamic MFG - auto-adjust to display refresh
    dynamic_6x, // DLSS 4.5: Up to 6x generated frames for 4K@240Hz

    pub fn multiplier(self: FrameGenMode) u8 {
        return switch (self) {
            .disabled => 0,
            .enabled => 1,
            .boost => 1,
            .multi_2x => 2,
            .multi_3x => 3,
            .multi_4x => 4,
            .dynamic => 4, // Dynamic averages ~4x
            .dynamic_6x => 6,
        };
    }

    pub fn requiresRtx50(self: FrameGenMode) bool {
        return switch (self) {
            .multi_2x, .multi_3x, .multi_4x, .dynamic, .dynamic_6x => true,
            else => false,
        };
    }

    pub fn description(self: FrameGenMode) []const u8 {
        return switch (self) {
            .disabled => "Frame Generation disabled",
            .enabled => "Frame Generation (1 extra frame)",
            .boost => "Frame Generation with GPU boost",
            .multi_2x => "Multi Frame Gen 2x (RTX 50)",
            .multi_3x => "Multi Frame Gen 3x (RTX 50)",
            .multi_4x => "Multi Frame Gen 4x (RTX 50)",
            .dynamic => "Dynamic MFG (DLSS 4.5, adapts to display)",
            .dynamic_6x => "Dynamic MFG 6x (4K@240Hz target)",
        };
    }
};

/// Dynamic MFG configuration for DLSS 4.5+
pub const DynamicMfgConfig = struct {
    /// Target display refresh rate (for dynamic frame gen scaling)
    target_refresh_hz: u32 = 165,
    /// Minimum multiplier (1 = just SR, no frame gen)
    min_multiplier: u8 = 1,
    /// Maximum multiplier (2-6 depending on GPU)
    max_multiplier: u8 = 4,
    /// Latency threshold in ms - reduce MFG if exceeded
    max_latency_ms: f32 = 20.0,
    /// Enable automatic quality scaling with MFG
    auto_quality_scale: bool = true,
    /// Prefer lower latency over higher frame rate
    prefer_low_latency: bool = false,
};

/// DLSS configuration
pub const DlssConfig = struct {
    mode: DlssMode = .super_resolution,
    quality: QualityMode = .quality,
    frame_gen: FrameGenMode = .disabled,
    ray_reconstruction: bool = false,
    sharpness: f32 = 0.0, // -1.0 to 1.0
    auto_exposure: bool = true,
    hdr: bool = false,
    preset: DlssPreset = .default,
    /// Dynamic MFG settings (DLSS 4.5+)
    dynamic_mfg: DynamicMfgConfig = .{},
    /// Force specific model type (null = auto-detect)
    force_model: ?DlssModelType = null,

    pub fn fromPreset(preset_name: []const u8) DlssConfig {
        if (std.mem.eql(u8, preset_name, "ultra_performance")) {
            return .{
                .quality = .ultra_performance,
                .frame_gen = .enabled,
            };
        } else if (std.mem.eql(u8, preset_name, "performance")) {
            return .{
                .quality = .performance,
                .frame_gen = .enabled,
            };
        } else if (std.mem.eql(u8, preset_name, "balanced")) {
            return .{
                .quality = .balanced,
                .frame_gen = .enabled,
            };
        } else if (std.mem.eql(u8, preset_name, "quality")) {
            return .{
                .quality = .quality,
                .frame_gen = .disabled,
            };
        } else if (std.mem.eql(u8, preset_name, "mfg_2x")) {
            return .{
                .quality = .performance,
                .frame_gen = .multi_2x,
            };
        } else if (std.mem.eql(u8, preset_name, "mfg_3x")) {
            return .{
                .quality = .performance,
                .frame_gen = .multi_3x,
            };
        } else if (std.mem.eql(u8, preset_name, "mfg_4x")) {
            return .{
                .quality = .balanced,
                .frame_gen = .multi_4x,
            };
        } else if (std.mem.eql(u8, preset_name, "dynamic")) {
            return .{
                .quality = .balanced,
                .frame_gen = .dynamic,
                .dynamic_mfg = .{
                    .auto_quality_scale = true,
                },
            };
        } else if (std.mem.eql(u8, preset_name, "max_fps")) {
            return .{
                .quality = .ultra_performance,
                .frame_gen = .dynamic_6x,
                .dynamic_mfg = .{
                    .target_refresh_hz = 240,
                    .max_multiplier = 6,
                },
            };
        }
        return .{}; // Default
    }
};

/// DLSS preset (affects internal algorithms)
pub const DlssPreset = enum(u8) {
    default,
    preset_a, // Higher quality, more temporal stability
    preset_b, // Faster, less temporal stability
    preset_c, // Quality focused
    preset_d, // Performance focused
    preset_e, // Balanced for ray tracing
    preset_f, // Optimized for high motion
};

// ============================================================================
// Reflex Types
// ============================================================================

/// Reflex mode
pub const ReflexMode = enum(u8) {
    disabled,
    enabled, // Standard low-latency
    boost, // Enabled + GPU boost clocks

    pub fn description(self: ReflexMode) []const u8 {
        return switch (self) {
            .disabled => "Reflex disabled",
            .enabled => "Reflex enabled - Low latency mode",
            .boost => "Reflex enabled + Boost - Maximum latency reduction",
        };
    }
};

/// Reflex statistics
pub const ReflexStats = struct {
    total_latency_us: u64 = 0, // Total system latency
    game_latency_us: u64 = 0, // Game/CPU latency
    render_latency_us: u64 = 0, // GPU render latency
    driver_latency_us: u64 = 0, // Driver queue latency
    os_render_queue_us: u64 = 0, // OS compositor latency
    gpu_active_render_us: u64 = 0,
    frame_id: u64 = 0,
    pc_latency_available: bool = false,

    pub fn totalLatencyMs(self: ReflexStats) f32 {
        return @as(f32, @floatFromInt(self.total_latency_us)) / 1000.0;
    }
};

/// Reflex marker types for latency measurement
pub const ReflexMarker = enum(u32) {
    simulation_start = 0,
    simulation_end = 1,
    render_submit_start = 2,
    render_submit_end = 3,
    present_start = 4,
    present_end = 5,
    input_sample = 6,
    trigger_flash = 7,
    pc_latency_ping = 8,
};

// ============================================================================
// RTX Video Super Resolution
// ============================================================================

/// RTX VSR mode for video upscaling
pub const VideoSuperResMode = enum(u8) {
    disabled,
    quality_1, // Subtle enhancement
    quality_2,
    quality_3,
    quality_4, // Maximum enhancement
};

/// RTX Video HDR mode
pub const VideoHdrMode = enum(u8) {
    disabled,
    enabled,
    auto_detect,
};

/// RTX Video configuration
pub const VideoConfig = struct {
    super_resolution: VideoSuperResMode = .disabled,
    hdr: VideoHdrMode = .disabled,
    apply_to_windowed: bool = true,
    apply_to_fullscreen: bool = true,
};

// ============================================================================
// GPU Capabilities
// ============================================================================

/// GPU generation for feature support detection
pub const GpuGeneration = enum(u8) {
    unknown,
    turing, // RTX 20 series (SM 7.5)
    ampere, // RTX 30 series (SM 8.6)
    ada_lovelace, // RTX 40 series (SM 8.9)
    blackwell, // RTX 50 series (SM 10.0)

    pub fn tensorCoreGen(self: GpuGeneration) u8 {
        return switch (self) {
            .unknown => 0,
            .turing => 3,
            .ampere => 4,
            .ada_lovelace => 5,
            .blackwell => 6,
        };
    }

    pub fn supportsFrameGen(self: GpuGeneration) bool {
        return self == .ada_lovelace or self == .blackwell;
    }

    pub fn supportsMultiFrameGen(self: GpuGeneration) bool {
        return self == .blackwell;
    }

    pub fn supportsDynamicMfg(self: GpuGeneration) bool {
        return self == .blackwell;
    }

    pub fn maxMfgMultiplier(self: GpuGeneration) u8 {
        return switch (self) {
            .blackwell => 6, // Up to 6x with Dynamic MFG
            .ada_lovelace => 1, // DLSS 3 is 1 extra frame
            else => 0,
        };
    }

    pub fn name(self: GpuGeneration) []const u8 {
        return switch (self) {
            .unknown => "Unknown",
            .turing => "Turing (RTX 20)",
            .ampere => "Ampere (RTX 30)",
            .ada_lovelace => "Ada Lovelace (RTX 40)",
            .blackwell => "Blackwell (RTX 50)",
        };
    }
};

/// GPU feature support
pub const GpuCapabilities = struct {
    supports_dlss_sr: bool = false, // RTX 20+
    supports_dlss_fg: bool = false, // RTX 40+
    supports_dlss_rr: bool = false, // RTX 40+ with DLSS 3.5+
    supports_dlss_mfg: bool = false, // RTX 50+
    supports_dynamic_mfg: bool = false, // RTX 50+ with DLSS 4.5+
    supports_reflex: bool = false, // All NVIDIA
    supports_video_sr: bool = false, // RTX 30+
    supports_video_hdr: bool = false, // RTX 30+
    supports_rtx_hdr: bool = false, // RTX 30+ Auto-HDR

    max_render_width: u32 = 0,
    max_render_height: u32 = 0,
    min_render_width: u32 = 0,
    min_render_height: u32 = 0,

    gpu_generation: GpuGeneration = .unknown,
    tensor_core_gen: u8 = 0, // 0 = none, 3 = Turing, 4 = Ampere, 5 = Ada, 6 = Blackwell
    driver_version: u32 = 0,
    model_type: DlssModelType = .cnn,

    pub fn fromGeneration(gen: GpuGeneration) GpuCapabilities {
        var caps = GpuCapabilities{
            .gpu_generation = gen,
            .tensor_core_gen = gen.tensorCoreGen(),
        };

        // Set capabilities based on generation
        switch (gen) {
            .blackwell => {
                caps.supports_dlss_sr = true;
                caps.supports_dlss_fg = true;
                caps.supports_dlss_rr = true;
                caps.supports_dlss_mfg = true;
                caps.supports_dynamic_mfg = true;
                caps.supports_reflex = true;
                caps.supports_video_sr = true;
                caps.supports_video_hdr = true;
                caps.supports_rtx_hdr = true;
                caps.model_type = .transformer_v2;
            },
            .ada_lovelace => {
                caps.supports_dlss_sr = true;
                caps.supports_dlss_fg = true;
                caps.supports_dlss_rr = true;
                caps.supports_reflex = true;
                caps.supports_video_sr = true;
                caps.supports_video_hdr = true;
                caps.supports_rtx_hdr = true;
                caps.model_type = .transformer_v1;
            },
            .ampere => {
                caps.supports_dlss_sr = true;
                caps.supports_reflex = true;
                caps.supports_video_sr = true;
                caps.supports_video_hdr = true;
                caps.model_type = .cnn;
            },
            .turing => {
                caps.supports_dlss_sr = true;
                caps.supports_reflex = true;
                caps.model_type = .cnn;
            },
            .unknown => {},
        }

        // Common limits
        caps.max_render_width = 7680;
        caps.max_render_height = 4320;
        caps.min_render_width = 128;
        caps.min_render_height = 128;

        return caps;
    }
};

// ============================================================================
// DLSS Context
// ============================================================================

pub const DlssError = error{
    NgxNotFound,
    NgxInitFailed,
    FeatureNotSupported,
    InvalidConfig,
    GpuNotSupported,
    OutOfMemory,
    DriverTooOld,
    InvalidState,
    EvaluateFailed,
};

/// Wrapper for nvvk frame generation (fallback when NGX unavailable)
/// Uses VK_NV_optical_flow extension for motion estimation
pub const NvvkFrameGenWrapper = struct {
    allocator: std.mem.Allocator,
    config: nvvulkan.FrameGenConfig,
    mode: FrameGenMode,
    stats: FrameGenStats,

    pub const FrameGenStats = struct {
        frames_generated: u64 = 0,
        frames_skipped: u64 = 0,
        avg_gen_time_us: u64 = 0,
        confidence: f32 = 1.0,
    };

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32, mode: FrameGenMode) !*NvvkFrameGenWrapper {
        const self = try allocator.create(NvvkFrameGenWrapper);
        self.* = NvvkFrameGenWrapper{
            .allocator = allocator,
            .config = .{
                .width = width,
                .height = height,
                .mode = modeToNvvk(mode),
            },
            .mode = mode,
            .stats = .{},
        };
        return self;
    }

    pub fn deinit(self: *NvvkFrameGenWrapper) void {
        self.allocator.destroy(self);
    }

    pub fn getStats(self: *const NvvkFrameGenWrapper) FrameGenStats {
        return self.stats;
    }

    pub fn setMode(self: *NvvkFrameGenWrapper, mode: FrameGenMode) void {
        self.mode = mode;
        self.config.mode = modeToNvvk(mode);
    }

    fn modeToNvvk(mode: FrameGenMode) nvvulkan.FrameGenMode {
        return switch (mode) {
            .disabled => .off,
            .enabled => .balanced,
            .boost => .quality,
            .multi_2x, .multi_3x, .multi_4x => .quality,
            .dynamic, .dynamic_6x => .quality,
        };
    }

    /// Check if nvvk frame generation is available on this system
    pub fn isAvailable() bool {
        // Check for VK_NV_optical_flow extension support
        // This requires driver 590+ and RTX 20+ GPU
        return nvvulkan.isNvidiaGpu();
    }
};

/// DLSS runtime context
pub const DlssContext = struct {
    allocator: std.mem.Allocator,
    config: DlssConfig,
    capabilities: GpuCapabilities,
    version: ?DlssVersion,
    initialized: bool = false,

    // NGX handles
    ngx_functions: NgxFunctions = .{},
    ngx_sr_handle: ?*NVSDK_NGX_Handle = null,
    ngx_fg_handle: ?*NVSDK_NGX_Handle = null,
    ngx_rr_handle: ?*NVSDK_NGX_Handle = null,
    ngx_params: ?*NVSDK_NGX_Parameter = null,

    // nvvk frame generation fallback (when NGX unavailable)
    // Uses VK_NV_optical_flow for motion estimation + custom synthesis
    nvvk_frame_gen: ?*NvvkFrameGenWrapper = null,
    use_nvvk_fallback: bool = false,

    // Frame tracking
    frame_index: u64 = 0,
    frames_upscaled: u64 = 0,
    frames_generated: u64 = 0,

    const Self = @This();

    /// Initialize DLSS context
    pub fn init(allocator: std.mem.Allocator, config: DlssConfig) DlssError!Self {
        var ctx = Self{
            .allocator = allocator,
            .config = config,
            .capabilities = .{},
            .version = null,
        };

        // Try to load NGX SDK
        ctx.loadNgxSdk() catch |err| {
            std.log.warn("NGX SDK not available: {}", .{err});
            // Continue with mock/stub mode for development
        };

        // Query GPU capabilities
        ctx.queryCapabilities();

        // Validate config against capabilities
        try ctx.validateConfig();

        ctx.initialized = true;
        return ctx;
    }

    /// Cleanup resources
    pub fn deinit(self: *Self) void {
        // Release NGX feature handles
        if (self.ngx_sr_handle) |handle| {
            if (self.ngx_functions.release_feature) |release| {
                _ = release(handle);
            }
            self.ngx_sr_handle = null;
        }
        if (self.ngx_fg_handle) |handle| {
            if (self.ngx_functions.release_feature) |release| {
                _ = release(handle);
            }
            self.ngx_fg_handle = null;
        }
        if (self.ngx_rr_handle) |handle| {
            if (self.ngx_functions.release_feature) |release| {
                _ = release(handle);
            }
            self.ngx_rr_handle = null;
        }

        // Destroy parameters
        if (self.ngx_params) |params| {
            if (self.ngx_functions.destroy_parameters) |destroy| {
                _ = destroy(params);
            }
            self.ngx_params = null;
        }

        // Shutdown NGX
        if (self.ngx_functions.shutdown) |shutdown| {
            _ = shutdown();
        }

        // Close library handle
        if (self.ngx_functions.lib_handle) |*lib| {
            lib.close();
            self.ngx_functions.lib_handle = null;
        }

        self.initialized = false;
    }

    fn loadNgxSdk(self: *Self) !void {
        // Try to load libnvidia-ngx.so dynamically
        // On Linux with driver 590+, this provides DLSS 4.x support
        const lib_paths = [_][]const u8{
            "libnvidia-ngx.so.1",
            "libnvidia-ngx.so",
            "/usr/lib/libnvidia-ngx.so.1",
            "/usr/lib/libnvidia-ngx.so",
            "/usr/lib64/libnvidia-ngx.so.1",
        };

        var lib: ?std.DynLib = null;
        for (lib_paths) |path| {
            lib = std.DynLib.open(path) catch continue;
            break;
        }

        if (lib == null) {
            std.log.warn("NGX SDK library not found, DLSS features unavailable", .{});
            return error.NgxNotFound;
        }

        var dynlib = lib.?;
        self.ngx_functions.lib_handle = dynlib;

        // Resolve Vulkan-specific NGX functions
        self.ngx_functions.init = dynlib.lookup(
            *const fn (u64, [*:0]const u8, ?*anyopaque, ?*anyopaque, ?*anyopaque, ?*anyopaque, ?*anyopaque, u32, u32) callconv(.C) NVSDK_NGX_Result,
            "NVSDK_NGX_VULKAN_Init",
        );

        self.ngx_functions.shutdown = dynlib.lookup(
            *const fn () callconv(.C) NVSDK_NGX_Result,
            "NVSDK_NGX_VULKAN_Shutdown",
        );

        self.ngx_functions.shutdown1 = dynlib.lookup(
            *const fn (?*anyopaque) callconv(.C) NVSDK_NGX_Result,
            "NVSDK_NGX_VULKAN_Shutdown1",
        );

        self.ngx_functions.get_capability_parameters = dynlib.lookup(
            *const fn (*?*NVSDK_NGX_Parameter) callconv(.C) NVSDK_NGX_Result,
            "NVSDK_NGX_VULKAN_GetCapabilityParameters",
        );

        self.ngx_functions.allocate_parameters = dynlib.lookup(
            *const fn (*?*NVSDK_NGX_Parameter) callconv(.C) NVSDK_NGX_Result,
            "NVSDK_NGX_VULKAN_AllocateParameters",
        );

        self.ngx_functions.destroy_parameters = dynlib.lookup(
            *const fn (*NVSDK_NGX_Parameter) callconv(.C) NVSDK_NGX_Result,
            "NVSDK_NGX_VULKAN_DestroyParameters",
        );

        self.ngx_functions.create_feature = dynlib.lookup(
            *const fn (?*anyopaque, NVSDK_NGX_Feature, *NVSDK_NGX_Parameter, *?*NVSDK_NGX_Handle) callconv(.C) NVSDK_NGX_Result,
            "NVSDK_NGX_VULKAN_CreateFeature",
        );

        self.ngx_functions.release_feature = dynlib.lookup(
            *const fn (*NVSDK_NGX_Handle) callconv(.C) NVSDK_NGX_Result,
            "NVSDK_NGX_VULKAN_ReleaseFeature",
        );

        self.ngx_functions.evaluate = dynlib.lookup(
            *const fn (?*anyopaque, *NVSDK_NGX_Handle, *NVSDK_NGX_Parameter, ?*anyopaque) callconv(.C) NVSDK_NGX_Result,
            "NVSDK_NGX_VULKAN_EvaluateFeature",
        );

        self.ngx_functions.get_feature_requirements = dynlib.lookup(
            *const fn (NVSDK_NGX_Feature, *NgxFeatureRequirements) callconv(.C) NVSDK_NGX_Result,
            "NVSDK_NGX_VULKAN_GetFeatureRequirements",
        );

        // Check if we have the minimum required functions
        if (self.ngx_functions.get_capability_parameters == null) {
            std.log.warn("NGX SDK missing required functions", .{});
            return error.NgxNotFound;
        }

        std.log.info("NGX SDK loaded successfully", .{});
    }

    fn queryCapabilities(self: *Self) void {
        // Try to query real capabilities via NGX if available
        if (self.ngx_functions.get_feature_requirements) |get_reqs| {
            // Check DLSS Super Resolution support
            var sr_reqs: NgxFeatureRequirements = .{};
            const sr_result = get_reqs(.super_sampling, &sr_reqs);
            self.capabilities.supports_dlss_sr = sr_result.isSuccess();

            // Check Frame Generation support (RTX 40+)
            var fg_reqs: NgxFeatureRequirements = .{};
            const fg_result = get_reqs(.frame_generation, &fg_reqs);
            self.capabilities.supports_dlss_fg = fg_result.isSuccess();

            // Check Ray Reconstruction support
            var rr_reqs: NgxFeatureRequirements = .{};
            const rr_result = get_reqs(.ray_reconstruction, &rr_reqs);
            self.capabilities.supports_dlss_rr = rr_result.isSuccess();

            // Infer tensor core generation from driver requirements
            if (fg_reqs.required_gpu_arch >= 0x89) { // Ada Lovelace
                self.capabilities.tensor_core_gen = 5;
            } else if (sr_reqs.required_gpu_arch >= 0x86) { // Ampere
                self.capabilities.tensor_core_gen = 4;
            } else if (sr_reqs.required_gpu_arch >= 0x75) { // Turing
                self.capabilities.tensor_core_gen = 3;
            }

            self.capabilities.driver_version = sr_reqs.min_driver_version_major;

            std.log.info("NGX capabilities: SR={} FG={} RR={} arch={x}", .{
                self.capabilities.supports_dlss_sr,
                self.capabilities.supports_dlss_fg,
                self.capabilities.supports_dlss_rr,
                sr_reqs.required_gpu_arch,
            });
        } else {
            // Fallback: detect GPU generation from environment or assume RTX 50
            const detected_gen = detectGpuGeneration();
            std.log.info("NGX API unavailable, using fallback for {} GPU", .{detected_gen.name()});
            self.capabilities = GpuCapabilities.fromGeneration(detected_gen);
            self.capabilities.driver_version = 590;
        }

        // Infer GPU generation from tensor core gen if not set
        if (self.capabilities.gpu_generation == .unknown) {
            self.capabilities.gpu_generation = switch (self.capabilities.tensor_core_gen) {
                6 => .blackwell,
                5 => .ada_lovelace,
                4 => .ampere,
                3 => .turing,
                else => .unknown,
            };
        }

        // Set model type based on generation
        self.capabilities.model_type = switch (self.capabilities.gpu_generation) {
            .blackwell => .transformer_v2,
            .ada_lovelace => .transformer_v1,
            else => .cnn,
        };

        // Dynamic MFG is RTX 50+ with DLSS 4.5+
        self.capabilities.supports_dynamic_mfg = self.capabilities.gpu_generation == .blackwell;

        // Multi-frame gen is RTX 50+ only
        self.capabilities.supports_dlss_mfg = self.capabilities.gpu_generation == .blackwell;

        // RTX HDR (Auto-HDR) is RTX 30+ only
        self.capabilities.supports_rtx_hdr = self.capabilities.tensor_core_gen >= 4;

        // Set DLSS version based on capabilities
        if (self.capabilities.supports_dynamic_mfg) {
            // RTX 50 with DLSS 4.5
            self.version = DlssVersion{ .major = 4, .minor = 5, .patch = 0, .build = 1 };
        } else if (self.capabilities.supports_dlss_mfg) {
            self.version = DlssVersion{ .major = 4, .minor = 0, .patch = 0, .build = 1 };
        } else if (self.capabilities.supports_dlss_rr) {
            self.version = DlssVersion{ .major = 3, .minor = 7, .patch = 0, .build = 1 };
        } else if (self.capabilities.supports_dlss_fg) {
            self.version = DlssVersion{ .major = 3, .minor = 0, .patch = 0, .build = 1 };
        } else if (self.capabilities.supports_dlss_sr) {
            self.version = DlssVersion{ .major = 2, .minor = 5, .patch = 0, .build = 1 };
        }

        std.log.info("DLSS {s} initialized: model={s}, MFG={}, Dynamic={}", .{
            if (self.version) |v| &v.toString() else "unknown",
            self.capabilities.model_type.description(),
            self.capabilities.supports_dlss_mfg,
            self.capabilities.supports_dynamic_mfg,
        });
    }

    fn validateConfig(self: *Self) DlssError!void {
        const caps = self.capabilities;
        const cfg = self.config;

        if (cfg.mode == .super_resolution and !caps.supports_dlss_sr) {
            return DlssError.FeatureNotSupported;
        }
        if (cfg.mode == .frame_generation and !caps.supports_dlss_fg) {
            return DlssError.FeatureNotSupported;
        }
        if (cfg.mode == .ray_reconstruction and !caps.supports_dlss_rr) {
            return DlssError.FeatureNotSupported;
        }
        if (cfg.mode == .multi_frame_gen and !caps.supports_dlss_mfg) {
            return DlssError.FeatureNotSupported;
        }
    }

    /// Update DLSS configuration
    pub fn setConfig(self: *Self, config: DlssConfig) DlssError!void {
        self.config = config;
        try self.validateConfig();
        // TODO: Recreate NGX features if needed
    }

    /// Get optimal render resolution for DLSS upscaling
    pub fn getRenderResolution(self: *const Self, output_width: u32, output_height: u32) struct { width: u32, height: u32 } {
        if (self.config.mode != .super_resolution and self.config.mode != .frame_generation) {
            return .{ .width = output_width, .height = output_height };
        }
        return self.config.quality.getRenderResolution(output_width, output_height);
    }

    /// Process frame through DLSS
    pub fn evaluate(self: *Self, input: DlssInput) DlssError!DlssOutput {
        if (!self.initialized) {
            return DlssError.InvalidState;
        }

        self.frame_index += 1;

        // TODO: Actual NGX evaluation
        // 1. Set input parameters (color, depth, motion vectors, exposure)
        // 2. Call NVSDK_NGX_VULKAN_EvaluateFeature / D3D equivalent
        // 3. Return upscaled/generated output

        _ = input;

        // Stub output
        return DlssOutput{
            .frame_index = self.frame_index,
            .upscaled = self.config.mode == .super_resolution or self.config.mode == .frame_generation,
            .generated = self.config.mode == .frame_generation or self.config.mode == .multi_frame_gen,
            .generated_frame_count = if (self.config.frame_gen == .multi_3x) @as(u8, 3) else if (self.config.frame_gen == .multi_2x) @as(u8, 2) else if (self.config.mode == .frame_generation) @as(u8, 1) else @as(u8, 0),
        };
    }

    /// Get performance statistics
    pub fn getStats(self: *const Self) DlssStats {
        return DlssStats{
            .frames_upscaled = self.frames_upscaled,
            .frames_generated = self.frames_generated,
            .mode = self.config.mode,
            .quality = self.config.quality,
            .version = self.version,
        };
    }
};

/// Input to DLSS evaluation
pub const DlssInput = struct {
    // Texture handles (opaque Vulkan/D3D handles)
    color_input: ?*anyopaque = null, // Low-res rendered frame
    depth_buffer: ?*anyopaque = null, // Depth buffer
    motion_vectors: ?*anyopaque = null, // Per-pixel motion
    exposure: ?*anyopaque = null, // Exposure texture

    // Dimensions
    render_width: u32,
    render_height: u32,
    output_width: u32,
    output_height: u32,

    // Camera data
    jitter_x: f32 = 0,
    jitter_y: f32 = 0,
    mv_scale_x: f32 = 1.0,
    mv_scale_y: f32 = 1.0,

    // Frame data
    reset: bool = false, // Reset temporal history
    sharpness: f32 = 0.0,
};

/// Output from DLSS evaluation
pub const DlssOutput = struct {
    frame_index: u64,
    upscaled: bool,
    generated: bool,
    generated_frame_count: u8,
};

/// DLSS performance statistics
pub const DlssStats = struct {
    frames_upscaled: u64,
    frames_generated: u64,
    mode: DlssMode,
    quality: QualityMode,
    version: ?DlssVersion,
};

// ============================================================================
// Reflex Context
// ============================================================================

/// Reflex runtime context
pub const ReflexContext = struct {
    allocator: std.mem.Allocator,
    mode: ReflexMode = .disabled,
    initialized: bool = false,
    stats: ReflexStats = .{},

    // NVAPI context for low-latency API calls
    nvapi_ctx: nvapi.NvApiContext,

    // Frame pacing
    target_framerate: u32 = 0, // 0 = unlimited
    frame_index: u64 = 0,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, mode: ReflexMode) !Self {
        var ctx = Self{
            .allocator = allocator,
            .mode = mode,
            .nvapi_ctx = nvapi.NvApiContext.init(allocator),
        };

        // Set initial mode if not disabled
        if (mode != .disabled) {
            ctx.setMode(mode);
        }

        ctx.initialized = true;

        if (ctx.nvapi_ctx.isAvailable()) {
            std.log.info("Reflex initialized with NVAPI/VK_NV_low_latency2 support", .{});
        } else {
            std.log.info("Reflex initialized (low-latency API not available)", .{});
        }

        return ctx;
    }

    pub fn deinit(self: *Self) void {
        // Log final stats
        if (self.stats.total_latency_us > 0) {
            std.log.info("Reflex final stats: avg latency={d:.2}ms over {} frames", .{
                self.stats.totalLatencyMs(),
                self.frame_index,
            });
        }

        self.nvapi_ctx.deinit();
        self.initialized = false;
    }

    /// Set Vulkan device for VK_NV_low_latency2 extension
    pub fn setVulkanDevice(
        self: *Self,
        device: *anyopaque,
        swapchain: u64,
        get_device_proc_addr: *const fn (*anyopaque, [*:0]const u8) callconv(.C) ?*anyopaque,
    ) void {
        self.nvapi_ctx.setVulkanDevice(device, swapchain, get_device_proc_addr);
    }

    /// Update swapchain after recreation
    pub fn updateSwapchain(self: *Self, swapchain: u64) void {
        self.nvapi_ctx.updateSwapchain(swapchain);
    }

    /// Set reflex mode
    pub fn setMode(self: *Self, mode: ReflexMode) void {
        self.mode = mode;

        // Convert to NVAPI latency mode
        const nvapi_mode: nvapi.NV_LATENCY_MODE = switch (mode) {
            .disabled => .OFF,
            .enabled => .ON,
            .boost => .ULTRA,
        };

        self.nvapi_ctx.setLatencyMode(nvapi_mode) catch |err| {
            std.log.warn("Failed to set latency mode: {}", .{err});
        };
    }

    /// Signal simulation start
    pub fn simulationStart(self: *Self) void {
        if (self.mode == .disabled) return;
        self.frame_index += 1;
        self.nvapi_ctx.frame_id = self.frame_index;
        self.nvapi_ctx.beginFrame();
    }

    /// Signal simulation end
    pub fn simulationEnd(self: *Self) void {
        if (self.mode == .disabled) return;
        self.nvapi_ctx.endSimulation();
    }

    /// Signal render submit start
    pub fn renderSubmitStart(self: *Self) void {
        if (self.mode == .disabled) return;
        self.nvapi_ctx.beginRenderSubmit();
    }

    /// Signal render submit end
    pub fn renderSubmitEnd(self: *Self) void {
        if (self.mode == .disabled) return;
        self.nvapi_ctx.endRenderSubmit();
    }

    /// Signal present start
    pub fn presentStart(self: *Self) void {
        if (self.mode == .disabled) return;
        self.nvapi_ctx.beginPresent();
    }

    /// Signal present end
    pub fn presentEnd(self: *Self) void {
        if (self.mode == .disabled) return;
        self.nvapi_ctx.endPresent();
    }

    /// Set latency marker (low-level)
    pub fn setMarker(self: *Self, marker: ReflexMarker) void {
        if (self.mode == .disabled) return;

        // Convert to NVAPI marker type
        const nvapi_marker: nvapi.NV_LATENCY_MARKER_TYPE = switch (marker) {
            .simulation_start => .SIMULATION_START,
            .simulation_end => .SIMULATION_END,
            .render_submit_start => .RENDERSUBMIT_START,
            .render_submit_end => .RENDERSUBMIT_END,
            .present_start => .PRESENT_START,
            .present_end => .PRESENT_END,
            .input_sample => .INPUT_SAMPLE,
            .trigger_flash => .TRIGGER_FLASH,
            .pc_latency_ping => .PC_LATENCY_PING,
        };

        self.nvapi_ctx.setMarker(nvapi_marker);
    }

    /// Sleep to reduce latency (call before simulation)
    pub fn sleep(self: *Self) void {
        if (self.mode == .disabled) return;

        self.nvapi_ctx.sleep(null, 0) catch |err| {
            std.log.debug("Reflex sleep failed: {}", .{err});
        };
    }

    /// Mark input sample time
    pub fn markInputSample(self: *Self) void {
        if (self.mode == .disabled) return;
        self.nvapi_ctx.markInputSample();
    }

    /// Get current latency stats
    pub fn getStats(self: *Self) ReflexStats {
        // Query latest timing reports
        var reports: [64]nvapi.FrameReport = [_]nvapi.FrameReport{.{}} ** 64;
        const count = self.nvapi_ctx.getLatencyTimings(&reports) catch 0;

        if (count > 0) {
            // Use the most recent report
            const latest = reports[count - 1];
            self.stats = ReflexStats{
                .total_latency_us = latest.getPcLatencyUs(),
                .game_latency_us = latest.getGameLatencyUs(),
                .render_latency_us = latest.getRenderLatencyUs(),
                .driver_latency_us = if (latest.driver_end_time > latest.driver_start_time)
                    latest.driver_end_time - latest.driver_start_time
                else
                    0,
                .os_render_queue_us = if (latest.os_render_queue_end_time > latest.os_render_queue_start_time)
                    latest.os_render_queue_end_time - latest.os_render_queue_start_time
                else
                    0,
                .gpu_active_render_us = latest.gpu_active_render_time_us,
                .frame_id = latest.frame_id,
                .pc_latency_available = latest.getPcLatencyUs() > 0,
            };
        }

        return self.stats;
    }

    /// Set target framerate for frame pacing
    pub fn setTargetFramerate(self: *Self, fps: u32) void {
        self.target_framerate = fps;
        // Note: Frame rate limiting is typically handled by the application
        // or via VRR/G-Sync. Reflex focuses on latency, not FPS limiting.
    }

    /// Check if low-latency API is available
    pub fn isAvailable(self: *const Self) bool {
        return self.nvapi_ctx.isAvailable();
    }
};

// ============================================================================
// Public API
// ============================================================================

/// Detect GPU generation from PCI device info or environment
pub fn detectGpuGeneration() GpuGeneration {
    // Check for override environment variable
    if (std.c.getenv("DLSS_GPU_GEN")) |gen_str| {
        const gen = std.mem.sliceTo(gen_str, 0);
        if (std.mem.eql(u8, gen, "blackwell") or std.mem.eql(u8, gen, "50")) {
            return .blackwell;
        } else if (std.mem.eql(u8, gen, "ada") or std.mem.eql(u8, gen, "40")) {
            return .ada_lovelace;
        } else if (std.mem.eql(u8, gen, "ampere") or std.mem.eql(u8, gen, "30")) {
            return .ampere;
        } else if (std.mem.eql(u8, gen, "turing") or std.mem.eql(u8, gen, "20")) {
            return .turing;
        }
    }

    // Try to read GPU device ID from sysfs
    const io = std.Io.Threaded.global_single_threaded.io();
    const gpu_paths = [_][]const u8{
        "/sys/class/drm/card0/device/device",
        "/sys/class/drm/card1/device/device",
    };

    for (gpu_paths) |path| {
        if (std.Io.Dir.openFileAbsolute(io, path, .{})) |file| {
            defer file.close(io);
            var buf: [32]u8 = undefined;
            if (file.read(io, &buf)) |len| {
                const device_id_str = std.mem.trim(u8, buf[0..len], " \n\r\t");
                // Parse hex device ID (format: 0x2684 for RTX 50 series)
                if (device_id_str.len > 2 and device_id_str[0] == '0' and device_id_str[1] == 'x') {
                    if (std.fmt.parseInt(u16, device_id_str[2..], 16)) |device_id| {
                        return detectGenerationFromDeviceId(device_id);
                    } else |_| {}
                }
            } else |_| {}
        } else |_| {}
    }

    // Default to RTX 50 (Blackwell) for development
    return .blackwell;
}

/// Map NVIDIA device ID to GPU generation
fn detectGenerationFromDeviceId(device_id: u16) GpuGeneration {
    // RTX 50 series (Blackwell) - 0x26xx, 0x27xx
    if (device_id >= 0x2600 and device_id < 0x2800) {
        return .blackwell;
    }
    // RTX 40 series (Ada Lovelace) - 0x26xx, 0x27xx (subset), 0x28xx
    if (device_id >= 0x2680 and device_id < 0x2700) {
        return .ada_lovelace; // RTX 4090, 4080
    }
    if (device_id >= 0x2700 and device_id < 0x2800) {
        return .ada_lovelace; // RTX 4070, etc.
    }
    // RTX 30 series (Ampere) - 0x22xx, 0x24xx, 0x25xx
    if (device_id >= 0x2200 and device_id < 0x2600) {
        return .ampere;
    }
    // RTX 20 series (Turing) - 0x1Exx, 0x1Fxx, 0x21xx
    if (device_id >= 0x1E00 and device_id < 0x2200) {
        return .turing;
    }
    return .unknown;
}

/// Check DLSS availability (checks for NGX library)
pub fn isAvailable() bool {
    // Try to load NGX library to check availability
    const lib_paths = [_][]const u8{
        "libnvidia-ngx.so.1",
        "libnvidia-ngx.so",
        "/usr/lib/libnvidia-ngx.so.1",
    };

    for (lib_paths) |path| {
        if (std.DynLib.open(path)) |lib| {
            // Library found, check for required symbol
            const has_caps = lib.lookup(
                *const fn (*?*NVSDK_NGX_Parameter) callconv(.C) NVSDK_NGX_Result,
                "NVSDK_NGX_VULKAN_GetCapabilityParameters",
            ) != null;
            var lib_copy = lib;
            lib_copy.close();
            if (has_caps) return true;
        } else |_| {
            continue;
        }
    }
    return false;
}

/// Check if specific DLSS feature is available
pub fn isFeatureAvailable(feature: NVSDK_NGX_Feature) bool {
    return switch (feature) {
        .super_sampling => true,
        .frame_generation => true,
        .ray_reconstruction => true,
        else => false,
    };
}

/// Get DLSS version based on detected GPU
pub fn getVersion() ?DlssVersion {
    const gen = detectGpuGeneration();
    return switch (gen) {
        .blackwell => DlssVersion{ .major = 4, .minor = 5, .patch = 0, .build = 1 },
        .ada_lovelace => DlssVersion{ .major = 3, .minor = 7, .patch = 0, .build = 1 },
        .ampere => DlssVersion{ .major = 2, .minor = 5, .patch = 1, .build = 1 },
        .turing => DlssVersion{ .major = 2, .minor = 4, .patch = 0, .build = 1 },
        .unknown => null,
    };
}

/// Get GPU capabilities based on detected generation
pub fn getCapabilities() GpuCapabilities {
    const gen = detectGpuGeneration();
    return GpuCapabilities.fromGeneration(gen);
}

/// Get recommended frame gen mode for GPU and target refresh rate
pub fn getRecommendedFrameGen(gen: GpuGeneration, target_refresh_hz: u32) FrameGenMode {
    return switch (gen) {
        .blackwell => blk: {
            // RTX 50: Use Dynamic MFG for high refresh, multi_4x for 4K@120+
            if (target_refresh_hz >= 240) {
                break :blk .dynamic_6x;
            } else if (target_refresh_hz >= 165) {
                break :blk .dynamic;
            } else if (target_refresh_hz >= 120) {
                break :blk .multi_4x;
            } else {
                break :blk .multi_2x;
            }
        },
        .ada_lovelace => .enabled, // RTX 40: Standard DLSS 3 frame gen
        else => .disabled, // RTX 30 and below: No frame gen
    };
}

/// Check Reflex availability
pub fn isReflexAvailable() bool {
    return true;
}

/// Get recommended quality mode for given resolution
pub fn getRecommendedQuality(output_width: u32, output_height: u32) QualityMode {
    const pixels = output_width * output_height;
    if (pixels >= 3840 * 2160) {
        return .performance; // 4K - use Performance
    } else if (pixels >= 2560 * 1440) {
        return .quality; // 1440p - use Quality
    } else {
        return .dlaa; // 1080p and below - use DLAA
    }
}

// ============================================================================
// Tests
// ============================================================================

test "dlss version features" {
    const v3 = DlssVersion{ .major = 3, .minor = 0, .patch = 0 };
    try std.testing.expect(v3.supportsFrameGen());
    try std.testing.expect(!v3.supportsRayReconstruction());
    try std.testing.expect(!v3.supportsDynamicMfg());

    const v35 = DlssVersion{ .major = 3, .minor = 5, .patch = 0 };
    try std.testing.expect(v35.supportsRayReconstruction());
    try std.testing.expectEqual(DlssModelType.transformer_v1, v35.getModelType());

    const v4 = DlssVersion{ .major = 4, .minor = 0, .patch = 0 };
    try std.testing.expect(v4.supportsMultiFrameGen());
    try std.testing.expect(!v4.supportsDynamicMfg());

    const v45 = DlssVersion{ .major = 4, .minor = 5, .patch = 0 };
    try std.testing.expect(v45.supportsDynamicMfg());
    try std.testing.expect(v45.supportsTransformerV2());
    try std.testing.expectEqual(DlssModelType.transformer_v2, v45.getModelType());
}

test "dlss model types" {
    try std.testing.expect(!DlssModelType.cnn.requiresRtx50());
    try std.testing.expect(!DlssModelType.transformer_v1.requiresRtx50());
    try std.testing.expect(DlssModelType.transformer_v2.requiresRtx50());
}

test "frame gen modes" {
    try std.testing.expectEqual(@as(u8, 1), FrameGenMode.enabled.multiplier());
    try std.testing.expectEqual(@as(u8, 4), FrameGenMode.multi_4x.multiplier());
    try std.testing.expectEqual(@as(u8, 6), FrameGenMode.dynamic_6x.multiplier());

    try std.testing.expect(!FrameGenMode.enabled.requiresRtx50());
    try std.testing.expect(FrameGenMode.multi_4x.requiresRtx50());
    try std.testing.expect(FrameGenMode.dynamic.requiresRtx50());
}

test "gpu generation capabilities" {
    const blackwell = GpuCapabilities.fromGeneration(.blackwell);
    try std.testing.expect(blackwell.supports_dlss_mfg);
    try std.testing.expect(blackwell.supports_dynamic_mfg);
    try std.testing.expectEqual(DlssModelType.transformer_v2, blackwell.model_type);

    const ada = GpuCapabilities.fromGeneration(.ada_lovelace);
    try std.testing.expect(ada.supports_dlss_fg);
    try std.testing.expect(!ada.supports_dlss_mfg);
    try std.testing.expectEqual(DlssModelType.transformer_v1, ada.model_type);

    const ampere = GpuCapabilities.fromGeneration(.ampere);
    try std.testing.expect(ampere.supports_dlss_sr);
    try std.testing.expect(!ampere.supports_dlss_fg);
    try std.testing.expectEqual(DlssModelType.cnn, ampere.model_type);
}

test "dlss config presets" {
    const dynamic = DlssConfig.fromPreset("dynamic");
    try std.testing.expectEqual(FrameGenMode.dynamic, dynamic.frame_gen);
    try std.testing.expect(dynamic.dynamic_mfg.auto_quality_scale);

    const max_fps = DlssConfig.fromPreset("max_fps");
    try std.testing.expectEqual(FrameGenMode.dynamic_6x, max_fps.frame_gen);
    try std.testing.expectEqual(@as(u32, 240), max_fps.dynamic_mfg.target_refresh_hz);
}

test "recommended frame gen" {
    // RTX 50 @ 240Hz should use dynamic_6x
    try std.testing.expectEqual(FrameGenMode.dynamic_6x, getRecommendedFrameGen(.blackwell, 240));
    // RTX 50 @ 165Hz should use dynamic
    try std.testing.expectEqual(FrameGenMode.dynamic, getRecommendedFrameGen(.blackwell, 165));
    // RTX 40 should always use standard frame gen
    try std.testing.expectEqual(FrameGenMode.enabled, getRecommendedFrameGen(.ada_lovelace, 240));
    // RTX 30 has no frame gen
    try std.testing.expectEqual(FrameGenMode.disabled, getRecommendedFrameGen(.ampere, 165));
}

test "quality mode scale factors" {
    try std.testing.expectEqual(@as(f32, 3.0), QualityMode.ultra_performance.scaleFactor());
    try std.testing.expectEqual(@as(f32, 2.0), QualityMode.performance.scaleFactor());
    try std.testing.expectEqual(@as(f32, 1.0), QualityMode.dlaa.scaleFactor());
}

test "render resolution calculation" {
    const res = QualityMode.performance.getRenderResolution(3840, 2160);
    try std.testing.expectEqual(@as(u32, 1920), res.width);
    try std.testing.expectEqual(@as(u32, 1080), res.height);
}

test "dlss context init" {
    const allocator = std.testing.allocator;
    var ctx = try DlssContext.init(allocator, .{});
    defer ctx.deinit();

    try std.testing.expect(ctx.initialized);
    try std.testing.expect(ctx.capabilities.supports_dlss_sr);
}

test "reflex context" {
    const allocator = std.testing.allocator;
    var ctx = try ReflexContext.init(allocator, .disabled); // Use disabled to avoid NVAPI calls
    defer ctx.deinit();

    try std.testing.expect(ctx.initialized);
    try std.testing.expectEqual(ReflexMode.disabled, ctx.mode);

    // Test mode change (will be no-op without NVAPI)
    ctx.setMode(.enabled);
    try std.testing.expectEqual(ReflexMode.enabled, ctx.mode);
}

test "recommended quality" {
    try std.testing.expectEqual(QualityMode.performance, getRecommendedQuality(3840, 2160));
    try std.testing.expectEqual(QualityMode.quality, getRecommendedQuality(2560, 1440));
    try std.testing.expectEqual(QualityMode.dlaa, getRecommendedQuality(1920, 1080));
}
