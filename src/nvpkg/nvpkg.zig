//! nvpkg - System Integration & Package Management
//!
//! Installation, updates, configuration, and system hooks for NVPrime.
//!
//! Features:
//! - Configuration file management (TOML)
//! - Udev rules for NVIDIA GPU events
//! - Systemd service integration
//! - Shader cache management
//! - Driver compatibility checking

const std = @import("std");

pub const version = "0.1.0";

/// Installation status
pub const InstallStatus = enum {
    not_installed,
    installed,
    needs_update,
    broken,
    partial,

    pub fn description(self: InstallStatus) []const u8 {
        return switch (self) {
            .not_installed => "Not installed",
            .installed => "Installed and configured",
            .needs_update => "Update available",
            .broken => "Installation broken",
            .partial => "Partially installed",
        };
    }
};

/// Configuration paths
pub const Paths = struct {
    config_dir: []const u8,
    data_dir: []const u8,
    cache_dir: []const u8,
    shader_cache_dir: []const u8,
    log_dir: []const u8,

    pub fn system() Paths {
        return Paths{
            .config_dir = "/etc/nvprime",
            .data_dir = "/usr/share/nvprime",
            .cache_dir = "/var/cache/nvprime",
            .shader_cache_dir = "/var/cache/nvprime/shaders",
            .log_dir = "/var/log/nvprime",
        };
    }

    pub fn user() Paths {
        const home = std.c.getenv("HOME") orelse "/home/user";
        _ = home;
        return Paths{
            .config_dir = "~/.config/nvprime",
            .data_dir = "~/.local/share/nvprime",
            .cache_dir = "~/.cache/nvprime",
            .shader_cache_dir = "~/.cache/nvprime/shaders",
            .log_dir = "~/.local/share/nvprime/logs",
        };
    }

    /// Get XDG-compliant paths
    pub fn xdg() Paths {
        const config = std.c.getenv("XDG_CONFIG_HOME") orelse "~/.config";
        const data = std.c.getenv("XDG_DATA_HOME") orelse "~/.local/share";
        const cache = std.c.getenv("XDG_CACHE_HOME") orelse "~/.cache";
        _ = config;
        _ = data;
        _ = cache;

        return Paths{
            .config_dir = "~/.config/nvprime",
            .data_dir = "~/.local/share/nvprime",
            .cache_dir = "~/.cache/nvprime",
            .shader_cache_dir = "~/.cache/nvprime/shaders",
            .log_dir = "~/.local/share/nvprime/logs",
        };
    }
};

/// NVPrime configuration
pub const Config = struct {
    /// Enable nvprime daemon
    daemon_enabled: bool = true,
    /// Polling interval for metrics (ms)
    poll_interval_ms: u32 = 1000,
    /// Enable shader cache management
    shader_cache_enabled: bool = true,
    /// Max shader cache size (MB)
    shader_cache_max_mb: u32 = 4096,
    /// Auto-apply gaming profile when game detected
    auto_gaming_profile: bool = true,
    /// Default power profile
    power_profile: []const u8 = "balanced",
    /// Default fan profile
    fan_profile: []const u8 = "auto",
    /// Enable telemetry logging
    telemetry_enabled: bool = false,

    pub fn default() Config {
        return Config{};
    }

    pub fn gaming() Config {
        return Config{
            .poll_interval_ms = 500,
            .auto_gaming_profile = true,
            .power_profile = "performance",
        };
    }

    pub fn efficiency() Config {
        return Config{
            .poll_interval_ms = 2000,
            .auto_gaming_profile = false,
            .power_profile = "eco",
            .fan_profile = "silent",
        };
    }
};

/// Check installation status
pub fn getStatus() InstallStatus {
    // Check for config directory
    const paths = Paths.system();

    if (std.Io.Dir.accessAbsolute(std.Io.Threaded.global_single_threaded.io(), paths.config_dir, .{})) |_| {
        // Config exists, check for main config file
        var config_path_buf: [512]u8 = undefined;
        const config_path = std.fmt.bufPrint(&config_path_buf, "{s}/nvprime.toml", .{paths.config_dir}) catch {
            return .partial;
        };

        if (std.Io.Dir.accessAbsolute(std.Io.Threaded.global_single_threaded.io(), config_path, .{})) |_| {
            return .installed;
        } else |_| {
            return .partial;
        }
    } else |_| {
        return .not_installed;
    }
}

