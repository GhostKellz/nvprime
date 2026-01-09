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

const log = std.log.scoped(.dbus);

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
    VtableRegistrationFailed,
    MessageCreationFailed,
};

/// sd-bus types (opaque pointers)
const sd_bus = opaque {};
const sd_bus_message = opaque {};
const sd_bus_slot = opaque {};
const sd_bus_error = extern struct {
    name: ?[*:0]const u8 = null,
    message: ?[*:0]const u8 = null,
    _need_free: c_int = 0,
};

/// sd-bus vtable entry types
const SD_BUS_VTABLE_START: u8 = '<';
const SD_BUS_VTABLE_END: u8 = '>';
const SD_BUS_VTABLE_METHOD: u8 = 'M';
const SD_BUS_VTABLE_PROPERTY: u8 = 'P';
const SD_BUS_VTABLE_WRITABLE_PROPERTY: u8 = 'W';
const SD_BUS_VTABLE_SIGNAL: u8 = 'S';

/// sd-bus vtable flags
const SD_BUS_VTABLE_UNPRIVILEGED: u64 = 1 << 0;
const SD_BUS_VTABLE_PROPERTY_CONST: u64 = 1 << 5;
const SD_BUS_VTABLE_PROPERTY_EMITS_CHANGE: u64 = 1 << 6;

/// Method handler callback signature
const MethodHandler = *const fn (
    ?*sd_bus_message,
    ?*anyopaque,
    ?*sd_bus_error,
) callconv(.c) c_int;

/// Property getter callback signature
const PropertyGetter = *const fn (
    ?*sd_bus,
    ?[*:0]const u8,
    ?[*:0]const u8,
    ?[*:0]const u8,
    ?*sd_bus_message,
    ?*anyopaque,
    ?*sd_bus_error,
) callconv(.c) c_int;

/// sd-bus vtable entry (simplified)
const SdBusVtable = extern struct {
    type: u8,
    flags: u64 = 0,
    // Union of different entry types - using bytes for max flexibility
    data: extern union {
        start: extern struct { element_size: usize },
        method: extern struct {
            member: ?[*:0]const u8,
            signature: ?[*:0]const u8,
            result: ?[*:0]const u8,
            handler: ?MethodHandler,
            offset: usize,
            names: ?[*:0]const u8,
        },
        property: extern struct {
            member: ?[*:0]const u8,
            signature: ?[*:0]const u8,
            getter: ?PropertyGetter,
            setter: ?PropertyGetter,
            offset: usize,
        },
        signal: extern struct {
            member: ?[*:0]const u8,
            signature: ?[*:0]const u8,
            names: ?[*:0]const u8,
        },
    } = undefined,
};

