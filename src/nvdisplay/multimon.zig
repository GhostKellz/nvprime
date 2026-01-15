//! nvdisplay/multimon - Multi-Monitor Orchestration
//!
//! Manage multiple displays, arrangements, and profiles.
//! Supports Wayland compositors (primary) and X11 (fallback).
//!
//! Wayland: Uses compositor-specific tools (kscreen-doctor, hyprctl, swaymsg)
//! X11: Uses xrandr

const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const posix = std.posix;
const nvdisplay = @import("nvdisplay.zig");

/// Display server type
pub const DisplayServer = enum {
    wayland_kwin, // KDE Plasma
    wayland_hyprland,
    wayland_sway,
    wayland_gnome,
    wayland_other,
    x11,
    unknown,

    pub fn isWayland(self: DisplayServer) bool {
        return switch (self) {
            .wayland_kwin, .wayland_hyprland, .wayland_sway, .wayland_gnome, .wayland_other => true,
            else => false,
        };
    }
};

/// Detect current display server
pub fn detectDisplayServer() DisplayServer {
    // Check for Wayland first (preferred)
    if (std.c.getenv("WAYLAND_DISPLAY") != null) {
        // Wayland session - detect compositor
        if (std.c.getenv("HYPRLAND_INSTANCE_SIGNATURE") != null) {
            return .wayland_hyprland;
        }
        if (std.c.getenv("SWAYSOCK") != null) {
            return .wayland_sway;
        }
        if (std.c.getenv("XDG_CURRENT_DESKTOP")) |desktop| {
            if (mem.indexOf(u8, desktop, "KDE") != null) {
                return .wayland_kwin;
            }
            if (mem.indexOf(u8, desktop, "GNOME") != null) {
                return .wayland_gnome;
            }
        }
        return .wayland_other;
    }

    // X11 fallback
    if (std.c.getenv("DISPLAY") != null) {
        return .x11;
    }

    return .unknown;
}

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

/// Run xrandr command and return output
fn runXrandr(allocator: mem.Allocator, args: []const []const u8) ![]const u8 {
    var argv = std.ArrayListUnmanaged([]const u8){};
    defer argv.deinit(allocator);

    try argv.append(allocator, "xrandr");
    for (args) |arg| {
        try argv.append(allocator, arg);
    }

    const result = std.process.run(allocator, std.Io.Threaded.global_single_threaded.io(), .{
        .argv = argv.items,
    }) catch return error.XrandrError;
    defer allocator.free(result.stderr);

    if (result.term != .exited or result.term.exited != 0) {
        allocator.free(result.stdout);
        return error.XrandrError;
    }

    return result.stdout;
}