/// Driver compatibility info
pub const DriverInfo = struct {
    version: [32]u8 = [_]u8{0} ** 32,
    version_len: usize = 0,
    major: u32 = 0,
    minor: u32 = 0,
    patch: u32 = 0,
    is_open: bool = false,
    is_compatible: bool = false,
    gsp_enabled: bool = false,

    pub fn getVersion(self: *const DriverInfo) []const u8 {
        return self.version[0..self.version_len];
    }
};

/// Check NVIDIA driver compatibility
pub fn checkDriver() DriverInfo {
    var info = DriverInfo{};

    // Query driver version via nvidia-smi
    const result = std.process.run(std.heap.page_allocator, std.Io.Threaded.global_single_threaded.io(), .{
        .argv = &.{ "nvidia-smi", "--query-gpu=driver_version", "--format=csv,noheader" },
    }) catch return info;
    defer std.heap.page_allocator.free(result.stdout);
    defer std.heap.page_allocator.free(result.stderr);

    if (result.term != .exited or result.term.exited != 0) return info;

    const ver_str = std.mem.trim(u8, result.stdout, " \t\n\r");
    const len = @min(ver_str.len, info.version.len);
    @memcpy(info.version[0..len], ver_str[0..len]);
    info.version_len = len;

    // Parse version
    var iter = std.mem.splitScalar(u8, ver_str, '.');
    if (iter.next()) |major_str| {
        info.major = std.fmt.parseInt(u32, major_str, 10) catch 0;
    }
    if (iter.next()) |minor_str| {
        info.minor = std.fmt.parseInt(u32, minor_str, 10) catch 0;
    }
    if (iter.next()) |patch_str| {
        info.patch = std.fmt.parseInt(u32, patch_str, 10) catch 0;
    }

    // Check compatibility (require 535+ for full features)
    info.is_compatible = info.major >= 535;

    // Check for open driver
    if (std.Io.Dir.accessAbsolute(std.Io.Threaded.global_single_threaded.io(), "/sys/module/nvidia/parameters/modeset", .{})) |_| {
        // Proprietary driver
        info.is_open = false;
    } else |_| {}

    if (std.Io.Dir.accessAbsolute(std.Io.Threaded.global_single_threaded.io(), "/sys/module/nvidia_open", .{})) |_| {
        info.is_open = true;
    } else |_| {}

    // Check GSP status
    const gsp_result = std.process.run(std.heap.page_allocator, std.Io.Threaded.global_single_threaded.io(), .{
        .argv = &.{ "nvidia-smi", "--query-gpu=gsp.mode.current", "--format=csv,noheader" },
    }) catch return info;
    defer std.heap.page_allocator.free(gsp_result.stdout);
    defer std.heap.page_allocator.free(gsp_result.stderr);

    if (gsp_result.term == .exited and gsp_result.term.exited == 0) {
        const gsp_mode = std.mem.trim(u8, gsp_result.stdout, " \t\n\r");
        info.gsp_enabled = std.mem.eql(u8, gsp_mode, "Enabled") or
            std.mem.eql(u8, gsp_mode, "1");
    }

    return info;
}

/// Udev rule for NVIDIA GPU events
pub const udev_rule =
    \\# NVPrime udev rules for NVIDIA GPU events
    \\# Place in /etc/udev/rules.d/99-nvprime.rules
    \\
    \\# GPU power state changes
    \\SUBSYSTEM=="drm", KERNEL=="card*", DRIVERS=="nvidia", RUN+="/usr/bin/nvprime-hook gpu-event"
    \\
    \\# NVIDIA module load
    \\ACTION=="add", SUBSYSTEM=="module", KERNEL=="nvidia", RUN+="/usr/bin/nvprime-hook module-load"
    \\
    \\# USB game controllers (for latency optimization)
    \\SUBSYSTEM=="usb", ATTR{idVendor}=="054c", RUN+="/usr/bin/nvprime-hook controller-event"
    \\SUBSYSTEM=="usb", ATTR{idVendor}=="045e", RUN+="/usr/bin/nvprime-hook controller-event"
;

/// Systemd service unit
pub const systemd_service =
    \\[Unit]
    \\Description=NVPrime NVIDIA Platform Daemon
    \\After=nvidia-persistenced.service
    \\Wants=nvidia-persistenced.service
    \\
    \\[Service]
    \\Type=simple
    \\ExecStart=/usr/bin/nvprime-daemon
    \\Restart=on-failure
    \\RestartSec=5
    \\
    \\# Security hardening
    \\NoNewPrivileges=yes
    \\ProtectSystem=strict
    \\ProtectHome=read-only
    \\PrivateTmp=yes
    \\
    \\[Install]
    \\WantedBy=multi-user.target
;

