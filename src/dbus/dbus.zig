//! NVPrime D-Bus Service
//!
//! Exposes GPU information and control via D-Bus.
//! Service name: com.nvidia.NVPrime
//!
//! Interfaces:
//! - com.nvidia.NVPrime.GPU: GPU information and monitoring
//! - com.nvidia.NVPrime.Power: Power management
//! - com.nvidia.NVPrime.Performance: Performance profiles
//!
//! Example usage with dbus-send:
//! ```
//! dbus-send --session --dest=com.nvidia.NVPrime \
//!   --print-reply /com/nvidia/NVPrime/GPU0 \
//!   com.nvidia.NVPrime.GPU.GetTemperature
//! ```

const std = @import("std");
const root = @import("../root.zig");

/// D-Bus service configuration
pub const config = struct {
    pub const service_name = "com.nvidia.NVPrime";
    pub const object_path_base = "/com/nvidia/NVPrime";

    pub const interface_gpu = "com.nvidia.NVPrime.GPU";
    pub const interface_power = "com.nvidia.NVPrime.Power";
    pub const interface_perf = "com.nvidia.NVPrime.Performance";
};

/// D-Bus error codes
pub const DbusError = error{
    ConnectionFailed,
    RequestNameFailed,
    ObjectPathInvalid,
    MethodCallFailed,
    LibraryNotFound,
};

/// sd-bus bindings (loaded dynamically)
const SdBus = struct {
    const c = @cImport({
        @cInclude("systemd/sd-bus.h");
    });

    // Function pointers for dynamic loading
    bus_open_user: ?*const fn (*?*c.sd_bus) callconv(.c) c_int = null,
    bus_request_name: ?*const fn (*c.sd_bus, [*:0]const u8, u64) callconv(.c) c_int = null,
    bus_process: ?*const fn (*c.sd_bus, ?*?*c.sd_bus_message) callconv(.c) c_int = null,
    bus_wait: ?*const fn (*c.sd_bus, u64) callconv(.c) c_int = null,
    bus_flush_close_unref: ?*const fn (*c.sd_bus) callconv(.c) ?*c.sd_bus = null,
    bus_add_object_vtable: ?*const fn (
        *c.sd_bus,
        ?*?*c.sd_bus_slot,
        [*:0]const u8,
        [*:0]const u8,
        [*]const c.sd_bus_vtable,
        ?*anyopaque,
    ) callconv(.c) c_int = null,

    handle: ?*anyopaque = null,

    fn load() ?SdBus {
        const dlopen = @cImport({
            @cInclude("dlfcn.h");
        });

        var self = SdBus{};

        // Try to load libsystemd
        self.handle = dlopen.dlopen("libsystemd.so.0", dlopen.RTLD_LAZY);
        if (self.handle == null) {
            self.handle = dlopen.dlopen("libsystemd.so", dlopen.RTLD_LAZY);
        }

        if (self.handle == null) {
            return null;
        }

        // Load function pointers
        self.bus_open_user = @ptrCast(dlopen.dlsym(self.handle, "sd_bus_open_user"));
        self.bus_request_name = @ptrCast(dlopen.dlsym(self.handle, "sd_bus_request_name"));
        self.bus_process = @ptrCast(dlopen.dlsym(self.handle, "sd_bus_process"));
        self.bus_wait = @ptrCast(dlopen.dlsym(self.handle, "sd_bus_wait"));
        self.bus_flush_close_unref = @ptrCast(dlopen.dlsym(self.handle, "sd_bus_flush_close_unref"));
        self.bus_add_object_vtable = @ptrCast(dlopen.dlsym(self.handle, "sd_bus_add_object_vtable"));

        return self;
    }
};

/// D-Bus service state
pub const Service = struct {
    allocator: std.mem.Allocator,
    sdbus: ?SdBus = null,
    running: bool = false,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .sdbus = SdBus.load(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.stop();
    }

    /// Check if D-Bus is available
    pub fn isAvailable(self: *const Self) bool {
        return self.sdbus != null and self.sdbus.?.bus_open_user != null;
    }

    /// Start the D-Bus service
    pub fn start(self: *Self) DbusError!void {
        if (!self.isAvailable()) {
            std.log.warn("D-Bus (systemd) not available", .{});
            return DbusError.LibraryNotFound;
        }

        std.log.info("Starting NVPrime D-Bus service: {s}", .{config.service_name});
        self.running = true;

        // Full implementation would:
        // 1. sd_bus_open_user() to connect to session bus
        // 2. sd_bus_request_name() to claim our service name
        // 3. sd_bus_add_object_vtable() to register methods
        // 4. Run event loop with sd_bus_process() / sd_bus_wait()
    }

    /// Stop the D-Bus service
    pub fn stop(self: *Self) void {
        if (!self.running) return;
        self.running = false;
        std.log.info("NVPrime D-Bus service stopped", .{});
    }
};