/// Parse xrandr output to get display layout
fn parseXrandrOutput(allocator: mem.Allocator, output: []const u8) !Layout {
    var layout = Layout.init();

    var lines = mem.splitScalar(u8, output, '\n');
    var current_entry: ?*LayoutEntry = null;

    while (lines.next()) |line| {
        // Skip empty lines
        if (line.len == 0) continue;

        // Connected display line format: "DP-1 connected primary 2560x1440+0+0 ..."
        if (mem.indexOf(u8, line, " connected") != null) {
            if (layout.entry_count >= layout.entries.len) break;

            var entry = &layout.entries[layout.entry_count];
            @memset(&entry.display_name, 0);

            // Parse display name (first word)
            const name_end = mem.indexOf(u8, line, " ") orelse line.len;
            const name_len = @min(name_end, entry.display_name.len - 1);
            @memcpy(entry.display_name[0..name_len], line[0..name_len]);

            entry.enabled = true;
            entry.rotation = .normal;

            // Check for primary
            if (mem.indexOf(u8, line, "primary") != null) {
                layout.primary_index = layout.entry_count;
                entry.position = .primary;
            } else {
                entry.position = .right; // Default
            }

            // Parse geometry: WIDTHxHEIGHT+X+Y
            var iter = mem.splitScalar(u8, line, ' ');
            while (iter.next()) |part| {
                // Look for geometry pattern
                if (mem.indexOf(u8, part, "x") != null and mem.indexOf(u8, part, "+") != null) {
                    // Parse WIDTHxHEIGHT+X+Y
                    const x_pos = mem.indexOf(u8, part, "x") orelse continue;
                    const plus1 = mem.indexOf(u8, part, "+") orelse continue;
                    const plus2 = mem.lastIndexOf(u8, part, "+") orelse continue;

                    entry.width = std.fmt.parseInt(u32, part[0..x_pos], 10) catch 0;
                    entry.height = std.fmt.parseInt(u32, part[x_pos + 1 .. plus1], 10) catch 0;
                    entry.x_offset = std.fmt.parseInt(i32, part[plus1 + 1 .. plus2], 10) catch 0;
                    entry.y_offset = std.fmt.parseInt(i32, part[plus2 + 1 ..], 10) catch 0;
                    break;
                }
            }

            // Parse rotation
            if (mem.indexOf(u8, line, "left") != null) {
                entry.rotation = .left;
            } else if (mem.indexOf(u8, line, "right") != null) {
                entry.rotation = .right;
            } else if (mem.indexOf(u8, line, "inverted") != null) {
                entry.rotation = .inverted;
            }

            current_entry = entry;
            layout.entry_count += 1;
        }
        // Mode line with * indicates current mode: "   2560x1440     59.95*+"
        else if (current_entry != null and mem.indexOf(u8, line, "*") != null) {
            // Parse refresh rate
            var iter = mem.splitScalar(u8, line, ' ');
            while (iter.next()) |part| {
                if (part.len == 0) continue;
                if (mem.indexOf(u8, part, "*") != null) {
                    // Remove * and + suffixes
                    var rate_str = part;
                    if (mem.indexOf(u8, rate_str, "*")) |idx| {
                        rate_str = rate_str[0..idx];
                    }
                    const rate_f = std.fmt.parseFloat(f32, rate_str) catch 60.0;
                    current_entry.?.refresh_hz = @intFromFloat(rate_f);
                    break;
                }
            }
        }
    }

    // Determine arrangement
    if (layout.entry_count == 1) {
        layout.arrangement = .single;
    } else if (layout.entry_count > 1) {
        // Check if mirrored (same position)
        var all_same_pos = true;
        for (layout.entries[1..layout.entry_count]) |entry| {
            if (entry.x_offset != layout.entries[0].x_offset or
                entry.y_offset != layout.entries[0].y_offset)
            {
                all_same_pos = false;
                break;
            }
        }
        layout.arrangement = if (all_same_pos) .mirror else .extend;
    }

    _ = allocator;
    return layout;
}

/// Run generic command and return output
fn runCommand(allocator: mem.Allocator, argv: []const []const u8) ![]const u8 {
    const result = std.process.run(allocator, std.Io.Threaded.global_single_threaded.io(), .{
        .argv = argv,
    }) catch return error.CommandError;
    defer allocator.free(result.stderr);

    if (result.term != .exited or result.term.exited != 0) {
        allocator.free(result.stdout);
        return error.CommandError;
    }

    return result.stdout;
}

