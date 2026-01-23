//! nvdlss C API exports
//!
//! Provides C ABI-compatible functions for DLSS, Frame Generation,
//! and Reflex low-latency control.

const std = @import("std");
const nvprime = @import("nvprime");
const nvdlss = nvprime.nvdlss;

// ============================================================================
// C-compatible enums
// ============================================================================

/// C-compatible DLSS quality mode
pub const NvDlssQuality = enum(c_int) {
    ultra_performance = 0,
    performance = 1,
    balanced = 2,
    quality = 3,
    ultra_quality = 4,
    dlaa = 5,
};

/// C-compatible DLSS mode
pub const NvDlssMode = enum(c_int) {
    disabled = 0,
    super_resolution = 1,
    frame_generation = 2,
    ray_reconstruction = 3,
    multi_frame_gen = 4,
};

/// C-compatible frame generation mode
pub const NvFrameGenMode = enum(c_int) {
    disabled = 0,
    enabled = 1,
    boost = 2,
    multi_2x = 3,
    multi_3x = 4,
    multi_4x = 5,
    dynamic = 6,
    dynamic_6x = 7,
};

/// C-compatible GPU generation
pub const NvGpuGeneration = enum(c_int) {
    unknown = 0,
    turing = 1,
    ampere = 2,
    ada_lovelace = 3,
    blackwell = 4,
};

/// C-compatible Reflex mode
pub const NvReflexMode = enum(c_int) {
    disabled = 0,
    enabled = 1,
    boost = 2,
};

// ============================================================================
// C-compatible structures
// ============================================================================

/// C-compatible DLSS version info
pub const NvDlssVersion = extern struct {
    major: u32,
    minor: u32,
    patch: u32,
    build: u32,
};

/// C-compatible GPU capabilities
pub const NvDlssCapabilities = extern struct {
    supports_dlss_sr: bool,
    supports_dlss_fg: bool,
    supports_dlss_rr: bool,
    supports_dlss_mfg: bool,
    supports_dynamic_mfg: bool,
    supports_reflex: bool,
    supports_video_sr: bool,
    supports_video_hdr: bool,
    supports_rtx_hdr: bool,
    max_render_width: u32,
    max_render_height: u32,
    gpu_generation: NvGpuGeneration,
    tensor_core_gen: u8,
    driver_version: u32,
};

/// C-compatible DLSS configuration
pub const NvDlssConfig = extern struct {
    mode: NvDlssMode,
    quality: NvDlssQuality,
    frame_gen: NvFrameGenMode,
    ray_reconstruction: bool,
    sharpness: f32,
    auto_exposure: bool,
    hdr: bool,
};

/// C-compatible render resolution
pub const NvRenderResolution = extern struct {
    width: u32,
    height: u32,
};

/// C-compatible DLSS statistics
pub const NvDlssStats = extern struct {
    frames_upscaled: u64,
    frames_generated: u64,
    mode: NvDlssMode,
    quality: NvDlssQuality,
};

/// C-compatible Reflex statistics
pub const NvReflexStats = extern struct {
    total_latency_us: u64,
    game_latency_us: u64,
    render_latency_us: u64,
    driver_latency_us: u64,
    os_render_queue_us: u64,
    gpu_active_render_us: u64,
    frame_id: u64,
    pc_latency_available: bool,
};

// ============================================================================
// C ABI Exports - DLSS
// ============================================================================

/// Check if DLSS is available on this system
export fn nvdlss_is_available() bool {
    return nvdlss.isAvailable();
}

/// Get detected GPU generation
export fn nvdlss_get_gpu_generation() NvGpuGeneration {
    const gen = nvdlss.detectGpuGeneration();
    return switch (gen) {
        .unknown => .unknown,
        .turing => .turing,
        .ampere => .ampere,
        .ada_lovelace => .ada_lovelace,
        .blackwell => .blackwell,
    };
}

/// Get DLSS version
export fn nvdlss_get_version(out_version: *NvDlssVersion) c_int {
    const version = nvdlss.getVersion() orelse return -1;
    out_version.* = NvDlssVersion{
        .major = version.major,
        .minor = version.minor,
        .patch = version.patch,
        .build = version.build,
    };
    return 0;
}

/// Get GPU capabilities for DLSS features
export fn nvdlss_get_capabilities(out_caps: *NvDlssCapabilities) c_int {
    const caps = nvdlss.getCapabilities();
    out_caps.* = NvDlssCapabilities{
        .supports_dlss_sr = caps.supports_dlss_sr,
        .supports_dlss_fg = caps.supports_dlss_fg,
        .supports_dlss_rr = caps.supports_dlss_rr,
        .supports_dlss_mfg = caps.supports_dlss_mfg,
        .supports_dynamic_mfg = caps.supports_dynamic_mfg,
        .supports_reflex = caps.supports_reflex,
        .supports_video_sr = caps.supports_video_sr,
        .supports_video_hdr = caps.supports_video_hdr,
        .supports_rtx_hdr = caps.supports_rtx_hdr,
        .max_render_width = caps.max_render_width,
        .max_render_height = caps.max_render_height,
        .gpu_generation = switch (caps.gpu_generation) {
            .unknown => .unknown,
            .turing => .turing,
            .ampere => .ampere,
            .ada_lovelace => .ada_lovelace,
            .blackwell => .blackwell,
        },
        .tensor_core_gen = caps.tensor_core_gen,
        .driver_version = caps.driver_version,
    };
    return 0;
}

/// Check if super resolution is supported
export fn nvdlss_supports_sr() bool {
    const caps = nvdlss.getCapabilities();
    return caps.supports_dlss_sr;
}