/// sd-bus bindings (loaded dynamically)
const SdBus = struct {
    const dlopen_c = @cImport({
        @cInclude("dlfcn.h");
    });

    // Function pointer types
    const OpenUserFn = *const fn (**sd_bus) callconv(.c) c_int;
    const RequestNameFn = *const fn (*sd_bus, [*:0]const u8, u64) callconv(.c) c_int;
    const ProcessFn = *const fn (*sd_bus, ?*?*sd_bus_message) callconv(.c) c_int;
    const WaitFn = *const fn (*sd_bus, u64) callconv(.c) c_int;
    const FlushCloseUnrefFn = *const fn (?*sd_bus) callconv(.c) ?*sd_bus;
    const AddObjectVtableFn = *const fn (
        *sd_bus,
        ?*?*sd_bus_slot,
        [*:0]const u8,
        [*:0]const u8,
        [*]const SdBusVtable,
        ?*anyopaque,
    ) callconv(.c) c_int;

    // Message handling
    const MessageNewMethodReturnFn = *const fn (*sd_bus_message, **sd_bus_message) callconv(.c) c_int;
    const MessageAppendFn = *const fn (*sd_bus_message, [*:0]const u8, ...) callconv(.c) c_int;
    const SendFn = *const fn (*sd_bus, *sd_bus_message, ?*u64) callconv(.c) c_int;
    const MessageUnrefFn = *const fn (?*sd_bus_message) callconv(.c) ?*sd_bus_message;
    const MessageGetBusFn = *const fn (*sd_bus_message) callconv(.c) ?*sd_bus;
    const ReplyMethodReturnFn = *const fn (*sd_bus_message, [*:0]const u8, ...) callconv(.c) c_int;
    const ReplyMethodErrorfFn = *const fn (*sd_bus_message, [*:0]const u8, [*:0]const u8, ...) callconv(.c) c_int;

    // Function pointers
    bus_open_user: ?OpenUserFn = null,
    bus_request_name: ?RequestNameFn = null,
    bus_process: ?ProcessFn = null,
    bus_wait: ?WaitFn = null,
    bus_flush_close_unref: ?FlushCloseUnrefFn = null,
    bus_add_object_vtable: ?AddObjectVtableFn = null,
    bus_message_new_method_return: ?MessageNewMethodReturnFn = null,
    bus_message_append: ?MessageAppendFn = null,
    bus_send: ?SendFn = null,
    bus_message_unref: ?MessageUnrefFn = null,
    bus_message_get_bus: ?MessageGetBusFn = null,
    bus_reply_method_return: ?ReplyMethodReturnFn = null,
    bus_reply_method_errorf: ?ReplyMethodErrorfFn = null,

    handle: ?*anyopaque = null,

    fn load() ?SdBus {
        var self = SdBus{};

        // Try to load libsystemd
        self.handle = dlopen_c.dlopen("libsystemd.so.0", dlopen_c.RTLD_LAZY);
        if (self.handle == null) {
            self.handle = dlopen_c.dlopen("libsystemd.so", dlopen_c.RTLD_LAZY);
        }

        if (self.handle == null) {
            log.warn("Failed to load libsystemd.so", .{});
            return null;
        }

        // Load function pointers
        self.bus_open_user = @ptrCast(dlopen_c.dlsym(self.handle, "sd_bus_open_user"));
        self.bus_request_name = @ptrCast(dlopen_c.dlsym(self.handle, "sd_bus_request_name"));
        self.bus_process = @ptrCast(dlopen_c.dlsym(self.handle, "sd_bus_process"));
        self.bus_wait = @ptrCast(dlopen_c.dlsym(self.handle, "sd_bus_wait"));
        self.bus_flush_close_unref = @ptrCast(dlopen_c.dlsym(self.handle, "sd_bus_flush_close_unref"));
        self.bus_add_object_vtable = @ptrCast(dlopen_c.dlsym(self.handle, "sd_bus_add_object_vtable"));
        self.bus_message_new_method_return = @ptrCast(dlopen_c.dlsym(self.handle, "sd_bus_message_new_method_return"));
        self.bus_message_append = @ptrCast(dlopen_c.dlsym(self.handle, "sd_bus_message_append"));
        self.bus_send = @ptrCast(dlopen_c.dlsym(self.handle, "sd_bus_send"));
        self.bus_message_unref = @ptrCast(dlopen_c.dlsym(self.handle, "sd_bus_message_unref"));
        self.bus_message_get_bus = @ptrCast(dlopen_c.dlsym(self.handle, "sd_bus_message_get_bus"));
        self.bus_reply_method_return = @ptrCast(dlopen_c.dlsym(self.handle, "sd_bus_reply_method_return"));
        self.bus_reply_method_errorf = @ptrCast(dlopen_c.dlsym(self.handle, "sd_bus_reply_method_errorf"));

        if (self.bus_open_user == null or self.bus_request_name == null) {
            log.warn("Failed to load required sd-bus functions", .{});
            return null;
        }

        return self;
    }

    fn unload(self: *SdBus) void {
        if (self.handle) |h| {
            _ = dlopen_c.dlclose(h);
            self.handle = null;
        }
    }
};

/// Global sd-bus library handle (needed for C callbacks)
var g_sdbus: ?SdBus = null;

