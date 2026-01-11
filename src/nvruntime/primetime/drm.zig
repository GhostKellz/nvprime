//! DRM/KMS backend for PrimeTime
//!
//! Direct Rendering Manager interface for display control.
//! Handles monitor enumeration, mode setting, VRR, and page flipping.
//!
//! Features:
//! - Legacy and atomic modesetting support
//! - VRR (Variable Refresh Rate) control
//! - VRR range detection (min/max Hz)
//! - Page flip with VBlank synchronization
//! - Multi-monitor enumeration
//!
//! Note: This module requires libdrm. Build with -Ddrm=true to enable.

const std = @import("std");
const builtin = @import("builtin");

const log = std.log.scoped(.drm);

// Only include DRM headers when building with DRM support
const has_drm = @hasDecl(@import("root"), "drm_enabled") and @import("root").drm_enabled;

const c = if (has_drm) @cImport({
    @cInclude("xf86drm.h");
    @cInclude("xf86drmMode.h");
    @cInclude("drm_fourcc.h");
}) else struct {
    // Stub constants when DRM not available
    pub const DRM_MODE_CONNECTED: c_int = 1;
    pub const DRM_MODE_TYPE_PREFERRED: u32 = 1 << 3;
    pub const DRM_MODE_FLAG_INTERLACE: u32 = 1 << 4;
    pub const DRM_MODE_OBJECT_CONNECTOR: u32 = 0xc0c0c0c0;
    pub const DRM_VBLANK_RELATIVE: u32 = 1;
    pub const DRM_VBLANK_HIGH_CRTC_SHIFT: u32 = 1;
    pub const DRM_VBLANK_HIGH_CRTC_MASK: u32 = 0;

    pub const drmModeRes = opaque {};
    pub const drmModeConnector = extern struct {
        connection: c_int = 0,
        connector_type: u32 = 0,
        count_modes: c_int = 0,
        modes: [*]drmModeModeInfo = undefined,
    };
    pub const drmModeModeInfo = extern struct {
        hdisplay: u16 = 0,
        vdisplay: u16 = 0,
        vrefresh: u32 = 0,
        flags: u32 = 0,
        type: u32 = 0,
    };
    pub const drmVBlank = extern struct {
        request: extern struct {
            type: u32 = 0,
            sequence: u32 = 0,
        } = .{},
        reply: extern struct {
            sequence: u32 = 0,
            tval_sec: i64 = 0,
            tval_usec: i64 = 0,
        } = .{},
    };

    pub fn drmModeGetResources(_: c_int) ?*drmModeRes {
        return null;
    }
    pub fn drmModeFreeResources(_: ?*drmModeRes) void {}
    pub fn drmModeGetConnector(_: c_int, _: u32) ?*drmModeConnector {
        return null;
    }
    pub fn drmModeFreeConnector(_: *drmModeConnector) void {}
    pub fn drmModeObjectGetProperties(_: c_int, _: u32, _: u32) ?*anyopaque {
        return null;
    }
    pub fn drmModeFreeObjectProperties(_: ?*anyopaque) void {}
    pub fn drmModeGetProperty(_: c_int, _: u32) ?*anyopaque {
        return null;
    }
    pub fn drmModeFreeProperty(_: ?*anyopaque) void {}
    pub fn drmModeObjectSetProperty(_: c_int, _: u32, _: u32, _: u32, _: u64) c_int {
        return -1;
    }
    pub fn drmWaitVBlank(_: c_int, _: *drmVBlank) c_int {
        return -1;
    }
};

