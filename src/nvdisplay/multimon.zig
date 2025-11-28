//! nvdisplay/multimon - Multi-Monitor Orchestration
//!
//! Manage multiple displays, arrangements, and profiles.

const std = @import("std");
const nvdisplay = @import("nvdisplay.zig");

/// Display arrangement
pub const Arrangement = enum {
    single, // One display active
    extend, // Extended desktop
    mirror, // Mirrored/clone
    surround, // NVIDIA Surround (single logical display)
};

/// Display position relative to primary
pub const Position = enum {
    primary,
    left,
    right,
    above,
    below,
};

/// Display layout entry
pub const LayoutEntry = struct {
    display_name: [32]u8,
    position: Position,
    x_offset: i32,
    y_offset: i32,
    width: u32,
    height: u32,
    refresh_hz: u32,
    rotation: Rotation,
    enabled: bool,

    pub fn getName(self: *const LayoutEntry) []const u8 {
        return std.mem.sliceTo(&self.display_name, 0);
    }
};

/// Display rotation
pub const Rotation = enum {
    normal, // 0 degrees
    left, // 90 degrees CCW
    inverted, // 180 degrees
    right, // 270 degrees CCW (90 CW)

    pub fn degrees(self: Rotation) u32 {
        return switch (self) {
            .normal => 0,
            .left => 90,
            .inverted => 180,
            .right => 270,
        };
    }
};

/// Multi-monitor layout
pub const Layout = struct {
    entries: [8]LayoutEntry,
    entry_count: usize,
    arrangement: Arrangement,
    primary_index: usize,

    pub fn init() Layout {
        return Layout{
            .entries = undefined,
            .entry_count = 0,
            .arrangement = .single,
            .primary_index = 0,
        };
    }

    pub fn getPrimary(self: *const Layout) ?*const LayoutEntry {
        if (self.entry_count == 0) return null;
        return &self.entries[self.primary_index];
    }

    pub fn totalWidth(self: *const Layout) u32 {
        var max_x: i32 = 0;
        for (self.entries[0..self.entry_count]) |entry| {
            if (!entry.enabled) continue;
            const right = entry.x_offset + @as(i32, @intCast(entry.width));
            if (right > max_x) max_x = right;
        }
        return if (max_x > 0) @intCast(max_x) else 0;
    }

    pub fn totalHeight(self: *const Layout) u32 {
        var max_y: i32 = 0;
        for (self.entries[0..self.entry_count]) |entry| {
            if (!entry.enabled) continue;
            const bottom = entry.y_offset + @as(i32, @intCast(entry.height));
            if (bottom > max_y) max_y = bottom;
        }
        return if (max_y > 0) @intCast(max_y) else 0;
    }
};

/// Get current layout
pub fn getLayout() !Layout {
    // TODO: Query via xrandr or wlr-output-management
    return error.NotSupported;
}

/// Apply layout
pub fn setLayout(layout: Layout) !void {
    _ = layout;
    return error.NotSupported;
}

/// Set primary display
pub fn setPrimary(display_name: []const u8) !void {
    _ = display_name;
    // xrandr --output DP-1 --primary
    return error.NotSupported;
}

/// Enable a display
pub fn enableDisplay(display_name: []const u8) !void {
    _ = display_name;
    return error.NotSupported;
}

/// Disable a display
pub fn disableDisplay(display_name: []const u8) !void {
    _ = display_name;
    return error.NotSupported;
}

/// Position a display relative to another
pub fn positionDisplay(display_name: []const u8, position: Position, relative_to: []const u8) !void {
    _ = display_name;
    _ = position;
    _ = relative_to;
    return error.NotSupported;
}

/// Set display rotation
pub fn setRotation(display_name: []const u8, rotation: Rotation) !void {
    _ = display_name;
    _ = rotation;
    return error.NotSupported;
}

/// Multi-monitor profile
pub const Profile = struct {
    name: [64]u8,
    layout: Layout,

    pub fn getName(self: *const Profile) []const u8 {
        return std.mem.sliceTo(&self.name, 0);
    }
};

/// Profile storage
pub const ProfileStore = struct {
    profiles: [16]Profile,
    profile_count: usize,

    pub fn init() ProfileStore {
        return ProfileStore{
            .profiles = undefined,
            .profile_count = 0,
        };
    }

    pub fn save(self: *ProfileStore, name: []const u8, layout: Layout) !void {
        if (self.profile_count >= 16) return error.StoreFull;
        var profile = &self.profiles[self.profile_count];
        @memset(&profile.name, 0);
        @memcpy(profile.name[0..@min(name.len, 63)], name[0..@min(name.len, 63)]);
        profile.layout = layout;
        self.profile_count += 1;
    }

    pub fn find(self: *const ProfileStore, name: []const u8) ?*const Profile {
        for (self.profiles[0..self.profile_count]) |*profile| {
            if (std.mem.eql(u8, profile.getName(), name)) {
                return profile;
            }
        }
        return null;
    }
};

/// Save current layout as profile
pub fn saveProfile(name: []const u8) !void {
    _ = name;
    return error.NotSupported;
}

/// Load and apply a saved profile
pub fn loadProfile(name: []const u8) !void {
    _ = name;
    return error.NotSupported;
}

/// NVIDIA Surround configuration
pub const SurroundConfig = struct {
    enabled: bool,
    displays: [3][32]u8,
    display_count: usize,
    bezel_correction_x: i32,
    bezel_correction_y: i32,
    resolution_per_display: struct {
        width: u32,
        height: u32,
    },
};

/// Configure NVIDIA Surround
pub fn configureSurround(config: SurroundConfig) !void {
    _ = config;
    // Requires nvidia-settings Surround configuration
    return error.NotSupported;
}

test "layout" {
    var layout = Layout.init();
    try std.testing.expectEqual(@as(usize, 0), layout.entry_count);
}