/// Check if frame generation is supported
export fn nvdlss_supports_frame_gen() bool {
    const caps = nvdlss.getCapabilities();
    return caps.supports_dlss_fg;
}

/// Check if multi-frame generation is supported (RTX 50+)
export fn nvdlss_supports_multi_frame_gen() bool {
    const caps = nvdlss.getCapabilities();
    return caps.supports_dlss_mfg;
}

/// Check if dynamic MFG is supported (RTX 50+ with DLSS 4.5+)
export fn nvdlss_supports_dynamic_mfg() bool {
    const caps = nvdlss.getCapabilities();
    return caps.supports_dynamic_mfg;
}

/// Check if ray reconstruction is supported
export fn nvdlss_supports_ray_reconstruction() bool {
    const caps = nvdlss.getCapabilities();
    return caps.supports_dlss_rr;
}

/// Get recommended quality mode for resolution
export fn nvdlss_get_recommended_quality(output_width: u32, output_height: u32) NvDlssQuality {
    const quality = nvdlss.getRecommendedQuality(output_width, output_height);
    return switch (quality) {
        .ultra_performance => .ultra_performance,
        .performance => .performance,
        .balanced => .balanced,
        .quality => .quality,
        .ultra_quality => .ultra_quality,
        .dlaa => .dlaa,
    };
}

/// Get recommended frame gen mode for GPU and refresh rate
export fn nvdlss_get_recommended_frame_gen(gpu_gen: NvGpuGeneration, target_refresh_hz: u32) NvFrameGenMode {
    const gen = switch (gpu_gen) {
        .unknown => nvdlss.GpuGeneration.unknown,
        .turing => nvdlss.GpuGeneration.turing,
        .ampere => nvdlss.GpuGeneration.ampere,
        .ada_lovelace => nvdlss.GpuGeneration.ada_lovelace,
        .blackwell => nvdlss.GpuGeneration.blackwell,
    };
    const mode = nvdlss.getRecommendedFrameGen(gen, target_refresh_hz);
    return switch (mode) {
        .disabled => .disabled,
        .enabled => .enabled,
        .boost => .boost,
        .multi_2x => .multi_2x,
        .multi_3x => .multi_3x,
        .multi_4x => .multi_4x,
        .dynamic => .dynamic,
        .dynamic_6x => .dynamic_6x,
    };
}

/// Calculate render resolution for quality mode
export fn nvdlss_get_render_resolution(quality: NvDlssQuality, output_width: u32, output_height: u32, out_res: *NvRenderResolution) c_int {
    const q = switch (quality) {
        .ultra_performance => nvdlss.QualityMode.ultra_performance,
        .performance => nvdlss.QualityMode.performance,
        .balanced => nvdlss.QualityMode.balanced,
        .quality => nvdlss.QualityMode.quality,
        .ultra_quality => nvdlss.QualityMode.ultra_quality,
        .dlaa => nvdlss.QualityMode.dlaa,
    };
    const res = q.getRenderResolution(output_width, output_height);
    out_res.* = NvRenderResolution{
        .width = res.width,
        .height = res.height,
    };
    return 0;
}

/// Get quality mode scale factor
export fn nvdlss_get_scale_factor(quality: NvDlssQuality) f32 {
    const q = switch (quality) {
        .ultra_performance => nvdlss.QualityMode.ultra_performance,
        .performance => nvdlss.QualityMode.performance,
        .balanced => nvdlss.QualityMode.balanced,
        .quality => nvdlss.QualityMode.quality,
        .ultra_quality => nvdlss.QualityMode.ultra_quality,
        .dlaa => nvdlss.QualityMode.dlaa,
    };
    return q.scaleFactor();
}

/// Get frame gen multiplier
export fn nvdlss_get_frame_gen_multiplier(mode: NvFrameGenMode) c_int {
    const m = switch (mode) {
        .disabled => nvdlss.FrameGenMode.disabled,
        .enabled => nvdlss.FrameGenMode.enabled,
        .boost => nvdlss.FrameGenMode.boost,
        .multi_2x => nvdlss.FrameGenMode.multi_2x,
        .multi_3x => nvdlss.FrameGenMode.multi_3x,
        .multi_4x => nvdlss.FrameGenMode.multi_4x,
        .dynamic => nvdlss.FrameGenMode.dynamic,
        .dynamic_6x => nvdlss.FrameGenMode.dynamic_6x,
    };
    return @intCast(m.multiplier());
}

/// Check if frame gen mode requires RTX 50
export fn nvdlss_frame_gen_requires_rtx50(mode: NvFrameGenMode) bool {
    const m = switch (mode) {
        .disabled => nvdlss.FrameGenMode.disabled,
        .enabled => nvdlss.FrameGenMode.enabled,
        .boost => nvdlss.FrameGenMode.boost,
        .multi_2x => nvdlss.FrameGenMode.multi_2x,
        .multi_3x => nvdlss.FrameGenMode.multi_3x,
        .multi_4x => nvdlss.FrameGenMode.multi_4x,
        .dynamic => nvdlss.FrameGenMode.dynamic,
        .dynamic_6x => nvdlss.FrameGenMode.dynamic_6x,
    };
    return m.requiresRtx50();
}

// ============================================================================
// C ABI Exports - Reflex
// ============================================================================

/// Check if Reflex low-latency is available
export fn nvreflex_is_available() bool {
    return nvdlss.isReflexAvailable();
}

/// Get Reflex latency in milliseconds (convenience function)
export fn nvreflex_get_latency_ms(stats: *const NvReflexStats) f32 {
    return @as(f32, @floatFromInt(stats.total_latency_us)) / 1000.0;
}