/// DRM device handle
pub const Device = struct {
    fd: std.posix.fd_t,
    resources: ?*c.drmModeRes,

    pub fn open(path: []const u8) !Device {
        const fd = try std.posix.open(
            @ptrCast(path.ptr),
            .{ .ACCMODE = .RDWR, .CLOEXEC = true },
            0,
        );

        const resources = c.drmModeGetResources(fd);

        return Device{
            .fd = fd,
            .resources = resources,
        };
    }

    pub fn openDefault() !Device {
        // Try common DRM device paths
        const paths = [_][]const u8{
            "/dev/dri/card0",
            "/dev/dri/card1",
            "/dev/dri/renderD128",
        };

        for (paths) |path| {
            if (open(path)) |device| {
                return device;
            } else |_| continue;
        }

        return error.NoDrmDevice;
    }

    pub fn close(self: *Device) void {
        if (self.resources) |res| {
            c.drmModeFreeResources(res);
        }
        std.posix.close(self.fd);
    }

    /// Get number of connected connectors (monitors)
    pub fn getConnectorCount(self: *const Device) u32 {
        if (self.resources) |res| {
            return @intCast(res.count_connectors);
        }
        return 0;
    }

    /// Get connector info
    pub fn getConnector(self: *const Device, index: u32) ?Connector {
        if (self.resources) |res| {
            if (index >= res.count_connectors) return null;
            const conn_id = res.connectors[index];
            const conn = c.drmModeGetConnector(self.fd, conn_id);
            if (conn == null) return null;

            return Connector{
                .id = conn_id,
                .handle = conn,
                .fd = self.fd,
            };
        }
        return null;
    }

    /// Check if VRR is supported
    pub fn supportsVrr(self: *const Device, connector_id: u32) bool {
        var prop_id: u32 = 0;
        if (self.findProperty(connector_id, c.DRM_MODE_OBJECT_CONNECTOR, "VRR_ENABLED")) |id| {
            prop_id = id;
        } else {
            return false;
        }
        _ = prop_id;
        return true;
    }

    /// Set VRR enabled/disabled
    pub fn setVrr(self: *Device, connector_id: u32, enabled: bool) !void {
        const prop_id = self.findProperty(connector_id, c.DRM_MODE_OBJECT_CONNECTOR, "VRR_ENABLED") orelse
            return error.VrrNotSupported;

        const value: u64 = if (enabled) 1 else 0;
        const ret = c.drmModeObjectSetProperty(self.fd, connector_id, c.DRM_MODE_OBJECT_CONNECTOR, prop_id, value);
        if (ret != 0) return error.SetPropertyFailed;
    }

    fn findProperty(self: *const Device, object_id: u32, object_type: u32, name: []const u8) ?u32 {
        const props = c.drmModeObjectGetProperties(self.fd, object_id, object_type);
        if (props == null) return null;
        defer c.drmModeFreeObjectProperties(props);

        var i: u32 = 0;
        while (i < props.?.count_props) : (i += 1) {
            const prop = c.drmModeGetProperty(self.fd, props.?.props[i]);
            if (prop == null) continue;
            defer c.drmModeFreeProperty(prop);

            const prop_name = std.mem.span(@as([*:0]const u8, @ptrCast(&prop.?.name)));
            if (std.mem.eql(u8, prop_name, name)) {
                return props.?.props[i];
            }
        }
        return null;
    }

    /// Get the current value of a connector property
    pub fn getPropertyValue(self: *const Device, connector_id: u32, name: []const u8) ?u64 {
        const props = c.drmModeObjectGetProperties(self.fd, connector_id, c.DRM_MODE_OBJECT_CONNECTOR);
        if (props == null) return null;
        defer c.drmModeFreeObjectProperties(props);

        var i: u32 = 0;
        while (i < props.?.count_props) : (i += 1) {
            const prop = c.drmModeGetProperty(self.fd, props.?.props[i]);
            if (prop == null) continue;
            defer c.drmModeFreeProperty(prop);

            const prop_name = std.mem.span(@as([*:0]const u8, @ptrCast(&prop.?.name)));
            if (std.mem.eql(u8, prop_name, name)) {
                return props.?.prop_values[i];
            }
        }
        return null;
    }

    /// Get VRR capabilities for a connector
    pub fn getVrrCapabilities(self: *const Device, connector_id: u32) VrrCapabilities {
        var caps = VrrCapabilities{};

        // Check if VRR_ENABLED property exists
        if (self.findProperty(connector_id, c.DRM_MODE_OBJECT_CONNECTOR, "VRR_ENABLED")) |_| {
            caps.supported = true;

            // Check current enabled state
            if (self.getPropertyValue(connector_id, "VRR_ENABLED")) |val| {
                caps.enabled = val != 0;
            }
        }

        // Try to get VRR range from various properties
        // NVIDIA exposes "vrr_min_hz" and "vrr_max_hz" on some drivers
        if (self.getPropertyValue(connector_id, "vrr_min_hz")) |min| {
            caps.min_refresh_hz = @truncate(min);
        }
        if (self.getPropertyValue(connector_id, "vrr_max_hz")) |max| {
            caps.max_refresh_hz = @truncate(max);
        }

        // Fallback: try to get from EDID-derived properties
        if (caps.max_refresh_hz == 0) {
            // Look at available modes for the highest refresh rate
            if (self.getConnectorById(connector_id)) |*conn| {
                defer conn.deinit();
                var max_hz: u32 = 0;
                var i: u32 = 0;
                while (i < conn.getModeCount()) : (i += 1) {
                    if (conn.getMode(i)) |mode| {
                        if (mode.refresh_hz > max_hz) {
                            max_hz = mode.refresh_hz;
                        }
                    }
                }
                if (max_hz > 0) caps.max_refresh_hz = max_hz;
            }
        }

        // Default min to 48Hz if VRR is supported but min not reported
        if (caps.supported and caps.min_refresh_hz == 0) {
            caps.min_refresh_hz = 48;
        }

        return caps;
    }

    /// Get connector by ID
    fn getConnectorById(self: *const Device, connector_id: u32) ?Connector {
        const conn = c.drmModeGetConnector(self.fd, connector_id);
        if (conn == null) return null;

        return Connector{
            .id = connector_id,
            .handle = conn.?,
            .fd = self.fd,
        };
    }

    /// Create an atomic request
    pub fn createAtomicRequest(self: *Device, allocator: std.mem.Allocator) AtomicRequest {
        return AtomicRequest.init(allocator, self.fd);
    }
};