/// D-Bus service state
pub const Service = struct {
    allocator: std.mem.Allocator,
    sdbus: ?SdBus = null,
    bus: ?*sd_bus = null,
    slot: ?*sd_bus_slot = null,
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    thread: ?std.Thread = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        const sdbus = SdBus.load();
        g_sdbus = sdbus;

        return Self{
            .allocator = allocator,
            .sdbus = sdbus,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stop();
        if (self.sdbus) |*sb| {
            sb.unload();
        }
        g_sdbus = null;
    }

    /// Check if D-Bus is available
    pub fn isAvailable(self: *const Self) bool {
        return self.sdbus != null and self.sdbus.?.bus_open_user != null;
    }

    /// Start the D-Bus service in a background thread
    pub fn start(self: *Self) DbusError!void {
        if (!self.isAvailable()) {
            log.warn("D-Bus (systemd) not available", .{});
            return DbusError.LibraryNotFound;
        }

        if (self.running.load(.seq_cst)) {
            return; // Already running
        }

        log.info("Starting NVPrime D-Bus service: {s}", .{config.service_name});

        // Start service thread
        self.running.store(true, .seq_cst);
        self.thread = std.Thread.spawn(.{}, runEventLoop, .{self}) catch |err| {
            log.err("Failed to spawn D-Bus thread: {}", .{err});
            self.running.store(false, .seq_cst);
            return DbusError.ConnectionFailed;
        };
    }

    /// Run the D-Bus event loop (runs in background thread)
    fn runEventLoop(self: *Self) void {
        const sb = self.sdbus orelse return;

        // Connect to session bus
        var bus: ?*sd_bus = null;
        const open_result = sb.bus_open_user.?(&bus);
        if (open_result < 0 or bus == null) {
            log.err("Failed to connect to session bus: {}", .{open_result});
            self.running.store(false, .seq_cst);
            return;
        }
        self.bus = bus;

        // Request our service name
        const name_result = sb.bus_request_name.?(bus.?, config.service_name, 0);
        if (name_result < 0) {
            log.err("Failed to request name '{s}': {}", .{ config.service_name, name_result });
            _ = sb.bus_flush_close_unref.?(bus);
            self.bus = null;
            self.running.store(false, .seq_cst);
            return;
        }

        // Register GPU interface vtable
        const vtable_result = sb.bus_add_object_vtable.?(
            bus.?,
            @ptrCast(&self.slot),
            config.object_path_base ++ "/GPU0",
            config.interface_gpu,
            &gpu_vtable,
            null,
        );
        if (vtable_result < 0) {
            log.err("Failed to register vtable: {}", .{vtable_result});
            _ = sb.bus_flush_close_unref.?(bus);
            self.bus = null;
            self.running.store(false, .seq_cst);
            return;
        }

        log.info("D-Bus service started on {s}", .{config.object_path_base});

        // Event loop
        while (self.running.load(.seq_cst)) {
            // Process pending messages
            const process_result = sb.bus_process.?(bus.?, null);
            if (process_result < 0) {
                log.err("sd_bus_process failed: {}", .{process_result});
                break;
            }

            if (process_result > 0) {
                // Processed a message, check for more immediately
                continue;
            }

            // No messages, wait for activity (100ms timeout)
            const wait_result = sb.bus_wait.?(bus.?, 100 * 1000); // microseconds
            if (wait_result < 0) {
                // Timeout is not an error
                if (wait_result != -@as(c_int, @intCast(@intFromEnum(std.posix.E.INTR))) and
                    wait_result != -@as(c_int, @intCast(@intFromEnum(std.posix.E.AGAIN))))
                {
                    log.err("sd_bus_wait failed: {}", .{wait_result});
                    break;
                }
            }
        }

        // Cleanup
        _ = sb.bus_flush_close_unref.?(bus);
        self.bus = null;
        self.running.store(false, .seq_cst);
        log.info("D-Bus service stopped", .{});
    }

    /// Stop the D-Bus service
    pub fn stop(self: *Self) void {
        if (!self.running.load(.seq_cst)) return;

        log.info("Stopping NVPrime D-Bus service...", .{});
        self.running.store(false, .seq_cst);

        // Wait for thread to finish
        if (self.thread) |t| {
            t.join();
            self.thread = null;
        }
    }

    /// Check if service is running
    pub fn isRunning(self: *const Self) bool {
        return self.running.load(.seq_cst);
    }
};

// ============================================================================
// Method Handlers
// ============================================================================

