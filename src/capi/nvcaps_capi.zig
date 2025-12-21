//! nvcaps C API exports
//!
//! Provides C ABI-compatible functions for capability discovery.

const std = @import("std");
const nvprime = @import("nvprime");
const nvcaps = nvprime.nvcaps;
const nvml = nvprime.nvml;

/// C-compatible GPU architecture enum
pub const NvArchitecture = enum(c_int) {
    unknown = 0,
    kepler = 1,
    maxwell = 2,
    pascal = 3,
    volta = 4,
    turing = 5,
    ampere = 6,
    ada_lovelace = 7,
    hopper = 8,
    blackwell = 9,
};

/// C-compatible GPU capabilities structure
pub const NvGpuCapabilities = extern struct {
    index: u32,
    name: [96]u8,
    uuid: [96]u8,
    architecture: NvArchitecture,
    compute_major: i32,
    compute_minor: i32,
    vram_total_mb: u64,
    vram_used_mb: u64,
    pcie_bus_id: [32]u8,
    pcie_gen: u32,
    pcie_width: u32,
    supports_rtx: bool,
    supports_dlss: bool,
    supports_dlss3: bool,
    supports_reflex: bool,
    supports_nvenc: bool,
    supports_power_management: bool,
    supports_clock_control: bool,
    supports_fan_control: bool,
    temperature_c: u32,
    power_draw_w: f32,
    power_limit_w: f32,
    gpu_clock_mhz: u32,
    mem_clock_mhz: u32,
    pstate: u32,
};

/// C-compatible system summary
pub const NvSystemSummary = extern struct {
    gpu_count: u32,
    total_vram_mb: u64,
    best_architecture: NvArchitecture,
    all_support_rtx: bool,
    all_support_dlss: bool,
    primary_gpu_index: u32,
};

fn archToC(arch: nvcaps.Architecture) NvArchitecture {
    return switch (arch) {
        .unknown => .unknown,
        .kepler => .kepler,
        .maxwell => .maxwell,
        .pascal => .pascal,
        .volta => .volta,
        .turing => .turing,
        .ampere => .ampere,
        .ada_lovelace => .ada_lovelace,
        .hopper => .hopper,
        .blackwell => .blackwell,
    };
}

fn capsToC(caps: nvcaps.GpuCapabilities) NvGpuCapabilities {
    return NvGpuCapabilities{
        .index = caps.index,
        .name = caps.name,
        .uuid = caps.uuid,
        .architecture = archToC(caps.architecture),
        .compute_major = caps.compute_capability.major,
        .compute_minor = caps.compute_capability.minor,
        .vram_total_mb = caps.vram_total_mb,
        .vram_used_mb = caps.vram_used_mb,
        .pcie_bus_id = caps.pcie_bus_id,
        .pcie_gen = caps.pcie_gen,
        .pcie_width = caps.pcie_width,
        .supports_rtx = caps.supports_rtx,
        .supports_dlss = caps.supports_dlss,
        .supports_dlss3 = caps.supports_dlss3,
        .supports_reflex = caps.supports_reflex,
        .supports_nvenc = caps.supports_nvenc,
        .supports_power_management = caps.supports_power_management,
        .supports_clock_control = caps.supports_clock_control,
        .supports_fan_control = caps.supports_fan_control,
        .temperature_c = caps.temperature_c,
        .power_draw_w = caps.power_draw_w,
        .power_limit_w = caps.power_limit_w,
        .gpu_clock_mhz = caps.gpu_clock_mhz,
        .mem_clock_mhz = caps.mem_clock_mhz,
        .pstate = caps.pstate,
    };
}

// ============================================================================
// C ABI Exports
// ============================================================================

/// Initialize nvprime library
export fn nvprime_init() c_int {
    nvml.init() catch return -1;
    nvcaps.init() catch return -2;
    return 0;
}

/// Shutdown nvprime library
export fn nvprime_shutdown() void {
    nvcaps.deinit();
    nvml.shutdown();
}

/// Get number of detected GPUs
export fn nvprime_get_gpu_count() c_int {
    const count = nvml.getDeviceCount() catch return -1;
    return @intCast(count);
}