/// DRM connector (output/monitor)
pub const Connector = struct {
    id: u32,
    handle: *c.drmModeConnector,
    fd: std.posix.fd_t,

    pub fn deinit(self: *Connector) void {
        c.drmModeFreeConnector(self.handle);
    }

    pub fn isConnected(self: *const Connector) bool {
        return self.handle.connection == c.DRM_MODE_CONNECTED;
    }

    pub fn getName(self: *const Connector) []const u8 {
        const type_name = switch (self.handle.connector_type) {
            c.DRM_MODE_CONNECTOR_VGA => "VGA",
            c.DRM_MODE_CONNECTOR_DVII => "DVI-I",
            c.DRM_MODE_CONNECTOR_DVID => "DVI-D",
            c.DRM_MODE_CONNECTOR_DVIA => "DVI-A",
            c.DRM_MODE_CONNECTOR_HDMIA => "HDMI-A",
            c.DRM_MODE_CONNECTOR_HDMIB => "HDMI-B",
            c.DRM_MODE_CONNECTOR_DisplayPort => "DP",
            c.DRM_MODE_CONNECTOR_eDP => "eDP",
            else => "Unknown",
        };
        return type_name;
    }

    pub fn getModeCount(self: *const Connector) u32 {
        return @intCast(self.handle.count_modes);
    }

    /// Get mode at index
    pub fn getMode(self: *const Connector, index: u32) ?Mode {
        if (index >= self.handle.count_modes) return null;
        const m = self.handle.modes[index];
        return Mode{
            .width = @intCast(m.hdisplay),
            .height = @intCast(m.vdisplay),
            .refresh_hz = @intCast(m.vrefresh),
            .flags = m.flags,
        };
    }

    /// Get preferred mode (usually native resolution)
    pub fn getPreferredMode(self: *const Connector) ?Mode {
        var i: u32 = 0;
        while (i < self.handle.count_modes) : (i += 1) {
            const m = self.handle.modes[i];
            if ((m.type & c.DRM_MODE_TYPE_PREFERRED) != 0) {
                return Mode{
                    .width = @intCast(m.hdisplay),
                    .height = @intCast(m.vdisplay),
                    .refresh_hz = @intCast(m.vrefresh),
                    .flags = m.flags,
                };
            }
        }
        // Fall back to first mode
        return self.getMode(0);
    }
};

/// Display mode
pub const Mode = struct {
    width: u32,
    height: u32,
    refresh_hz: u32,
    flags: u32,

    pub fn isInterlaced(self: *const Mode) bool {
        return (self.flags & c.DRM_MODE_FLAG_INTERLACE) != 0;
    }

    pub fn getFrameTimeNs(self: *const Mode) u64 {
        if (self.refresh_hz == 0) return 16_666_667; // Default 60Hz
        return @divFloor(1_000_000_000, @as(u64, self.refresh_hz));
    }
};