/// Handler for GetTemperature method
fn handleGetTemperature(
    msg: ?*sd_bus_message,
    _: ?*anyopaque,
    _: ?*sd_bus_error,
) callconv(.c) c_int {
    const sb = g_sdbus orelse return -1;
    const reply_fn = sb.bus_reply_method_return orelse return -1;

    const info = getGpuInfo(0) orelse {
        return -1;
    };

    // Reply with temperature as u32
    return reply_fn(msg.?, "u", info.temperature_c);
}

/// Handler for GetPowerDraw method
fn handleGetPowerDraw(
    msg: ?*sd_bus_message,
    _: ?*anyopaque,
    _: ?*sd_bus_error,
) callconv(.c) c_int {
    const sb = g_sdbus orelse return -1;
    const reply_fn = sb.bus_reply_method_return orelse return -1;

    const info = getGpuInfo(0) orelse {
        return -1;
    };

    // Reply with power as double
    return reply_fn(msg.?, "d", @as(f64, info.power_draw_w));
}

/// Handler for GetClocks method
fn handleGetClocks(
    msg: ?*sd_bus_message,
    _: ?*anyopaque,
    _: ?*sd_bus_error,
) callconv(.c) c_int {
    const sb = g_sdbus orelse return -1;
    const reply_fn = sb.bus_reply_method_return orelse return -1;

    const info = getGpuInfo(0) orelse {
        return -1;
    };

    // Reply with gpu_mhz, mem_mhz
    return reply_fn(msg.?, "uu", info.gpu_clock_mhz, info.mem_clock_mhz);
}

/// Handler for GetUtilization method
fn handleGetUtilization(
    msg: ?*sd_bus_message,
    _: ?*anyopaque,
    _: ?*sd_bus_error,
) callconv(.c) c_int {
    const sb = g_sdbus orelse return -1;
    const reply_fn = sb.bus_reply_method_return orelse return -1;

    const info = getGpuInfo(0) orelse {
        return -1;
    };

    // Reply with gpu_percent, mem_percent (using gpu for both for now)
    return reply_fn(msg.?, "uu", info.utilization_percent, info.mem_utilization_percent);
}

/// Handler for GetVRAM method
fn handleGetVRAM(
    msg: ?*sd_bus_message,
    _: ?*anyopaque,
    _: ?*sd_bus_error,
) callconv(.c) c_int {
    const sb = g_sdbus orelse return -1;
    const reply_fn = sb.bus_reply_method_return orelse return -1;

    const info = getGpuInfo(0) orelse {
        return -1;
    };

    // Reply with used_mb, total_mb as u64
    return reply_fn(msg.?, "tt", info.vram_used_mb, info.vram_total_mb);
}

/// Property getter for Name
fn handleGetName(
    _: ?*sd_bus,
    _: ?[*:0]const u8,
    _: ?[*:0]const u8,
    _: ?[*:0]const u8,
    reply: ?*sd_bus_message,
    _: ?*anyopaque,
    _: ?*sd_bus_error,
) callconv(.c) c_int {
    const sb = g_sdbus orelse return -1;
    const append_fn = sb.bus_message_append orelse return -1;

    const info = getGpuInfo(0) orelse {
        return append_fn(reply.?, "s", "Unknown GPU");
    };

    return append_fn(reply.?, "s", info.name.ptr);
}

/// Property getter for Architecture
fn handleGetArchitecture(
    _: ?*sd_bus,
    _: ?[*:0]const u8,
    _: ?[*:0]const u8,
    _: ?[*:0]const u8,
    reply: ?*sd_bus_message,
    _: ?*anyopaque,
    _: ?*sd_bus_error,
) callconv(.c) c_int {
    const sb = g_sdbus orelse return -1;
    const append_fn = sb.bus_message_append orelse return -1;

    const info = getGpuInfo(0) orelse {
        return append_fn(reply.?, "s", "Unknown");
    };

    return append_fn(reply.?, "s", info.architecture.ptr);
}