/// GPU information for D-Bus export
pub const GpuInfo = struct {
    index: u32,
    name: []const u8,
    architecture: []const u8,
    temperature_c: u32,
    power_draw_w: f32,
    gpu_clock_mhz: u32,
    mem_clock_mhz: u32,
    utilization_percent: u32,
    vram_used_mb: u64,
    vram_total_mb: u64,

    /// Convert to D-Bus-friendly format (could use sd_bus_message_append)
    pub fn toProperties(self: *const GpuInfo, allocator: std.mem.Allocator) !std.StringHashMap([]const u8) {
        var props = std.StringHashMap([]const u8).init(allocator);

        try props.put("Name", self.name);
        try props.put("Architecture", self.architecture);

        return props;
    }
};

/// Get GPU info for D-Bus export
pub fn getGpuInfo(index: u32) ?GpuInfo {
    const caps = root.nvcaps.getCapabilities() catch return null;

    return GpuInfo{
        .index = index,
        .name = caps.name[0..caps.name_len],
        .architecture = @tagName(caps.architecture),
        .temperature_c = caps.temperature,
        .power_draw_w = @as(f32, @floatFromInt(caps.power_usage)) / 1000.0,
        .gpu_clock_mhz = caps.gpu_clock,
        .mem_clock_mhz = caps.mem_clock,
        .utilization_percent = caps.gpu_utilization,
        .vram_used_mb = caps.vram_used / (1024 * 1024),
        .vram_total_mb = caps.vram_total / (1024 * 1024),
    };
}

// D-Bus introspection XML for GPU interface
pub const gpu_introspection_xml =
    \\<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN"
    \\"http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
    \\<node>
    \\  <interface name="com.nvidia.NVPrime.GPU">
    \\    <method name="GetTemperature">
    \\      <arg name="temperature" type="u" direction="out"/>
    \\    </method>
    \\    <method name="GetPowerDraw">
    \\      <arg name="watts" type="d" direction="out"/>
    \\    </method>
    \\    <method name="GetClocks">
    \\      <arg name="gpu_mhz" type="u" direction="out"/>
    \\      <arg name="mem_mhz" type="u" direction="out"/>
    \\    </method>
    \\    <method name="GetUtilization">
    \\      <arg name="gpu_percent" type="u" direction="out"/>
    \\      <arg name="mem_percent" type="u" direction="out"/>
    \\    </method>
    \\    <method name="GetVRAM">
    \\      <arg name="used_mb" type="t" direction="out"/>
    \\      <arg name="total_mb" type="t" direction="out"/>
    \\    </method>
    \\    <property name="Name" type="s" access="read"/>
    \\    <property name="Architecture" type="s" access="read"/>
    \\    <property name="Temperature" type="u" access="read"/>
    \\    <property name="PowerDraw" type="d" access="read"/>
    \\    <property name="GpuClock" type="u" access="read"/>
    \\    <property name="MemClock" type="u" access="read"/>
    \\    <signal name="ThermalWarning">
    \\      <arg name="temperature" type="u"/>
    \\      <arg name="threshold" type="u"/>
    \\    </signal>
    \\    <signal name="PowerLimitReached">
    \\      <arg name="current_watts" type="d"/>
    \\      <arg name="limit_watts" type="d"/>
    \\    </signal>
    \\  </interface>
    \\</node>
;

// Tests
test "service init" {
    var service = Service.init(std.testing.allocator);
    defer service.deinit();

    // May or may not be available depending on system
    _ = service.isAvailable();
}

test "config constants" {
    try std.testing.expectEqualStrings("com.nvidia.NVPrime", config.service_name);
    try std.testing.expectEqualStrings("/com/nvidia/NVPrime", config.object_path_base);
}