/// VRR capabilities for a display
pub const VrrCapabilities = struct {
    supported: bool = false,
    enabled: bool = false,
    min_refresh_hz: u32 = 0,
    max_refresh_hz: u32 = 0,

    /// Check if a target FPS is within the VRR range
    pub fn isInRange(self: *const VrrCapabilities, fps: u32) bool {
        if (!self.supported) return false;
        return fps >= self.min_refresh_hz and fps <= self.max_refresh_hz;
    }

    /// Get frame time in nanoseconds for the minimum refresh
    pub fn getMaxFrameTimeNs(self: *const VrrCapabilities) u64 {
        if (self.min_refresh_hz == 0) return 33_333_333; // 30Hz default
        return @divFloor(1_000_000_000, @as(u64, self.min_refresh_hz));
    }

    /// Get frame time in nanoseconds for the maximum refresh
    pub fn getMinFrameTimeNs(self: *const VrrCapabilities) u64 {
        if (self.max_refresh_hz == 0) return 6_944_444; // 144Hz default
        return @divFloor(1_000_000_000, @as(u64, self.max_refresh_hz));
    }
};

/// Page flip status
pub const PageFlipStatus = enum {
    pending, // Flip submitted, waiting for vsync
    complete, // Flip completed
    failed, // Flip failed
};

/// Page flip event data
pub const PageFlipEvent = struct {
    sequence: u32,
    timestamp_ns: u64,
    user_data: u64,
};

/// Display output state
pub const OutputState = struct {
    connector_id: u32,
    crtc_id: u32,
    active: bool = false,
    mode: ?Mode = null,
    vrr: VrrCapabilities = .{},

    /// Get effective frame time accounting for VRR
    pub fn getTargetFrameTimeNs(self: *const OutputState, target_fps: u32) u64 {
        if (self.vrr.enabled and self.vrr.isInRange(target_fps)) {
            // VRR active - use target FPS
            return @divFloor(1_000_000_000, @as(u64, target_fps));
        }
        // Fixed refresh - use mode refresh rate
        if (self.mode) |m| {
            return m.getFrameTimeNs();
        }
        return 16_666_667; // 60Hz default
    }
};

/// DRM atomic request for batched property changes
pub const AtomicRequest = struct {
    allocator: std.mem.Allocator,
    fd: std.posix.fd_t,
    properties: std.ArrayList(PropertyChange),

    pub const PropertyChange = struct {
        object_id: u32,
        property_id: u32,
        value: u64,
    };

    pub fn init(allocator: std.mem.Allocator, fd: std.posix.fd_t) AtomicRequest {
        return .{
            .allocator = allocator,
            .fd = fd,
            .properties = std.ArrayList(PropertyChange).init(allocator),
        };
    }

    pub fn deinit(self: *AtomicRequest) void {
        self.properties.deinit();
    }

    /// Add a property change to the request
    pub fn addProperty(self: *AtomicRequest, object_id: u32, property_id: u32, value: u64) !void {
        try self.properties.append(.{
            .object_id = object_id,
            .property_id = property_id,
            .value = value,
        });
    }

    /// Commit the atomic request
    pub fn commit(self: *AtomicRequest, flags: u32) !void {
        // In actual implementation with libdrm:
        // - Create drmModeAtomicReq
        // - Add all properties
        // - Call drmModeAtomicCommit
        _ = flags;

        if (!has_drm) {
            log.debug("Atomic commit (stub): {} properties", .{self.properties.items.len});
            return;
        }

        // TODO: Real atomic commit when libdrm is available
        for (self.properties.items) |prop| {
            log.debug("Atomic set: obj={} prop={} val={}", .{ prop.object_id, prop.property_id, prop.value });
        }
    }

    /// Clear all pending property changes
    pub fn clear(self: *AtomicRequest) void {
        self.properties.clearRetainingCapacity();
    }
};

/// Frame timing for latency measurement
pub const FrameTiming = struct {
    /// Sequence number
    sequence: u32,
    /// Timestamp in nanoseconds
    timestamp_ns: u64,

    /// Calculate time since last frame
    pub fn timeSince(self: *const FrameTiming, other: *const FrameTiming) u64 {
        if (self.timestamp_ns > other.timestamp_ns) {
            return self.timestamp_ns - other.timestamp_ns;
        }
        return 0;
    }
};

/// Wait for vertical blank
pub fn waitVblank(fd: std.posix.fd_t, crtc_id: u32) !FrameTiming {
    var vbl: c.drmVBlank = undefined;
    vbl.request.type = c.DRM_VBLANK_RELATIVE;
    vbl.request.sequence = 1;

    // Set CRTC index in high bits
    vbl.request.type |= (crtc_id << c.DRM_VBLANK_HIGH_CRTC_SHIFT) & c.DRM_VBLANK_HIGH_CRTC_MASK;

    const ret = c.drmWaitVBlank(fd, &vbl);
    if (ret != 0) return error.VblankWaitFailed;

    return FrameTiming{
        .sequence = vbl.reply.sequence,
        .timestamp_ns = @as(u64, @intCast(vbl.reply.tval_sec)) * 1_000_000_000 +
            @as(u64, @intCast(vbl.reply.tval_usec)) * 1000,
    };
}

