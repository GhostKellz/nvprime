//! nvcaps - NVIDIA Capability Discovery
//!
//! Hardware detection, capability profiling, and feature availability checking.
//! This is the foundation that other subsystems query to understand what the GPU supports.

const std = @import("std");
const nvml = @import("../bindings/nvml.zig");

/// GPU Architecture generations
pub const Architecture = enum {
    unknown,
    kepler, // GK1xx - Compute 3.x
    maxwell, // GM1xx/GM2xx - Compute 5.x
    pascal, // GP1xx - Compute 6.x
    volta, // GV1xx - Compute 7.0
    turing, // TU1xx - Compute 7.5
    ampere, // GA1xx - Compute 8.x
    ada_lovelace, // AD1xx - Compute 8.9
    hopper, // GH1xx - Compute 9.0
    blackwell, // GB1xx - Compute 10.x

    pub fn fromComputeCapability(major: i32, minor: i32) Architecture {
        return switch (major) {
            3 => .kepler,
            5 => .maxwell,
            6 => .pascal,
            7 => if (minor >= 5) .turing else .volta,
            8 => if (minor >= 9) .ada_lovelace else .ampere,
            9 => .hopper,
            10, 11, 12 => .blackwell, // Blackwell covers compute 10.x-12.x
            else => .unknown,
        };
    }

    pub fn supportsRtx(self: Architecture) bool {
        return switch (self) {
            .turing, .ampere, .ada_lovelace, .hopper, .blackwell => true,
            else => false,
        };
    }

    pub fn supportsDlss(self: Architecture) bool {
        return switch (self) {
            .turing, .ampere, .ada_lovelace, .hopper, .blackwell => true,
            else => false,
        };
    }

    pub fn supportsDlss3(self: Architecture) bool {
        return switch (self) {
            .ada_lovelace, .hopper, .blackwell => true,
            else => false,
        };
    }

    pub fn supportsReflex(self: Architecture) bool {
        return switch (self) {
            .pascal, .volta, .turing, .ampere, .ada_lovelace, .hopper, .blackwell => true,
            else => false,
        };
    }

    pub fn supportsNvenc(self: Architecture) bool {
        return switch (self) {
            .kepler, .maxwell, .pascal, .volta, .turing, .ampere, .ada_lovelace, .hopper, .blackwell => true,
            else => false,
        };
    }
};

/// GPU capability profile
pub const GpuCapabilities = struct {
    // Identity
    index: u32,
    name: [96]u8,
    uuid: [96]u8,
    architecture: Architecture,
    compute_capability: struct { major: i32, minor: i32 },

    // Memory
    vram_total_mb: u64,
    vram_used_mb: u64,

    // PCIe
    pcie_bus_id: [32]u8,
    pcie_gen: u32,
    pcie_width: u32,

    // Feature support
    supports_rtx: bool,
    supports_dlss: bool,
    supports_dlss3: bool,
    supports_reflex: bool,
    supports_nvenc: bool,
    supports_power_management: bool,
    supports_clock_control: bool,
    supports_fan_control: bool,

    // Current state
    temperature_c: u32,
    power_draw_w: f32,
    power_limit_w: f32,
    gpu_clock_mhz: u32,
    mem_clock_mhz: u32,
    pstate: u32,

    pub fn print(self: GpuCapabilities, writer: anytype) !void {
        try writer.print("GPU {d}: {s}\n", .{ self.index, std.mem.sliceTo(&self.name, 0) });
        try writer.print("  Architecture: {s}\n", .{@tagName(self.architecture)});
        try writer.print("  VRAM: {d} MB / {d} MB\n", .{ self.vram_used_mb, self.vram_total_mb });
        try writer.print("  PCIe: {s} Gen{d} x{d}\n", .{ std.mem.sliceTo(&self.pcie_bus_id, 0), self.pcie_gen, self.pcie_width });
        try writer.print("  Features: RTX={} DLSS={} DLSS3={} Reflex={}\n", .{
            self.supports_rtx,
            self.supports_dlss,
            self.supports_dlss3,
            self.supports_reflex,
        });
        try writer.print("  State: {d}C, {d:.1}W/{d:.1}W, GPU {d}MHz, MEM {d}MHz, P{d}\n", .{
            self.temperature_c,
            self.power_draw_w,
            self.power_limit_w,
            self.gpu_clock_mhz,
            self.mem_clock_mhz,
            self.pstate,
        });
    }
};