/// Get capabilities for a specific GPU
export fn nvprime_get_gpu_caps(index: u32, out_caps: *NvGpuCapabilities) c_int {
    const caps = nvcaps.getGpuCapabilities(index) catch return -1;
    out_caps.* = capsToC(caps);
    return 0;
}

/// Check if GPU supports a specific feature
export fn nvprime_gpu_supports_rtx(index: u32) bool {
    const caps = nvcaps.getGpuCapabilities(index) catch return false;
    return caps.supports_rtx;
}

export fn nvprime_gpu_supports_dlss(index: u32) bool {
    const caps = nvcaps.getGpuCapabilities(index) catch return false;
    return caps.supports_dlss;
}

export fn nvprime_gpu_supports_dlss3(index: u32) bool {
    const caps = nvcaps.getGpuCapabilities(index) catch return false;
    return caps.supports_dlss3;
}

export fn nvprime_gpu_supports_reflex(index: u32) bool {
    const caps = nvcaps.getGpuCapabilities(index) catch return false;
    return caps.supports_reflex;
}

export fn nvprime_gpu_supports_nvenc(index: u32) bool {
    const caps = nvcaps.getGpuCapabilities(index) catch return false;
    return caps.supports_nvenc;
}

/// Get GPU temperature in Celsius
export fn nvprime_get_gpu_temperature(index: u32) c_int {
    const device = nvml.getDeviceByIndex(index) catch return -1;
    const temp = nvml.getDeviceTemperature(device, nvml.TEMPERATURE_GPU) catch return -1;
    return @intCast(temp);
}

/// Get GPU power usage in milliwatts
export fn nvprime_get_gpu_power_usage(index: u32) c_int {
    const device = nvml.getDeviceByIndex(index) catch return -1;
    const power = nvml.getDevicePowerUsage(device) catch return -1;
    return @intCast(power);
}

/// Get GPU clock speed in MHz
export fn nvprime_get_gpu_clock(index: u32) c_int {
    const device = nvml.getDeviceByIndex(index) catch return -1;
    const clock = nvml.getDeviceClock(device, nvml.CLOCK_GRAPHICS) catch return -1;
    return @intCast(clock);
}

/// Get memory clock speed in MHz
export fn nvprime_get_mem_clock(index: u32) c_int {
    const device = nvml.getDeviceByIndex(index) catch return -1;
    const clock = nvml.getDeviceClock(device, nvml.CLOCK_MEM) catch return -1;
    return @intCast(clock);
}

/// Get GPU name (copies to buffer, returns bytes written or -1 on error)
export fn nvprime_get_gpu_name(index: u32, buffer: [*]u8, buffer_size: usize) c_int {
    const caps = nvcaps.getGpuCapabilities(index) catch return -1;
    const name = std.mem.sliceTo(&caps.name, 0);
    const copy_len = @min(name.len, buffer_size - 1);
    @memcpy(buffer[0..copy_len], name[0..copy_len]);
    buffer[copy_len] = 0;
    return @intCast(copy_len);
}

/// Get GPU architecture name (returns static string pointer)
export fn nvprime_get_arch_name(arch: NvArchitecture) [*:0]const u8 {
    return switch (arch) {
        .unknown => "Unknown",
        .kepler => "Kepler",
        .maxwell => "Maxwell",
        .pascal => "Pascal",
        .volta => "Volta",
        .turing => "Turing",
        .ampere => "Ampere",
        .ada_lovelace => "Ada Lovelace",
        .hopper => "Hopper",
        .blackwell => "Blackwell",
    };
}

/// Get VRAM total in megabytes
export fn nvprime_get_vram_total(index: u32) u64 {
    const caps = nvcaps.getGpuCapabilities(index) catch return 0;
    return caps.vram_total_mb;
}

/// Get VRAM used in megabytes
export fn nvprime_get_vram_used(index: u32) u64 {
    const device = nvml.getDeviceByIndex(index) catch return 0;
    const memory = nvml.getDeviceMemoryInfo(device) catch return 0;
    return memory.used / (1024 * 1024);
}

/// Get GPU performance state (P-state, 0-15)
export fn nvprime_get_pstate(index: u32) c_int {
    const device = nvml.getDeviceByIndex(index) catch return -1;
    const pstate = nvml.getDevicePerformanceState(device) catch return -1;
    return @intCast(pstate);
}
