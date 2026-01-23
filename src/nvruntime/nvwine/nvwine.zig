//! nvruntime/nvwine - NVIDIA Wine/Proton Integration
//!
//! Wine/Proton integration for NVIDIA-optimized gaming on Linux.
//! Provides environment setup, FSR injection, and Proton/Wine-GE detection.
//!
//! ## Features
//!
//! - **Proton Detection**: Auto-detect Proton versions and paths
//! - **Wine-GE Support**: Support for GloriousEggroll Wine builds
//! - **FSR Injection**: AMD FSR 1.0 sharpening via Proton
//! - **NVAPI Setup**: Configure DXVK-NVAPI for Windows games
//! - **Environment Generation**: Generate optimal Wine environment variables

const std = @import("std");
const nvvk = @import("nvvk");
const fs = std.fs;
const mem = std.mem;
const posix = std.posix;

pub const version = "0.1.0-dev";

/// Wine patch status
pub const PatchStatus = enum {
    not_applied,
    applied,
    outdated,

    pub fn description(self: PatchStatus) []const u8 {
        return switch (self) {
            .not_applied => "NVIDIA Wine patches not applied",
            .applied => "NVIDIA Wine patches active",
            .outdated => "Wine patches need update",
        };
    }
};

/// Wine/Proton distribution type
pub const WineType = enum {
    /// System Wine installation
    system,
    /// Valve's Proton
    proton,
    /// Proton-GE (GloriousEggroll)
    proton_ge,
    /// Wine-GE
    wine_ge,
    /// Lutris Wine
    lutris,
    /// Custom Wine build
    custom,
    /// Unknown
    unknown,

    pub fn name(self: WineType) []const u8 {
        return switch (self) {
            .system => "System Wine",
            .proton => "Proton",
            .proton_ge => "Proton-GE",
            .wine_ge => "Wine-GE",
            .lutris => "Lutris Wine",
            .custom => "Custom Wine",
            .unknown => "Unknown",
        };
    }
};

/// Proton version info
pub const ProtonVersion = struct {
    major: u32 = 0,
    minor: u32 = 0,
    patch: u32 = 0,
    wine_type: WineType = .unknown,
    path: ?[]const u8 = null,
    is_ge: bool = false,
    ge_version: u32 = 0, // GE release number

    pub fn format(self: ProtonVersion, writer: anytype) !void {
        if (self.wine_type == .proton_ge) {
            try writer.print("Proton-{d}.{d}-GE-{d}", .{ self.major, self.minor, self.ge_version });
        } else if (self.wine_type == .proton) {
            try writer.print("Proton {d}.{d}-{d}", .{ self.major, self.minor, self.patch });
        } else {
            try writer.print("Wine {d}.{d}", .{ self.major, self.minor });
        }
    }

    /// Check if this is a modern Proton version (8.0+)
    pub fn isModern(self: ProtonVersion) bool {
        return (self.wine_type == .proton or self.wine_type == .proton_ge) and self.major >= 8;
    }

    /// Check if this version supports FSR
    pub fn supportsFsr(self: ProtonVersion) bool {
        // FSR support added in Proton 6.3+
        return (self.wine_type == .proton and self.major >= 6 and self.minor >= 3) or
            self.wine_type == .proton_ge or
            self.wine_type == .wine_ge;
    }

    /// Check if this version has good Vulkan 1.4 support
    pub fn supportsVulkan14(self: ProtonVersion) bool {
        // Vulkan 1.4 support requires recent DXVK versions bundled in Proton 9+
        return self.major >= 9 or self.wine_type == .proton_ge;
    }
};