/// Profile type for optimized defaults
pub const Profile = enum {
    gaming,
    workstation,
    ai_compute,
    streaming,
    efficiency,

    pub fn description(self: Profile) []const u8 {
        return switch (self) {
            .gaming => "Optimized for low latency gaming with Reflex/VRR",
            .workstation => "Balanced performance for professional workloads",
            .ai_compute => "Maximum compute throughput for AI/ML",
            .streaming => "Optimized NVENC encoding for game streaming",
            .efficiency => "Power-saving mode for light workloads",
        };
    }
};

/// Cached GPU data
var gpu_cache: ?[]GpuCapabilities = null;
var allocator: ?std.mem.Allocator = null;

/// Initialize nvcaps subsystem
pub fn init() !void {
    // nvcaps currently relies on NVML being initialized by the caller
}

/// Deinitialize nvcaps subsystem
pub fn deinit() void {
    if (gpu_cache) |cache| {
        if (allocator) |alloc| {
            alloc.free(cache);
        }
    }
    gpu_cache = null;
    allocator = null;
}

/// Detect all GPUs and return their capabilities
pub fn detectGpus(alloc: std.mem.Allocator) ![]GpuCapabilities {
    const count = try nvml.getDeviceCount();
    var gpus = try alloc.alloc(GpuCapabilities, count);
    errdefer alloc.free(gpus);

    for (0..count) |i| {
        gpus[i] = try getGpuCapabilities(@intCast(i));
    }

    // Cache the results
    if (gpu_cache) |old_cache| {
        if (allocator) |old_alloc| {
            old_alloc.free(old_cache);
        }
    }
    gpu_cache = gpus;
    allocator = alloc;

    return gpus;
}

/// Get capabilities for a specific GPU
pub fn getGpuCapabilities(index: u32) !GpuCapabilities {
    const device = try nvml.getDeviceByIndex(index);

    const name = try nvml.getDeviceName(device);
    const uuid = try nvml.getDeviceUuid(device);
    const pci = try nvml.getDevicePciInfo(device);
    const memory = try nvml.getDeviceMemoryInfo(device);
    const compute = try nvml.getDeviceCudaComputeCapability(device);

    const arch = Architecture.fromComputeCapability(compute.major, compute.minor);

    // Get current state (may fail on some GPUs)
    const temp = nvml.getDeviceTemperature(device, nvml.TEMPERATURE_GPU) catch 0;
    const power = nvml.getDevicePowerUsage(device) catch 0;
    const power_limit = nvml.getDevicePowerLimit(device) catch 0;
    const gpu_clock = nvml.getDeviceClock(device, nvml.CLOCK_GRAPHICS) catch 0;
    const mem_clock = nvml.getDeviceClock(device, nvml.CLOCK_MEM) catch 0;
    const pstate = nvml.getDevicePerformanceState(device) catch @as(c_uint, 15);

    // Build PCI bus ID string
    var pcie_bus_id: [32]u8 = [_]u8{0} ** 32;
    const pcie_str = std.fmt.bufPrint(&pcie_bus_id, "{x:0>4}:{x:0>2}:{x:0>2}.{d}", .{
        pci.domain,
        pci.bus,
        pci.device,
        0, // function
    }) catch "unknown";
    // Null-terminate after the formatted string
    if (pcie_str.len < 32) {
        pcie_bus_id[pcie_str.len] = 0;
    }

    return GpuCapabilities{
        .index = index,
        .name = name,
        .uuid = uuid,
        .architecture = arch,
        .compute_capability = .{ .major = compute.major, .minor = compute.minor },
        .vram_total_mb = memory.total / (1024 * 1024),
        .vram_used_mb = memory.used / (1024 * 1024),
        .pcie_bus_id = pcie_bus_id,
        .pcie_gen = 0, // Would need additional NVML calls
        .pcie_width = 0,
        .supports_rtx = arch.supportsRtx(),
        .supports_dlss = arch.supportsDlss(),
        .supports_dlss3 = arch.supportsDlss3(),
        .supports_reflex = arch.supportsReflex(),
        .supports_nvenc = arch.supportsNvenc(),
        .supports_power_management = nvml.isFeatureSupported(device, .power_management),
        .supports_clock_control = nvml.isFeatureSupported(device, .clock_control),
        .supports_fan_control = nvml.isFeatureSupported(device, .fan_control),
        .temperature_c = temp,
        .power_draw_w = @as(f32, @floatFromInt(power)) / 1000.0,
        .power_limit_w = @as(f32, @floatFromInt(power_limit)) / 1000.0,
        .gpu_clock_mhz = gpu_clock,
        .mem_clock_mhz = mem_clock,
        .pstate = @intCast(pstate),
    };
}

