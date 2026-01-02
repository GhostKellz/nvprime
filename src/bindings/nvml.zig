//! NVML (NVIDIA Management Library) Bindings
//!
//! Low-level Zig bindings to libnvidia-ml for GPU management.
//! This provides the foundation for nvcaps, nvcore, nvpower, and nvdisplay.
//!
//! When built with -Dnvml=false, stub implementations are provided.

const std = @import("std");
const build_options = @import("build_options");

const use_nvml = build_options.use_nvml;

// Only include NVML headers when enabled
const c = if (use_nvml) @cImport({
    @cInclude("nvml.h");
}) else struct {
    // Stub types when NVML not available
    pub const nvmlReturn_t = i32;
    pub const nvmlDevice_t = *anyopaque;
    pub const nvmlPciInfo_t = extern struct {
        busIdLegacy: [16]u8 = undefined,
        domain: u32 = 0,
        bus: u32 = 0,
        device: u32 = 0,
        pciDeviceId: u32 = 0,
        pciSubSystemId: u32 = 0,
        busId: [32]u8 = undefined,
    };
    pub const nvmlMemory_t = extern struct { total: u64 = 0, free: u64 = 0, used: u64 = 0 };
    pub const nvmlUtilization_t = extern struct { gpu: u32 = 0, memory: u32 = 0 };
    pub const nvmlPstates_t = i32;
    pub const nvmlClockType_t = i32;
    pub const nvmlTemperatureSensors_t = i32;
    pub const nvmlDeviceArchitecture_t = i32;
    pub const NVML_SUCCESS: i32 = 0;
    pub const NVML_CLOCK_GRAPHICS: i32 = 0;
    pub const NVML_CLOCK_SM: i32 = 1;
    pub const NVML_CLOCK_MEM: i32 = 2;
    pub const NVML_CLOCK_VIDEO: i32 = 3;
    pub const NVML_TEMPERATURE_GPU: i32 = 0;
    pub const NVML_PSTATE_0: i32 = 0;
    pub const NVML_PSTATE_1: i32 = 1;
    pub const NVML_PSTATE_2: i32 = 2;
    pub const NVML_PSTATE_3: i32 = 3;
    pub const NVML_PSTATE_8: i32 = 8;
    pub const NVML_PSTATE_15: i32 = 15;
};

pub const NvmlError = error{
    Uninitialized,
    InvalidArgument,
    NotSupported,
    NoPermission,
    NotFound,
    InsufficientSize,
    InsufficientPower,
    DriverNotLoaded,
    Timeout,
    IrqIssue,
    LibraryNotFound,
    FunctionNotFound,
    CorruptedInfoROM,
    GpuIsLost,
    ResetRequired,
    OperatingSystem,
    LibRmVersionMismatch,
    InUse,
    Memory,
    NoData,
    VgpuEccNotSupported,
    InsufficientResources,
    FreqNotSupported,
    Unknown,
    NvmlNotAvailable,
};

fn mapNvmlReturn(ret: c.nvmlReturn_t) NvmlError!void {
    if (!use_nvml) return error.NvmlNotAvailable;
    return switch (ret) {
        c.NVML_SUCCESS => {},
        else => error.Unknown,
    };
}

// Type aliases for cleaner API
pub const Device = c.nvmlDevice_t;
pub const PciInfo = c.nvmlPciInfo_t;
pub const Memory = c.nvmlMemory_t;
pub const Utilization = c.nvmlUtilization_t;
pub const PStates = c.nvmlPstates_t;
pub const ClockType = c.nvmlClockType_t;
pub const TemperatureSensors = c.nvmlTemperatureSensors_t;

// Clock type constants
pub const CLOCK_GRAPHICS = c.NVML_CLOCK_GRAPHICS;
pub const CLOCK_SM = c.NVML_CLOCK_SM;
pub const CLOCK_MEM = c.NVML_CLOCK_MEM;
pub const CLOCK_VIDEO = c.NVML_CLOCK_VIDEO;

// Temperature sensor constants
pub const TEMPERATURE_GPU = c.NVML_TEMPERATURE_GPU;