/// Wine configuration for NVIDIA
pub const WineConfig = struct {
    /// Enable DXVK
    dxvk_enabled: bool = true,
    /// Enable VKD3D-Proton for DX12
    vkd3d_enabled: bool = true,
    /// Enable DXVK-NVAPI
    nvapi_enabled: bool = true,
    /// Enable FSR sharpening
    fsr_enabled: bool = false,
    /// FSR sharpening strength (0-5, lower = sharper)
    fsr_strength: u8 = 2,
    /// Enable async shader compilation
    async_shaders: bool = true,
    /// Enable MangoHud overlay
    mangohud_enabled: bool = false,
    /// Custom WINE environment variables
    custom_env: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) WineConfig {
        return .{
            .custom_env = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *WineConfig) void {
        self.custom_env.deinit();
    }

    /// Create default NVIDIA-optimized config
    pub fn nvidiaOptimized(allocator: std.mem.Allocator) WineConfig {
        return .{
            .dxvk_enabled = true,
            .vkd3d_enabled = true,
            .nvapi_enabled = true,
            .fsr_enabled = false, // FSR not needed on modern NVIDIA GPUs
            .async_shaders = true,
            .mangohud_enabled = false,
            .custom_env = std.StringHashMap([]const u8).init(allocator),
        };
    }

    /// Create config optimized for low latency gaming
    pub fn lowLatency(allocator: std.mem.Allocator) WineConfig {
        return .{
            .dxvk_enabled = true,
            .vkd3d_enabled = true,
            .nvapi_enabled = true,
            .fsr_enabled = false,
            .async_shaders = false, // Disable async for consistent frametimes
            .mangohud_enabled = false,
            .custom_env = std.StringHashMap([]const u8).init(allocator),
        };
    }
};

/// Common Proton paths
const PROTON_PATHS = [_][]const u8{
    "~/.steam/root/compatibilitytools.d",
    "~/.local/share/Steam/compatibilitytools.d",
    "/usr/share/steam/compatibilitytools.d",
};

const STEAM_PROTON_PATHS = [_][]const u8{
    "~/.steam/steam/steamapps/common",
    "~/.local/share/Steam/steamapps/common",
};

/// Get Wine/Proton patch status
pub fn getPatchStatus() PatchStatus {
    // Check if NVIDIA-related Wine patches are present

    // 1. Check for DXVK-NVAPI
    if (posix.getenv("DXVK_ENABLE_NVAPI")) |val| {
        if (mem.eql(u8, val, "1")) {
            return .applied;
        }
    }

    // 2. Check for Wine DLL overrides including NVAPI
    if (posix.getenv("WINEDLLOVERRIDES")) |overrides| {
        if (mem.indexOf(u8, overrides, "nvapi") != null) {
            return .applied;
        }
    }

    // 3. Check for Proton with NVIDIA features
    if (posix.getenv("PROTON_ENABLE_NVAPI")) |val| {
        if (mem.eql(u8, val, "1")) {
            return .applied;
        }
    }

    return .not_applied;
}

/// Detect current Proton version
pub fn detectProtonVersion(allocator: std.mem.Allocator) ?ProtonVersion {
    // Check PROTON_VERSION environment first
    if (posix.getenv("PROTON_VERSION")) |ver_str| {
        return parseProtonVersion(ver_str);
    }

    // Try to detect from Steam Proton path
    if (posix.getenv("STEAM_COMPAT_DATA_PATH")) |_| {
        // We're running under Proton
        // Try to detect version from the proton script
        if (posix.getenv("STEAM_COMPAT_CLIENT_INSTALL_PATH")) |steam_path| {
            var path_buf: [1024]u8 = undefined;
            const proton_path = std.fmt.bufPrint(&path_buf, "{s}/steamapps/common/Proton*/version", .{steam_path}) catch return null;
            _ = proton_path;
            _ = allocator;
            // Would read version file here
        }
    }

    // Check for GE versions
    const ge_paths = [_][]const u8{
        "/home/*/.steam/root/compatibilitytools.d/GE-Proton*/version",
        "/home/*/.local/share/Steam/compatibilitytools.d/GE-Proton*/version",
    };
    for (ge_paths) |_| {
        // Would glob and check paths here
    }

    return null;
}

fn parseProtonVersion(ver_str: []const u8) ProtonVersion {
    var result = ProtonVersion{};

    // Check for GE version format: "GE-Proton8-21" or "Proton-8.0-GE-1"
    if (mem.indexOf(u8, ver_str, "GE")) |_| {
        result.wine_type = .proton_ge;
        result.is_ge = true;

        // Parse GE version
        var iter = mem.splitAny(u8, ver_str, "-");
        while (iter.next()) |part| {
            if (part.len > 0 and part[0] >= '0' and part[0] <= '9') {
                const num = std.fmt.parseInt(u32, part, 10) catch continue;
                if (result.major == 0) {
                    result.major = num;
                } else if (result.minor == 0) {
                    result.minor = num;
                } else {
                    result.ge_version = num;
                }
            }
        }
    } else {
        result.wine_type = .proton;

        // Parse standard Proton version: "8.0-4" or "Proton 8.0"
        var iter = mem.splitAny(u8, ver_str, ".-_ ");
        while (iter.next()) |part| {
            if (part.len > 0 and part[0] >= '0' and part[0] <= '9') {
                const num = std.fmt.parseInt(u32, part, 10) catch continue;
                if (result.major == 0) {
                    result.major = num;
                } else if (result.minor == 0) {
                    result.minor = num;
                } else {
                    result.patch = num;
                }
            }
        }
    }

    return result;
}