/// Property getter for Temperature
fn handleGetTemperatureProp(
    _: ?*sd_bus,
    _: ?[*:0]const u8,
    _: ?[*:0]const u8,
    _: ?[*:0]const u8,
    reply: ?*sd_bus_message,
    _: ?*anyopaque,
    _: ?*sd_bus_error,
) callconv(.c) c_int {
    const sb = g_sdbus orelse return -1;
    const append_fn = sb.bus_message_append orelse return -1;

    const info = getGpuInfo(0) orelse {
        return append_fn(reply.?, "u", @as(u32, 0));
    };

    return append_fn(reply.?, "u", info.temperature_c);
}

/// Property getter for PowerDraw
fn handleGetPowerDrawProp(
    _: ?*sd_bus,
    _: ?[*:0]const u8,
    _: ?[*:0]const u8,
    _: ?[*:0]const u8,
    reply: ?*sd_bus_message,
    _: ?*anyopaque,
    _: ?*sd_bus_error,
) callconv(.c) c_int {
    const sb = g_sdbus orelse return -1;
    const append_fn = sb.bus_message_append orelse return -1;

    const info = getGpuInfo(0) orelse {
        return append_fn(reply.?, "d", @as(f64, 0.0));
    };

    return append_fn(reply.?, "d", @as(f64, info.power_draw_w));
}

/// Property getter for GpuClock
fn handleGetGpuClockProp(
    _: ?*sd_bus,
    _: ?[*:0]const u8,
    _: ?[*:0]const u8,
    _: ?[*:0]const u8,
    reply: ?*sd_bus_message,
    _: ?*anyopaque,
    _: ?*sd_bus_error,
) callconv(.c) c_int {
    const sb = g_sdbus orelse return -1;
    const append_fn = sb.bus_message_append orelse return -1;

    const info = getGpuInfo(0) orelse {
        return append_fn(reply.?, "u", @as(u32, 0));
    };

    return append_fn(reply.?, "u", info.gpu_clock_mhz);
}

/// Property getter for MemClock
fn handleGetMemClockProp(
    _: ?*sd_bus,
    _: ?[*:0]const u8,
    _: ?[*:0]const u8,
    _: ?[*:0]const u8,
    reply: ?*sd_bus_message,
    _: ?*anyopaque,
    _: ?*sd_bus_error,
) callconv(.c) c_int {
    const sb = g_sdbus orelse return -1;
    const append_fn = sb.bus_message_append orelse return -1;

    const info = getGpuInfo(0) orelse {
        return append_fn(reply.?, "u", @as(u32, 0));
    };

    return append_fn(reply.?, "u", info.mem_clock_mhz);
}

// ============================================================================
// VTable Definition
// ============================================================================

/// Helper to create vtable start entry
fn vtableStart() SdBusVtable {
    return SdBusVtable{
        .type = SD_BUS_VTABLE_START,
        .flags = 0,
        .data = .{ .start = .{ .element_size = @sizeOf(SdBusVtable) } },
    };
}

/// Helper to create vtable end entry
fn vtableEnd() SdBusVtable {
    return SdBusVtable{
        .type = SD_BUS_VTABLE_END,
        .flags = 0,
    };
}

/// Helper to create method entry
fn vtableMethod(
    member: [*:0]const u8,
    signature: ?[*:0]const u8,
    result: ?[*:0]const u8,
    handler: MethodHandler,
) SdBusVtable {
    return SdBusVtable{
        .type = SD_BUS_VTABLE_METHOD,
        .flags = SD_BUS_VTABLE_UNPRIVILEGED,
        .data = .{
            .method = .{
                .member = member,
                .signature = signature,
                .result = result,
                .handler = handler,
                .offset = 0,
                .names = null,
            },
        },
    };
}

/// Helper to create property entry
fn vtableProperty(
    member: [*:0]const u8,
    signature: [*:0]const u8,
    getter: PropertyGetter,
) SdBusVtable {
    return SdBusVtable{
        .type = SD_BUS_VTABLE_PROPERTY,
        .flags = SD_BUS_VTABLE_PROPERTY_EMITS_CHANGE,
        .data = .{
            .property = .{
                .member = member,
                .signature = signature,
                .getter = getter,
                .setter = null,
                .offset = 0,
            },
        },
    };
}

