//! DRM/KMS backend for PrimeTime
//!
//! Direct Rendering Manager interface for display control.
//! Handles monitor enumeration, mode setting, and VRR.
//!
//! Note: This module requires libdrm. Build with -Ddrm=true to enable.

const std = @import("std");
const builtin = @import("builtin");

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

test "drm types compile" {
    _ = Mode{ .width = 1920, .height = 1080, .refresh_hz = 60, .flags = 0 };
}