/// Generate environment variables for Wine/Proton
pub fn generateEnvironment(config: WineConfig, allocator: std.mem.Allocator) !std.StringHashMap([]const u8) {
    var env = std.StringHashMap([]const u8).init(allocator);

    // DXVK settings
    if (config.dxvk_enabled) {
        try env.put("DXVK_ASYNC", if (config.async_shaders) "1" else "0");
        try env.put("DXVK_LOG_LEVEL", "none");
    }

    // VKD3D-Proton settings
    if (config.vkd3d_enabled) {
        try env.put("VKD3D_FEATURE_LEVEL", "12_2");
    }

    // NVIDIA API settings
    if (config.nvapi_enabled) {
        try env.put("DXVK_ENABLE_NVAPI", "1");
        try env.put("PROTON_ENABLE_NVAPI", "1");
        try env.put("WINEDLLOVERRIDES", "nvapi64,nvapi=n");
    }

    // FSR settings
    if (config.fsr_enabled) {
        try env.put("WINE_FULLSCREEN_FSR", "1");
        var strength_buf: [2]u8 = undefined;
        const strength_str = std.fmt.bufPrint(&strength_buf, "{d}", .{config.fsr_strength}) catch "2";
        try env.put("WINE_FULLSCREEN_FSR_STRENGTH", strength_str);
    }

    // MangoHud
    if (config.mangohud_enabled) {
        try env.put("MANGOHUD", "1");
    }

    // NVIDIA-specific optimizations
    try env.put("__GL_THREADED_OPTIMIZATION", "1");
    try env.put("__GL_SHADER_DISK_CACHE", "1");
    try env.put("__GL_SHADER_DISK_CACHE_SKIP_CLEANUP", "1");

    // Copy custom environment
    var custom_iter = config.custom_env.iterator();
    while (custom_iter.next()) |entry| {
        try env.put(entry.key_ptr.*, entry.value_ptr.*);
    }

    return env;
}

/// Check if Wine/Proton is available
pub fn isWineAvailable() bool {
    // Check for wine executable
    const wine_paths = [_][]const u8{
        "/usr/bin/wine",
        "/usr/local/bin/wine",
        "/opt/wine/bin/wine",
    };

    for (wine_paths) |path| {
        if (fs.cwd().access(path, .{})) |_| {
            return true;
        } else |_| {}
    }

    return false;
}

/// Check if Proton is available
pub fn isProtonAvailable() bool {
    // Check for Steam and Proton
    const indicators = [_][]const u8{
        "/usr/bin/steam",
        "~/.steam/steam/steamapps/common/Proton 8.0",
        "~/.steam/root/compatibilitytools.d",
    };

    for (indicators) |_| {
        // Would expand ~ and check
    }

    // Check environment
    return posix.getenv("STEAM_COMPAT_DATA_PATH") != null;
}

test "nvwine patch status" {
    const status = getPatchStatus();
    _ = status.description();
}

test "wine type names" {
    try std.testing.expectEqualStrings("Proton-GE", WineType.proton_ge.name());
    try std.testing.expectEqualStrings("Proton", WineType.proton.name());
}

test "proton version parsing" {
    const ge_ver = parseProtonVersion("GE-Proton8-21");
    try std.testing.expect(ge_ver.is_ge);
    try std.testing.expectEqual(WineType.proton_ge, ge_ver.wine_type);
    try std.testing.expectEqual(@as(u32, 8), ge_ver.major);

    const std_ver = parseProtonVersion("8.0-4");
    try std.testing.expect(!std_ver.is_ge);
    try std.testing.expectEqual(@as(u32, 8), std_ver.major);
    try std.testing.expectEqual(@as(u32, 0), std_ver.minor);
}

test "proton feature detection" {
    const ver = ProtonVersion{
        .major = 9,
        .minor = 0,
        .wine_type = .proton,
    };

    try std.testing.expect(ver.isModern());
    try std.testing.expect(ver.supportsFsr());
    try std.testing.expect(ver.supportsVulkan14());
}