// P-state constants
pub const PSTATE_0 = c.NVML_PSTATE_0;
pub const PSTATE_1 = c.NVML_PSTATE_1;
pub const PSTATE_2 = c.NVML_PSTATE_2;
pub const PSTATE_3 = c.NVML_PSTATE_3;
pub const PSTATE_8 = c.NVML_PSTATE_8;
pub const PSTATE_15 = c.NVML_PSTATE_15;

// State tracking
var initialized = false;

/// Check if NVML is available at compile time
pub fn isAvailable() bool {
    return use_nvml;
}

/// Initialize NVML library
pub fn init() NvmlError!void {
    if (!use_nvml) return error.NvmlNotAvailable;
    if (initialized) return;
    try mapNvmlReturn(c.nvmlInit_v2());
    initialized = true;
}

/// Shutdown NVML library
pub fn shutdown() void {
    if (!use_nvml) return;
    if (!initialized) return;
    _ = c.nvmlShutdown();
    initialized = false;
}

/// Get NVML driver version string
pub fn getDriverVersion() NvmlError![80]u8 {
    if (!use_nvml) return error.NvmlNotAvailable;
    var version: [80]u8 = undefined;
    try mapNvmlReturn(c.nvmlSystemGetDriverVersion(&version, version.len));
    return version;
}

/// Get NVML library version string
pub fn getNvmlVersion() NvmlError![80]u8 {
    if (!use_nvml) return error.NvmlNotAvailable;
    var version: [80]u8 = undefined;
    try mapNvmlReturn(c.nvmlSystemGetNVMLVersion(&version, version.len));
    return version;
}

/// Get number of GPU devices
pub fn getDeviceCount() NvmlError!u32 {
    if (!use_nvml) return error.NvmlNotAvailable;
    var count: c_uint = 0;
    try mapNvmlReturn(c.nvmlDeviceGetCount_v2(&count));
    return count;
}

/// Get device handle by index
pub fn getDeviceByIndex(index: u32) NvmlError!Device {
    if (!use_nvml) return error.NvmlNotAvailable;
    var device: Device = undefined;
    try mapNvmlReturn(c.nvmlDeviceGetHandleByIndex_v2(index, &device));
    return device;
}

/// Get device name
pub fn getDeviceName(device: Device) NvmlError![96]u8 {
    if (!use_nvml) return error.NvmlNotAvailable;
    var name: [96]u8 = undefined;
    try mapNvmlReturn(c.nvmlDeviceGetName(device, &name, name.len));
    return name;
}

/// Get device UUID
pub fn getDeviceUuid(device: Device) NvmlError![96]u8 {
    if (!use_nvml) return error.NvmlNotAvailable;
    var uuid: [96]u8 = undefined;
    try mapNvmlReturn(c.nvmlDeviceGetUUID(device, &uuid, uuid.len));
    return uuid;
}

/// Get device PCI info
pub fn getDevicePciInfo(device: Device) NvmlError!PciInfo {
    if (!use_nvml) return error.NvmlNotAvailable;
    var pci: PciInfo = undefined;
    try mapNvmlReturn(c.nvmlDeviceGetPciInfo_v3(device, &pci));
    return pci;
}

/// Get device memory info
pub fn getDeviceMemoryInfo(device: Device) NvmlError!Memory {
    if (!use_nvml) return error.NvmlNotAvailable;
    var memory: Memory = undefined;
    try mapNvmlReturn(c.nvmlDeviceGetMemoryInfo(device, &memory));
    return memory;
}

/// Get device utilization rates
pub fn getDeviceUtilization(device: Device) NvmlError!Utilization {
    if (!use_nvml) return error.NvmlNotAvailable;
    var util: Utilization = undefined;
    try mapNvmlReturn(c.nvmlDeviceGetUtilizationRates(device, &util));
    return util;
}

/// Get current GPU clock speed (MHz)
pub fn getDeviceClock(device: Device, clock_type: ClockType) NvmlError!u32 {
    if (!use_nvml) return error.NvmlNotAvailable;
    var clock: c_uint = 0;
    try mapNvmlReturn(c.nvmlDeviceGetClockInfo(device, clock_type, &clock));
    return clock;
}