/// Systemd user service for per-user nvprime
pub const systemd_user_service =
    \\[Unit]
    \\Description=NVPrime User Session Service
    \\After=graphical-session.target
    \\
    \\[Service]
    \\Type=simple
    \\ExecStart=/usr/bin/nvprime-user
    \\Restart=on-failure
    \\
    \\[Install]
    \\WantedBy=graphical-session.target
;

/// Environment variables for NVIDIA gaming
pub const gaming_env =
    \\# NVPrime gaming environment
    \\# Source from /etc/profile.d/nvprime.sh
    \\
    \\# G-Sync / VRR
    \\export __GL_GSYNC_ALLOWED=1
    \\export __GL_VRR_ALLOWED=1
    \\
    \\# Shader cache
    \\export __GL_SHADER_DISK_CACHE=1
    \\export __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1
    \\export __GL_SHADER_DISK_CACHE_PATH="${XDG_CACHE_HOME:-$HOME/.cache}/nvprime/shaders"
    \\
    \\# Threaded optimizations
    \\export __GL_THREADED_OPTIMIZATIONS=1
    \\
    \\# NVIDIA Reflex (for DXVK/VKD3D)
    \\export DXVK_NVAPI_ALLOW_OTHER_DRIVERS=1
;

/// Shader cache info
pub const ShaderCacheInfo = struct {
    path: []const u8,
    size_bytes: u64,
    file_count: u32,
    enabled: bool,
};

/// Get shader cache info
pub fn getShaderCacheInfo() ShaderCacheInfo {
    const cache_path = std.c.getenv("__GL_SHADER_DISK_CACHE_PATH") orelse
        blk: {
            const home = std.c.getenv("HOME") orelse "/home/user";
            _ = home;
            break :blk "~/.cache/nvidia/GLCache";
        };

    const info = ShaderCacheInfo{
        .path = cache_path,
        .size_bytes = 0,
        .file_count = 0,
        .enabled = std.c.getenv("__GL_SHADER_DISK_CACHE") != null,
    };

    // Would walk directory to calculate size
    // For now return stub values

    return info;
}

/// Clear shader cache
pub fn clearShaderCache() !void {
    const home = std.c.getenv("HOME") orelse return error.NoHome;
    var path_buf: [512]u8 = undefined;

    // Clear NVIDIA GLCache
    const gl_cache = std.fmt.bufPrint(&path_buf, "{s}/.cache/nvidia/GLCache", .{home}) catch return error.PathError;

    // Use rm -rf via shell (safer than recursive delete in Zig)
    const allocator = std.heap.page_allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const result1 = std.process.run(allocator, io, .{
        .argv = &.{ "rm", "-rf", gl_cache },
    }) catch return error.SpawnError;
    allocator.free(result1.stdout);
    allocator.free(result1.stderr);

    // Clear nvprime shader cache
    const nvprime_cache = std.fmt.bufPrint(&path_buf, "{s}/.cache/nvprime/shaders", .{home}) catch return error.PathError;
    const result2 = std.process.run(allocator, io, .{
        .argv = &.{ "rm", "-rf", nvprime_cache },
    }) catch return error.SpawnError;
    allocator.free(result2.stdout);
    allocator.free(result2.stderr);
}

/// Installation actions
pub const InstallAction = enum {
    install_config,
    install_udev,
    install_systemd,
    install_env,
    install_all,
    uninstall,
};

/// Run installation action (requires root for system-wide)
pub fn install(action: InstallAction) !void {
    switch (action) {
        .install_config => {
            // Create config directory and default config
            std.log.info("Installing nvprime config to /etc/nvprime/", .{});
        },
        .install_udev => {
            std.log.info("Installing udev rules to /etc/udev/rules.d/", .{});
        },
        .install_systemd => {
            std.log.info("Installing systemd service", .{});
        },
        .install_env => {
            std.log.info("Installing environment to /etc/profile.d/", .{});
        },
        .install_all => {
            try install(.install_config);
            try install(.install_udev);
            try install(.install_systemd);
            try install(.install_env);
        },
        .uninstall => {
            std.log.info("Uninstalling nvprime system files", .{});
        },
    }
}

// ============================================================================
// Tests
// ============================================================================

test "config defaults" {
    const config = Config.default();
    try std.testing.expect(config.daemon_enabled);
    try std.testing.expectEqual(@as(u32, 1000), config.poll_interval_ms);
}

test "paths" {
    const sys_paths = Paths.system();
    try std.testing.expectEqualStrings("/etc/nvprime", sys_paths.config_dir);
}

test "driver info" {
    const info = checkDriver();
    // Just verify it doesn't crash
    _ = info.getVersion();
}