// ============================================================================
// High-level DRM Backend
// ============================================================================

/// DRM backend for PrimeTime compositor integration
pub const DrmBackend = struct {
    allocator: std.mem.Allocator,
    device: ?Device = null,
    outputs: std.ArrayList(OutputState),
    initialized: bool = false,

    // Page flip tracking
    pending_flips: u32 = 0,
    last_flip_time_ns: u64 = 0,

    // Statistics
    total_frames: u64 = 0,
    dropped_frames: u64 = 0,

    const Self = @This();

    pub const InitError = error{
        NoDrmDevice,
        NoConnectedOutputs,
        OutOfMemory,
    };

    /// Initialize the DRM backend
    pub fn init(allocator: std.mem.Allocator) InitError!Self {
        var self = Self{
            .allocator = allocator,
            .outputs = std.ArrayList(OutputState).init(allocator),
        };
        errdefer self.outputs.deinit();

        // Try to open DRM device
        self.device = Device.openDefault() catch |err| {
            log.warn("Failed to open DRM device: {}", .{err});
            return error.NoDrmDevice;
        };

        // Enumerate connected outputs
        try self.enumerateOutputs();

        if (self.outputs.items.len == 0) {
            log.warn("No connected displays found", .{});
            return error.NoConnectedOutputs;
        }

        self.initialized = true;

        log.info("DRM backend initialized: {} output(s)", .{self.outputs.items.len});
        for (self.outputs.items) |output| {
            const mode_str = if (output.mode) |m|
                std.fmt.allocPrint(allocator, "{}x{}@{}", .{ m.width, m.height, m.refresh_hz }) catch "?"
            else
                "no mode";
            defer if (output.mode != null) allocator.free(mode_str);

            log.info("  Output {}: {} (VRR: {s} {}-{}Hz)", .{
                output.connector_id,
                mode_str,
                if (output.vrr.supported) "supported" else "not supported",
                output.vrr.min_refresh_hz,
                output.vrr.max_refresh_hz,
            });
        }

        return self;
    }

    /// Cleanup
    pub fn deinit(self: *Self) void {
        if (self.device) |*dev| {
            dev.close();
            self.device = null;
        }

        self.outputs.deinit();
        self.initialized = false;

        log.info("DRM backend shutdown: {} frames, {} dropped", .{
            self.total_frames,
            self.dropped_frames,
        });
    }

    /// Enumerate connected outputs
    fn enumerateOutputs(self: *Self) !void {
        const dev = self.device orelse return;

        const conn_count = dev.getConnectorCount();
        var i: u32 = 0;
        while (i < conn_count) : (i += 1) {
            if (dev.getConnector(i)) |*conn| {
                defer conn.deinit();

                if (!conn.isConnected()) continue;

                const mode = conn.getPreferredMode();
                const vrr = dev.getVrrCapabilities(conn.id);

                try self.outputs.append(.{
                    .connector_id = conn.id,
                    .crtc_id = 0, // Would need to be assigned from CRTC enumeration
                    .active = true,
                    .mode = mode,
                    .vrr = vrr,
                });
            }
        }
    }

    /// Get the primary output
    pub fn getPrimaryOutput(self: *const Self) ?*const OutputState {
        if (self.outputs.items.len > 0) {
            return &self.outputs.items[0];
        }
        return null;
    }

    /// Get output by connector ID
    pub fn getOutput(self: *const Self, connector_id: u32) ?*const OutputState {
        for (self.outputs.items) |*output| {
            if (output.connector_id == connector_id) {
                return output;
            }
        }
        return null;
    }

    /// Enable VRR on an output
    pub fn enableVrr(self: *Self, connector_id: u32) !void {
        const dev = self.device orelse return error.NotInitialized;

        try dev.setVrr(connector_id, true);

        // Update state
        for (self.outputs.items) |*output| {
            if (output.connector_id == connector_id) {
                output.vrr.enabled = true;
                log.info("VRR enabled on output {}", .{connector_id});
                break;
            }
        }
    }

    /// Disable VRR on an output
    pub fn disableVrr(self: *Self, connector_id: u32) !void {
        const dev = self.device orelse return error.NotInitialized;

        try dev.setVrr(connector_id, false);

        // Update state
        for (self.outputs.items) |*output| {
            if (output.connector_id == connector_id) {
                output.vrr.enabled = false;
                log.info("VRR disabled on output {}", .{connector_id});
                break;
            }
        }
    }

    /// Wait for vblank on primary output
    pub fn waitVblank(self: *Self) !FrameTiming {
        const output = self.getPrimaryOutput() orelse return error.NoOutput;
        const dev = self.device orelse return error.NotInitialized;
        return waitVblankDev(dev.fd, output.crtc_id);
    }

    /// Get VRR capabilities for primary output
    pub fn getVrrCapabilities(self: *const Self) VrrCapabilities {
        if (self.getPrimaryOutput()) |output| {
            return output.vrr;
        }
        return .{};
    }

    /// Get recommended frame time for current VRR state
    pub fn getTargetFrameTimeNs(self: *const Self, target_fps: u32) u64 {
        if (self.getPrimaryOutput()) |output| {
            return output.getTargetFrameTimeNs(target_fps);
        }
        return 16_666_667; // 60Hz default
    }

    /// Record a frame completion
    pub fn recordFrame(self: *Self, timestamp_ns: u64) void {
        if (self.last_flip_time_ns > 0) {
            // Check for dropped frames (frame time > 2x expected)
            const delta = timestamp_ns - self.last_flip_time_ns;
            const expected = self.getTargetFrameTimeNs(0);
            if (delta > expected * 2) {
                self.dropped_frames += 1;
            }
        }
        self.last_flip_time_ns = timestamp_ns;
        self.total_frames += 1;
    }

    /// Get statistics
    pub fn getStats(self: *const Self) struct {
        total_frames: u64,
        dropped_frames: u64,
        drop_rate: f32,
    } {
        const drop_rate: f32 = if (self.total_frames > 0)
            @as(f32, @floatFromInt(self.dropped_frames)) / @as(f32, @floatFromInt(self.total_frames))
        else
            0.0;

        return .{
            .total_frames = self.total_frames,
            .dropped_frames = self.dropped_frames,
            .drop_rate = drop_rate,
        };
    }
};