/// Get max GPU clock speed (MHz)
pub fn getDeviceMaxClock(device: Device, clock_type: ClockType) NvmlError!u32 {
    if (!use_nvml) return error.NvmlNotAvailable;
    var clock: c_uint = 0;
    try mapNvmlReturn(c.nvmlDeviceGetMaxClockInfo(device, clock_type, &clock));
    return clock;
}

/// Get current performance state (P-state)
pub fn getDevicePerformanceState(device: Device) NvmlError!PStates {
    if (!use_nvml) return error.NvmlNotAvailable;
    var pstate: PStates = undefined;
    try mapNvmlReturn(c.nvmlDeviceGetPerformanceState(device, &pstate));
    return pstate;
}

/// Get GPU temperature
pub fn getDeviceTemperature(device: Device, sensor: TemperatureSensors) NvmlError!u32 {
    if (!use_nvml) return error.NvmlNotAvailable;
    var temp: c_uint = 0;
    try mapNvmlReturn(c.nvmlDeviceGetTemperature(device, sensor, &temp));
    return temp;
}

/// Get GPU power usage (milliwatts)
pub fn getDevicePowerUsage(device: Device) NvmlError!u32 {
    if (!use_nvml) return error.NvmlNotAvailable;
    var power: c_uint = 0;
    try mapNvmlReturn(c.nvmlDeviceGetPowerUsage(device, &power));
    return power;
}

/// Get GPU power limit (milliwatts)
pub fn getDevicePowerLimit(device: Device) NvmlError!u32 {
    if (!use_nvml) return error.NvmlNotAvailable;
    var limit: c_uint = 0;
    try mapNvmlReturn(c.nvmlDeviceGetPowerManagementLimit(device, &limit));
    return limit;
}

/// Set GPU power limit (milliwatts) - requires root
pub fn setDevicePowerLimit(device: Device, limit: u32) NvmlError!void {
    if (!use_nvml) return error.NvmlNotAvailable;
    try mapNvmlReturn(c.nvmlDeviceSetPowerManagementLimit(device, limit));
}

/// Get fan speed percentage
pub fn getDeviceFanSpeed(device: Device) NvmlError!u32 {
    if (!use_nvml) return error.NvmlNotAvailable;
    var speed: c_uint = 0;
    try mapNvmlReturn(c.nvmlDeviceGetFanSpeed(device, &speed));
    return speed;
}

/// Get CUDA compute capability
pub fn getDeviceCudaComputeCapability(device: Device) NvmlError!struct { major: i32, minor: i32 } {
    if (!use_nvml) return error.NvmlNotAvailable;
    var major: c_int = 0;
    var minor: c_int = 0;
    try mapNvmlReturn(c.nvmlDeviceGetCudaComputeCapability(device, &major, &minor));
    return .{ .major = major, .minor = minor };
}

/// Get device architecture
pub fn getDeviceArchitecture(device: Device) NvmlError!c.nvmlDeviceArchitecture_t {
    if (!use_nvml) return error.NvmlNotAvailable;
    var arch: c.nvmlDeviceArchitecture_t = undefined;
    try mapNvmlReturn(c.nvmlDeviceGetArchitecture(device, &arch));
    return arch;
}

/// Check if device supports a given feature
pub const FeatureQuery = enum {
    power_management,
    clock_control,
    fan_control,
};

pub fn isFeatureSupported(device: Device, feature: FeatureQuery) bool {
    if (!use_nvml) return false;
    switch (feature) {
        .power_management => {
            var limit: c_uint = 0;
            return c.nvmlDeviceGetPowerManagementLimit(device, &limit) == c.NVML_SUCCESS;
        },
        .clock_control => {
            var clock: c_uint = 0;
            return c.nvmlDeviceGetMaxClockInfo(device, CLOCK_GRAPHICS, &clock) == c.NVML_SUCCESS;
        },
        .fan_control => {
            var speed: c_uint = 0;
            return c.nvmlDeviceGetFanSpeed(device, &speed) == c.NVML_SUCCESS;
        },
    }
}

test "nvml types" {
    // Compile-time verification that types are correctly imported
    _ = Device;
    _ = Memory;
    _ = Utilization;
}