/// Get recommended profile based on GPU capabilities
pub fn getRecommendedProfile(caps: GpuCapabilities) Profile {
    if (caps.supports_dlss3 and caps.vram_total_mb >= 12000) {
        return .gaming; // High-end gaming GPU
    } else if (caps.vram_total_mb >= 24000) {
        return .ai_compute; // Likely a workstation/compute card
    } else if (caps.supports_nvenc and caps.supports_reflex) {
        return .streaming; // Good for streaming
    } else if (caps.architecture == .unknown or !caps.supports_rtx) {
        return .efficiency; // Older or limited GPU
    } else {
        return .workstation; // Default balanced profile
    }
}

/// Check if a specific feature is available
pub fn isFeatureAvailable(caps: GpuCapabilities, feature: []const u8) bool {
    if (std.mem.eql(u8, feature, "rtx")) return caps.supports_rtx;
    if (std.mem.eql(u8, feature, "dlss")) return caps.supports_dlss;
    if (std.mem.eql(u8, feature, "dlss3")) return caps.supports_dlss3;
    if (std.mem.eql(u8, feature, "reflex")) return caps.supports_reflex;
    if (std.mem.eql(u8, feature, "nvenc")) return caps.supports_nvenc;
    if (std.mem.eql(u8, feature, "power_management")) return caps.supports_power_management;
    if (std.mem.eql(u8, feature, "clock_control")) return caps.supports_clock_control;
    if (std.mem.eql(u8, feature, "fan_control")) return caps.supports_fan_control;
    return false;
}

/// Get system-wide GPU summary
pub const SystemSummary = struct {
    gpu_count: u32,
    total_vram_mb: u64,
    best_architecture: Architecture,
    all_support_rtx: bool,
    all_support_dlss: bool,
    primary_gpu_index: u32,
};

pub fn getSystemSummary(gpus: []const GpuCapabilities) SystemSummary {
    var summary = SystemSummary{
        .gpu_count = @intCast(gpus.len),
        .total_vram_mb = 0,
        .best_architecture = .unknown,
        .all_support_rtx = true,
        .all_support_dlss = true,
        .primary_gpu_index = 0,
    };

    var best_vram: u64 = 0;

    for (gpus, 0..) |gpu, i| {
        summary.total_vram_mb += gpu.vram_total_mb;

        if (@intFromEnum(gpu.architecture) > @intFromEnum(summary.best_architecture)) {
            summary.best_architecture = gpu.architecture;
        }

        if (!gpu.supports_rtx) summary.all_support_rtx = false;
        if (!gpu.supports_dlss) summary.all_support_dlss = false;

        // Primary GPU is the one with most VRAM
        if (gpu.vram_total_mb > best_vram) {
            best_vram = gpu.vram_total_mb;
            summary.primary_gpu_index = @intCast(i);
        }
    }

    return summary;
}

test "architecture detection" {
    try std.testing.expectEqual(Architecture.turing, Architecture.fromComputeCapability(7, 5));
    try std.testing.expectEqual(Architecture.ampere, Architecture.fromComputeCapability(8, 6));
    try std.testing.expectEqual(Architecture.ada_lovelace, Architecture.fromComputeCapability(8, 9));
    try std.testing.expect(Architecture.ada_lovelace.supportsDlss3());
    try std.testing.expect(!Architecture.ampere.supportsDlss3());
}