/// Parse Hyprland monitors output (JSON)
fn parseHyprlandOutput(allocator: mem.Allocator, output: []const u8) !Layout {
    var layout = Layout.init();

    // Hyprctl monitors output is JSON array
    // Simple parsing - look for name, width, height, x, y
    var lines = mem.splitScalar(u8, output, '\n');
    var current_entry: ?*LayoutEntry = null;

    while (lines.next()) |line| {
        const trimmed = mem.trim(u8, line, " \t");

        if (mem.startsWith(u8, trimmed, "\"name\":")) {
            if (layout.entry_count >= layout.entries.len) break;
            var entry = &layout.entries[layout.entry_count];
            @memset(&entry.display_name, 0);

            // Extract name between quotes
            if (mem.indexOf(u8, trimmed[7..], "\"")) |start| {
                const name_start = 7 + start + 1;
                if (mem.indexOf(u8, trimmed[name_start..], "\"")) |end| {
                    const name = trimmed[name_start .. name_start + end];
                    const name_len = @min(name.len, entry.display_name.len - 1);
                    @memcpy(entry.display_name[0..name_len], name[0..name_len]);
                }
            }

            entry.enabled = true;
            entry.rotation = .normal;
            entry.position = if (layout.entry_count == 0) .primary else .right;
            current_entry = entry;
            layout.entry_count += 1;
        } else if (current_entry != null) {
            if (mem.startsWith(u8, trimmed, "\"width\":")) {
                const val = mem.trim(u8, trimmed[8..], " ,");
                current_entry.?.width = std.fmt.parseInt(u32, val, 10) catch 0;
            } else if (mem.startsWith(u8, trimmed, "\"height\":")) {
                const val = mem.trim(u8, trimmed[9..], " ,");
                current_entry.?.height = std.fmt.parseInt(u32, val, 10) catch 0;
            } else if (mem.startsWith(u8, trimmed, "\"x\":")) {
                const val = mem.trim(u8, trimmed[4..], " ,");
                current_entry.?.x_offset = std.fmt.parseInt(i32, val, 10) catch 0;
            } else if (mem.startsWith(u8, trimmed, "\"y\":")) {
                const val = mem.trim(u8, trimmed[4..], " ,");
                current_entry.?.y_offset = std.fmt.parseInt(i32, val, 10) catch 0;
            } else if (mem.startsWith(u8, trimmed, "\"refreshRate\":")) {
                const val = mem.trim(u8, trimmed[14..], " ,");
                const rate_f = std.fmt.parseFloat(f32, val) catch 60.0;
                current_entry.?.refresh_hz = @intFromFloat(rate_f);
            }
        }
    }

    layout.arrangement = if (layout.entry_count <= 1) .single else .extend;
    _ = allocator;
    return layout;
}

/// Parse Sway output (swaymsg -t get_outputs)
fn parseSwayOutput(allocator: mem.Allocator, output: []const u8) !Layout {
    // Similar JSON parsing to Hyprland
    return parseHyprlandOutput(allocator, output);
}

/// Parse kscreen-doctor output
fn parseKwinOutput(allocator: mem.Allocator, output: []const u8) !Layout {
    var layout = Layout.init();

    var lines = mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        // kscreen-doctor output format: "Output: 1 DP-1 connected..."
        if (mem.startsWith(u8, line, "Output:")) {
            if (layout.entry_count >= layout.entries.len) break;
            var entry = &layout.entries[layout.entry_count];
            @memset(&entry.display_name, 0);

            // Parse the line
            var iter = mem.splitScalar(u8, line, ' ');
            _ = iter.next(); // Skip "Output:"
            _ = iter.next(); // Skip number

            if (iter.next()) |name| {
                const name_len = @min(name.len, entry.display_name.len - 1);
                @memcpy(entry.display_name[0..name_len], name[0..name_len]);
            }

            entry.enabled = mem.indexOf(u8, line, "enabled") != null;
            entry.rotation = .normal;
            entry.position = if (layout.entry_count == 0) .primary else .right;

            layout.entry_count += 1;
        }
    }

    layout.arrangement = if (layout.entry_count <= 1) .single else .extend;
    _ = allocator;
    return layout;
}