/// Helper to create signal entry
fn vtableSignal(
    member: [*:0]const u8,
    signature: [*:0]const u8,
) SdBusVtable {
    return SdBusVtable{
        .type = SD_BUS_VTABLE_SIGNAL,
        .flags = 0,
        .data = .{
            .signal = .{
                .member = member,
                .signature = signature,
                .names = null,
            },
        },
    };
}

/// GPU interface vtable
const gpu_vtable = [_]SdBusVtable{
    vtableStart(),

    // Methods
    vtableMethod("GetTemperature", "", "u", handleGetTemperature),
    vtableMethod("GetPowerDraw", "", "d", handleGetPowerDraw),
    vtableMethod("GetClocks", "", "uu", handleGetClocks),
    vtableMethod("GetUtilization", "", "uu", handleGetUtilization),
    vtableMethod("GetVRAM", "", "tt", handleGetVRAM),

    // Properties
    vtableProperty("Name", "s", handleGetName),
    vtableProperty("Architecture", "s", handleGetArchitecture),
    vtableProperty("Temperature", "u", handleGetTemperatureProp),
    vtableProperty("PowerDraw", "d", handleGetPowerDrawProp),
    vtableProperty("GpuClock", "u", handleGetGpuClockProp),
    vtableProperty("MemClock", "u", handleGetMemClockProp),

    // Signals
    vtableSignal("ThermalWarning", "uu"),
    vtableSignal("PowerLimitReached", "dd"),

    vtableEnd(),
};

// ============================================================================
// GPU Information
// ============================================================================

/// GPU information for D-Bus export
pub const GpuInfo = struct {
    index: u32,
    name: [:0]const u8,
    architecture: [:0]const u8,
    temperature_c: u32,
    power_draw_w: f32,
    gpu_clock_mhz: u32,
    mem_clock_mhz: u32,
    utilization_percent: u32,
    mem_utilization_percent: u32,
    vram_used_mb: u64,
    vram_total_mb: u64,

    // Static buffers for C string conversion
    var name_buf: [256:0]u8 = undefined;
    var arch_buf: [64:0]u8 = undefined;
};

/// Get GPU info for D-Bus export
pub fn getGpuInfo(index: u32) ?GpuInfo {
    _ = index; // TODO: multi-GPU support

    const caps = root.nvcaps.getCapabilities() catch |err| {
        log.debug("Failed to get GPU capabilities: {}", .{err});
        return null;
    };

    // Copy name to static buffer with null terminator
    const name_len = @min(caps.name_len, GpuInfo.name_buf.len - 1);
    @memcpy(GpuInfo.name_buf[0..name_len], caps.name[0..name_len]);
    GpuInfo.name_buf[name_len] = 0;

    // Copy architecture name
    const arch_name = @tagName(caps.architecture);
    const arch_len = @min(arch_name.len, GpuInfo.arch_buf.len - 1);
    @memcpy(GpuInfo.arch_buf[0..arch_len], arch_name[0..arch_len]);
    GpuInfo.arch_buf[arch_len] = 0;

    return GpuInfo{
        .index = 0,
        .name = GpuInfo.name_buf[0..name_len :0],
        .architecture = GpuInfo.arch_buf[0..arch_len :0],
        .temperature_c = caps.temperature,
        .power_draw_w = @as(f32, @floatFromInt(caps.power_usage)) / 1000.0,
        .gpu_clock_mhz = caps.gpu_clock,
        .mem_clock_mhz = caps.mem_clock,
        .utilization_percent = caps.gpu_utilization,
        .mem_utilization_percent = caps.memory_utilization,
        .vram_used_mb = caps.vram_used / (1024 * 1024),
        .vram_total_mb = caps.vram_total / (1024 * 1024),
    };
}

// ============================================================================
// D-Bus Introspection XML
// ============================================================================

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

// ============================================================================
// Tests
// ============================================================================

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

test "vtable helpers" {
    const start = vtableStart();
    try std.testing.expectEqual(SD_BUS_VTABLE_START, start.type);

    const end = vtableEnd();
    try std.testing.expectEqual(SD_BUS_VTABLE_END, end.type);
}
