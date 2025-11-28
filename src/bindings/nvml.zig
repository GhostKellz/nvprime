//! NVML (NVIDIA Management Library) Bindings
//!
//! Low-level Zig bindings to libnvidia-ml for GPU management.
//! This provides the foundation for nvcaps, nvcore, nvpower, and nvdisplay.

const std = @import("std");
const c = @cImport({
    @cInclude("nvml.h");
});

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
};

fn mapNvmlReturn(ret: c.nvmlReturn_t) NvmlError!void {
    return switch (ret) {
        c.NVML_SUCCESS => {},
        c.NVML_ERROR_UNINITIALIZED => error.Uninitialized,
        c.NVML_ERROR_INVALID_ARGUMENT => error.InvalidArgument,
        c.NVML_ERROR_NOT_SUPPORTED => error.NotSupported,
        c.NVML_ERROR_NO_PERMISSION => error.NoPermission,
        c.NVML_ERROR_NOT_FOUND => error.NotFound,
        c.NVML_ERROR_INSUFFICIENT_SIZE => error.InsufficientSize,
        c.NVML_ERROR_INSUFFICIENT_POWER => error.InsufficientPower,
        c.NVML_ERROR_DRIVER_NOT_LOADED => error.DriverNotLoaded,
        c.NVML_ERROR_TIMEOUT => error.Timeout,
        c.NVML_ERROR_IRQ_ISSUE => error.IrqIssue,
        c.NVML_ERROR_LIBRARY_NOT_FOUND => error.LibraryNotFound,
        c.NVML_ERROR_FUNCTION_NOT_FOUND => error.FunctionNotFound,
        c.NVML_ERROR_CORRUPTED_INFOROM => error.CorruptedInfoROM,
        c.NVML_ERROR_GPU_IS_LOST => error.GpuIsLost,
        c.NVML_ERROR_RESET_REQUIRED => error.ResetRequired,
        c.NVML_ERROR_OPERATING_SYSTEM => error.OperatingSystem,
        c.NVML_ERROR_LIB_RM_VERSION_MISMATCH => error.LibRmVersionMismatch,
        c.NVML_ERROR_IN_USE => error.InUse,
        c.NVML_ERROR_MEMORY => error.Memory,
        c.NVML_ERROR_NO_DATA => error.NoData,
        c.NVML_ERROR_VGPU_ECC_NOT_SUPPORTED => error.VgpuEccNotSupported,
        c.NVML_ERROR_INSUFFICIENT_RESOURCES => error.InsufficientResources,
        c.NVML_ERROR_FREQ_NOT_SUPPORTED => error.FreqNotSupported,
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

/// Initialize NVML library
pub fn init() NvmlError!void {
    if (initialized) return;
    try mapNvmlReturn(c.nvmlInit_v2());
    initialized = true;
}

/// Shutdown NVML library
pub fn shutdown() void {
    if (!initialized) return;
    _ = c.nvmlShutdown();
    initialized = false;
}

/// Get NVML driver version string
pub fn getDriverVersion() NvmlError![80]u8 {
    var version: [80]u8 = undefined;
    try mapNvmlReturn(c.nvmlSystemGetDriverVersion(&version, version.len));
    return version;
}

/// Get NVML library version string
pub fn getNvmlVersion() NvmlError![80]u8 {
    var version: [80]u8 = undefined;
    try mapNvmlReturn(c.nvmlSystemGetNVMLVersion(&version, version.len));
    return version;
}

/// Get number of GPU devices
pub fn getDeviceCount() NvmlError!u32 {
    var count: c_uint = 0;
    try mapNvmlReturn(c.nvmlDeviceGetCount_v2(&count));
    return count;
}

/// Get device handle by index
pub fn getDeviceByIndex(index: u32) NvmlError!Device {
    var device: Device = undefined;
    try mapNvmlReturn(c.nvmlDeviceGetHandleByIndex_v2(index, &device));
    return device;
}

/// Get device name
pub fn getDeviceName(device: Device) NvmlError![96]u8 {
    var name: [96]u8 = undefined;
    try mapNvmlReturn(c.nvmlDeviceGetName(device, &name, name.len));
    return name;
}

/// Get device UUID
pub fn getDeviceUuid(device: Device) NvmlError![96]u8 {
    var uuid: [96]u8 = undefined;
    try mapNvmlReturn(c.nvmlDeviceGetUUID(device, &uuid, uuid.len));
    return uuid;
}

/// Get device PCI info
pub fn getDevicePciInfo(device: Device) NvmlError!PciInfo {
    var pci: PciInfo = undefined;
    try mapNvmlReturn(c.nvmlDeviceGetPciInfo_v3(device, &pci));
    return pci;
}

/// Get device memory info
pub fn getDeviceMemoryInfo(device: Device) NvmlError!Memory {
    var memory: Memory = undefined;
    try mapNvmlReturn(c.nvmlDeviceGetMemoryInfo(device, &memory));
    return memory;
}

/// Get device utilization rates
pub fn getDeviceUtilization(device: Device) NvmlError!Utilization {
    var util: Utilization = undefined;
    try mapNvmlReturn(c.nvmlDeviceGetUtilizationRates(device, &util));
    return util;
}

/// Get current GPU clock speed (MHz)
pub fn getDeviceClock(device: Device, clock_type: ClockType) NvmlError!u32 {
    var clock: c_uint = 0;
    try mapNvmlReturn(c.nvmlDeviceGetClockInfo(device, clock_type, &clock));
    return clock;
}

/// Get max GPU clock speed (MHz)
pub fn getDeviceMaxClock(device: Device, clock_type: ClockType) NvmlError!u32 {
    var clock: c_uint = 0;
    try mapNvmlReturn(c.nvmlDeviceGetMaxClockInfo(device, clock_type, &clock));
    return clock;
}

/// Get current performance state (P-state)
pub fn getDevicePerformanceState(device: Device) NvmlError!PStates {
    var pstate: PStates = undefined;
    try mapNvmlReturn(c.nvmlDeviceGetPerformanceState(device, &pstate));
    return pstate;
}

/// Get GPU temperature
pub fn getDeviceTemperature(device: Device, sensor: TemperatureSensors) NvmlError!u32 {
    var temp: c_uint = 0;
    try mapNvmlReturn(c.nvmlDeviceGetTemperature(device, sensor, &temp));
    return temp;
}

/// Get GPU power usage (milliwatts)
pub fn getDevicePowerUsage(device: Device) NvmlError!u32 {
    var power: c_uint = 0;
    try mapNvmlReturn(c.nvmlDeviceGetPowerUsage(device, &power));
    return power;
}

/// Get GPU power limit (milliwatts)
pub fn getDevicePowerLimit(device: Device) NvmlError!u32 {
    var limit: c_uint = 0;
    try mapNvmlReturn(c.nvmlDeviceGetPowerManagementLimit(device, &limit));
    return limit;
}

/// Set GPU power limit (milliwatts) - requires root
pub fn setDevicePowerLimit(device: Device, limit: u32) NvmlError!void {
    try mapNvmlReturn(c.nvmlDeviceSetPowerManagementLimit(device, limit));
}

/// Get fan speed percentage
pub fn getDeviceFanSpeed(device: Device) NvmlError!u32 {
    var speed: c_uint = 0;
    try mapNvmlReturn(c.nvmlDeviceGetFanSpeed(device, &speed));
    return speed;
}

/// Get CUDA compute capability
pub fn getDeviceCudaComputeCapability(device: Device) NvmlError!struct { major: i32, minor: i32 } {
    var major: c_int = 0;
    var minor: c_int = 0;
    try mapNvmlReturn(c.nvmlDeviceGetCudaComputeCapability(device, &major, &minor));
    return .{ .major = major, .minor = minor };
}

/// Get device architecture
pub fn getDeviceArchitecture(device: Device) NvmlError!c.nvmlDeviceArchitecture_t {
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