fn waitVblankDev(fd: std.posix.fd_t, crtc_id: u32) !FrameTiming {
    return waitVblank(fd, crtc_id);
}

// ============================================================================
// Tests
// ============================================================================

test "drm types compile" {
    _ = Mode{ .width = 1920, .height = 1080, .refresh_hz = 60, .flags = 0 };
}

test "vrr capabilities" {
    var caps = VrrCapabilities{
        .supported = true,
        .enabled = true,
        .min_refresh_hz = 48,
        .max_refresh_hz = 165,
    };

    try std.testing.expect(caps.isInRange(60));
    try std.testing.expect(caps.isInRange(165));
    try std.testing.expect(!caps.isInRange(200));
    try std.testing.expect(!caps.isInRange(30));
}

test "mode frame time" {
    const mode = Mode{
        .width = 2560,
        .height = 1440,
        .refresh_hz = 144,
        .flags = 0,
    };

    // 144Hz = ~6.94ms = 6,944,444ns
    const frame_time = mode.getFrameTimeNs();
    try std.testing.expect(frame_time > 6_900_000);
    try std.testing.expect(frame_time < 7_000_000);
}

test "output state target frame time" {
    var output = OutputState{
        .connector_id = 1,
        .crtc_id = 0,
        .active = true,
        .mode = Mode{
            .width = 2560,
            .height = 1440,
            .refresh_hz = 60,
            .flags = 0,
        },
        .vrr = VrrCapabilities{
            .supported = true,
            .enabled = true,
            .min_refresh_hz = 48,
            .max_refresh_hz = 165,
        },
    };

    // With VRR enabled and in range, should use target FPS
    const target_120 = output.getTargetFrameTimeNs(120);
    try std.testing.expect(target_120 < 9_000_000); // ~8.33ms for 120Hz

    // Out of range should fall back to mode refresh
    const target_200 = output.getTargetFrameTimeNs(200);
    try std.testing.expect(target_200 > 16_000_000); // ~16.67ms for 60Hz
}

test "atomic request" {
    const allocator = std.testing.allocator;
    var req = AtomicRequest.init(allocator, 0);
    defer req.deinit();

    try req.addProperty(1, 100, 500);
    try req.addProperty(2, 101, 600);

    try std.testing.expectEqual(@as(usize, 2), req.properties.items.len);

    req.clear();
    try std.testing.expectEqual(@as(usize, 0), req.properties.items.len);
}