/// Get current layout
/// Auto-detects display server and uses appropriate tool
pub fn getLayout() !Layout {
    const allocator = std.heap.page_allocator;
    const server = detectDisplayServer();

    switch (server) {
        .wayland_hyprland => {
            const output = runCommand(allocator, &.{ "hyprctl", "monitors", "-j" }) catch {
                // Fallback to xrandr via XWayland
                const xout = try runXrandr(allocator, &.{});
                defer allocator.free(xout);
                return parseXrandrOutput(allocator, xout);
            };
            defer allocator.free(output);
            return parseHyprlandOutput(allocator, output);
        },
        .wayland_sway => {
            const output = runCommand(allocator, &.{ "swaymsg", "-t", "get_outputs" }) catch {
                const xout = try runXrandr(allocator, &.{});
                defer allocator.free(xout);
                return parseXrandrOutput(allocator, xout);
            };
            defer allocator.free(output);
            return parseSwayOutput(allocator, output);
        },
        .wayland_kwin => {
            const output = runCommand(allocator, &.{ "kscreen-doctor", "-o" }) catch {
                const xout = try runXrandr(allocator, &.{});
                defer allocator.free(xout);
                return parseXrandrOutput(allocator, xout);
            };
            defer allocator.free(output);
            return parseKwinOutput(allocator, output);
        },
        .wayland_gnome => {
            // GNOME uses gnome-randr or gsettings
            const output = runCommand(allocator, &.{ "gnome-randr", "query" }) catch {
                const xout = try runXrandr(allocator, &.{});
                defer allocator.free(xout);
                return parseXrandrOutput(allocator, xout);
            };
            defer allocator.free(output);
            return parseXrandrOutput(allocator, output); // Similar format
        },
        .x11, .wayland_other, .unknown => {
            const output = try runXrandr(allocator, &.{});
            defer allocator.free(output);
            return parseXrandrOutput(allocator, output);
        },
    }
}

/// Run xrandr command with fixed arguments
fn runXrandrCmd(args: []const []const u8) !void {
    const allocator = std.heap.page_allocator;

    var argv = std.ArrayListUnmanaged([]const u8){};
    defer argv.deinit(allocator);

    try argv.append(allocator, "xrandr");
    for (args) |arg| {
        try argv.append(allocator, arg);
    }

    const result = std.process.run(allocator, std.Io.Threaded.global_single_threaded.io(), .{
        .argv = argv.items,
    }) catch return error.XrandrError;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term != .exited or result.term.exited != 0) {
        return error.XrandrError;
    }
}

/// Apply layout
/// Uses xrandr to configure all displays in the layout
pub fn setLayout(layout: Layout) !void {
    for (layout.entries[0..layout.entry_count], 0..) |entry, i| {
        const name = entry.getName();

        if (!entry.enabled) {
            // Disable output
            try runXrandrCmd(&.{ "--output", name, "--off" });
            continue;
        }

        // Build mode string
        var mode_buf: [32]u8 = undefined;
        const mode = std.fmt.bufPrint(&mode_buf, "{d}x{d}", .{ entry.width, entry.height }) catch continue;

        // Build position string
        var pos_buf: [32]u8 = undefined;
        const pos = std.fmt.bufPrint(&pos_buf, "{d}x{d}", .{ entry.x_offset, entry.y_offset }) catch continue;

        // Build rotation string
        const rotation = switch (entry.rotation) {
            .normal => "normal",
            .left => "left",
            .inverted => "inverted",
            .right => "right",
        };

        // Build refresh string
        var rate_buf: [16]u8 = undefined;
        const rate = std.fmt.bufPrint(&rate_buf, "{d}", .{entry.refresh_hz}) catch "60";

        if (i == layout.primary_index) {
            try runXrandrCmd(&.{ "--output", name, "--mode", mode, "--pos", pos, "--rotate", rotation, "--rate", rate, "--primary" });
        } else {
            try runXrandrCmd(&.{ "--output", name, "--mode", mode, "--pos", pos, "--rotate", rotation, "--rate", rate });
        }
    }
}

/// Set primary display
pub fn setPrimary(display_name: []const u8) !void {
    try runXrandrCmd(&.{ "--output", display_name, "--primary" });
}

/// Enable a display with auto mode
pub fn enableDisplay(display_name: []const u8) !void {
    try runXrandrCmd(&.{ "--output", display_name, "--auto" });
}

/// Disable a display
pub fn disableDisplay(display_name: []const u8) !void {
    try runXrandrCmd(&.{ "--output", display_name, "--off" });
}

/// Position a display relative to another
pub fn positionDisplay(display_name: []const u8, position: Position, relative_to: []const u8) !void {
    const pos_arg = switch (position) {
        .primary => "--same-as", // Primary means same as
        .left => "--left-of",
        .right => "--right-of",
        .above => "--above",
        .below => "--below",
    };

    try runXrandrCmd(&.{ "--output", display_name, pos_arg, relative_to });
}

/// Set display rotation
pub fn setRotation(display_name: []const u8, rotation: Rotation) !void {
    const rot_arg = switch (rotation) {
        .normal => "normal",
        .left => "left",
        .inverted => "inverted",
        .right => "right",
    };

    try runXrandrCmd(&.{ "--output", display_name, "--rotate", rot_arg });
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

/// Global profile store (in-memory for now)
var g_profile_store = ProfileStore.init();

/// Save current layout as profile
pub fn saveProfile(name: []const u8) !void {
    const layout = try getLayout();
    try g_profile_store.save(name, layout);
}

/// Load and apply a saved profile
pub fn loadProfile(name: []const u8) !void {
    const profile = g_profile_store.find(name) orelse return error.ProfileNotFound;
    try setLayout(profile.layout);
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

/// Run nvidia-settings assignment
fn runNvidiaSettingsAssign(assignment: []const u8) !void {
    const allocator = std.heap.page_allocator;

    const result = std.process.run(allocator, std.Io.Threaded.global_single_threaded.io(), .{
        .argv = &.{ "nvidia-settings", "-a", assignment },
    }) catch return error.NvidiaSettingsError;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term != .exited or result.term.exited != 0) {
        return error.NvidiaSettingsError;
    }
}

/// Configure NVIDIA Surround
/// Uses nvidia-settings for multi-display spanning configuration
pub fn configureSurround(config: SurroundConfig) !void {
    if (!config.enabled) {
        // Disable Surround - reset to separate displays
        runNvidiaSettingsAssign("BaseMosaic=0") catch {};
        return;
    }

    // Enable Surround (BaseMosaic)
    // nvidia-settings format: BaseMosaic=<rows>x<cols>,<display0>,<display1>,...
    var mosaic_buf: [256]u8 = undefined;

    // Determine rows/cols based on display count (typically 1 row for horizontal)
    const cols = config.display_count;
    const rows: usize = 1;

    var offset: usize = 0;
    const prefix = std.fmt.bufPrint(mosaic_buf[offset..], "BaseMosaic={d}x{d}", .{ rows, cols }) catch return error.FormatError;
    offset += prefix.len;

    // Add display names
    for (config.displays[0..config.display_count]) |display| {
        const name = mem.sliceTo(&display, 0);
        const disp = std.fmt.bufPrint(mosaic_buf[offset..], ",{s}", .{name}) catch return error.FormatError;
        offset += disp.len;
    }

    try runNvidiaSettingsAssign(mosaic_buf[0..offset]);

    // Set bezel correction if specified
    if (config.bezel_correction_x != 0 or config.bezel_correction_y != 0) {
        var bezel_buf: [128]u8 = undefined;
        const bezel = std.fmt.bufPrint(&bezel_buf, "BaseMosaicBezelCorrection={d}x{d}", .{ config.bezel_correction_x, config.bezel_correction_y }) catch return error.FormatError;
        runNvidiaSettingsAssign(bezel) catch {};
    }
}

test "layout" {
    var layout = Layout.init();
    try std.testing.expectEqual(@as(usize, 0), layout.entry_count);
}
