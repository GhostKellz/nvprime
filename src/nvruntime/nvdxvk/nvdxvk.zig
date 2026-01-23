//! nvruntime/nvdxvk - NVIDIA DXVK Optimizations
//!
//! NVIDIA-specific DXVK optimizations and Reflex injection.
//! Uses nvvk for low-level Vulkan extension access.
//!
//! ## Features
//!
//! - **Reflex Injection** - Inject VK_NV_low_latency2 into DXVK
//! - **Shader Optimizations** - NVIDIA-specific shader paths
//! - **Async Compute** - Better async compute scheduling
//! - **State Cache** - Enhanced state cache with NVIDIA extensions

const std = @import("std");
const nvvk = @import("nvvk");

pub const version = "0.1.0-dev";

/// DXVK patch status
pub const PatchStatus = enum {
    not_applied,
    applied,
    outdated,
    incompatible,

    pub fn description(self: PatchStatus) []const u8 {
        return switch (self) {
            .not_applied => "NVIDIA patches not applied",
            .applied => "NVIDIA patches active",
            .outdated => "Patches need update",
            .incompatible => "DXVK version incompatible",
        };
    }
};

/// DXVK optimization level
pub const OptimizationLevel = enum {
    /// No NVIDIA-specific optimizations
    none,
    /// Basic optimizations (safe for all games)
    basic,
    /// Aggressive optimizations (may cause issues)
    aggressive,
    /// Maximum performance (experimental)
    experimental,

    pub fn description(self: OptimizationLevel) []const u8 {
        return switch (self) {
            .none => "No NVIDIA optimizations",
            .basic => "Safe optimizations for all games",
            .aggressive => "Aggressive (may cause issues)",
            .experimental => "Maximum performance (experimental)",
        };
    }
};

/// DXVK configuration for NVIDIA
pub const DxvkConfig = struct {
    /// Enable Reflex low-latency mode
    reflex_enabled: bool = true,
    /// Reflex mode (on/boost)
    reflex_mode: nvvk.low_latency.ModeConfig = .{ .enabled = true, .boost = false },
    /// Optimization level
    optimization_level: OptimizationLevel = .basic,
    /// Use async compute for supported operations
    async_compute: bool = true,
    /// Enable NVIDIA-specific shader paths
    nvidia_shaders: bool = true,
    /// Enable state cache enhancements
    enhanced_cache: bool = true,

    pub fn default() DxvkConfig {
        return .{};
    }

    pub fn lowLatency() DxvkConfig {
        return .{
            .reflex_enabled = true,
            .reflex_mode = .{ .enabled = true, .boost = true },
            .optimization_level = .aggressive,
            .async_compute = true,
            .nvidia_shaders = true,
            .enhanced_cache = true,
        };
    }

    pub fn compatibility() DxvkConfig {
        return .{
            .reflex_enabled = false,
            .reflex_mode = .{ .enabled = false, .boost = false },
            .optimization_level = .none,
            .async_compute = false,
            .nvidia_shaders = false,
            .enhanced_cache = false,
        };
    }
};

const fs = std.fs;
const mem = std.mem;
const posix = std.posix;

/// Common DXVK installation paths
const DXVK_PATHS = [_][]const u8{
    "/usr/share/dxvk",
    "/usr/local/share/dxvk",
    "/opt/dxvk",
};

/// Get current patch status
/// Checks for NVIDIA-patched DXVK installations
pub fn getPatchStatus() PatchStatus {
    // Check for DXVK_CONFIG environment (indicates custom config)
    if (posix.getenv("DXVK_CONFIG")) |_| {
        // Custom config present - check if NVIDIA features enabled
        return .applied;
    }

    // Check for NVIDIA-specific DXVK builds
    for (DXVK_PATHS) |dxvk_path| {
        var path_buf: [512]u8 = undefined;

        // Check for NVIDIA patch marker file
        const marker_path = std.fmt.bufPrint(&path_buf, "{s}/nvidia-patches", .{dxvk_path}) catch continue;
        if (fs.cwd().access(marker_path, .{})) |_| {
            return .applied;
        } else |_| {}

        // Check for DXVK-nvapi which indicates NVIDIA integration
        const nvapi_path = std.fmt.bufPrint(&path_buf, "{s}/nvapi", .{dxvk_path}) catch continue;
        if (fs.cwd().access(nvapi_path, .{})) |_| {
            return .applied;
        } else |_| {}
    }

    // Check if running with async patches (common NVIDIA optimization)
    if (posix.getenv("DXVK_ASYNC")) |val| {
        if (mem.eql(u8, val, "1")) {
            return .applied;
        }
    }

    return .not_applied;
}

/// Environment variables to set for DXVK with NVIDIA optimizations
pub const EnvVars = struct {
    /// Enable DXVK async shader compilation
    pub const DXVK_ASYNC = "DXVK_ASYNC";
    /// State cache path
    pub const DXVK_STATE_CACHE_PATH = "DXVK_STATE_CACHE_PATH";
    /// Log level
    pub const DXVK_LOG_LEVEL = "DXVK_LOG_LEVEL";
    /// HUD configuration
    pub const DXVK_HUD = "DXVK_HUD";
    /// Frame rate limit
    pub const DXVK_FRAME_RATE = "DXVK_FRAME_RATE";

    /// Get recommended env vars for a config
    /// Returns a static array of key-value pairs for environment setup
    pub fn forConfig(config: DxvkConfig) []const [2][]const u8 {
        // Static arrays for different configurations
        const env_basic = [_][2][]const u8{
            .{ DXVK_ASYNC, "1" },
            .{ DXVK_LOG_LEVEL, "none" },
        };

        const env_aggressive = [_][2][]const u8{
            .{ DXVK_ASYNC, "1" },
            .{ DXVK_LOG_LEVEL, "none" },
            .{ "DXVK_CONFIG_FILE", "" }, // Use default optimized config
            .{ "VKD3D_FEATURE_LEVEL", "12_2" },
        };

        const env_experimental = [_][2][]const u8{
            .{ DXVK_ASYNC, "1" },
            .{ DXVK_LOG_LEVEL, "none" },
            .{ "DXVK_NVAPI_ALLOW_OTHER_DRIVERS", "1" },
            .{ "DXVK_ENABLE_NVAPI", "1" },
        };

        const env_none = [_][2][]const u8{
            .{ DXVK_LOG_LEVEL, "info" },
        };

        return switch (config.optimization_level) {
            .none => &env_none,
            .basic => &env_basic,
            .aggressive => &env_aggressive,
            .experimental => &env_experimental,
        };
    }
};

/// DXVK version info
pub const DxvkVersion = struct {
    major: u32,
    minor: u32,
    patch: u32,
    is_async: bool,
    is_gplasync: bool,

    pub fn format(self: DxvkVersion, writer: anytype) !void {
        try writer.print("{d}.{d}.{d}", .{ self.major, self.minor, self.patch });
        if (self.is_async) try writer.writeAll("-async");
        if (self.is_gplasync) try writer.writeAll("-gplasync");
    }
};

/// Detect installed DXVK version
/// Parses version from DXVK shared libraries or version files
pub fn detectVersion() ?DxvkVersion {
    const allocator = std.heap.page_allocator;

    // Check common locations for DXVK version info
    const version_paths = [_][]const u8{
        "/usr/share/dxvk/version",
        "/usr/local/share/dxvk/version",
        "/opt/dxvk/version",
    };

    for (version_paths) |path| {
        const file = fs.cwd().openFile(path, .{}) catch continue;
        defer file.close();

        var buf: [64]u8 = undefined;
        const len = file.read(&buf) catch continue;
        const content = mem.trim(u8, buf[0..len], " \t\n\r");

        // Parse version string like "2.3.1" or "2.3.1-async"
        return parseVersionString(content);
    }

    // Try to get version from pacman/package manager
    const result = std.process.run(allocator, std.Io.Threaded.global_single_threaded.io(), .{
        .argv = &.{ "pacman", "-Q", "dxvk" },
    }) catch return null;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term == .exited and result.term.exited == 0) {
        // Output format: "dxvk 2.3.1-1"
        const output = mem.trim(u8, result.stdout, " \t\n\r");
        if (mem.indexOf(u8, output, " ")) |space_idx| {
            const version_str = output[space_idx + 1 ..];
            // Remove package revision (-1, -2, etc)
            const dash_idx = mem.indexOf(u8, version_str, "-") orelse version_str.len;
            return parseVersionString(version_str[0..dash_idx]);
        }
    }

    return null;
}

fn parseVersionString(s: []const u8) ?DxvkVersion {
    var parsed = DxvkVersion{
        .major = 0,
        .minor = 0,
        .patch = 0,
        .is_async = mem.indexOf(u8, s, "async") != null,
        .is_gplasync = mem.indexOf(u8, s, "gplasync") != null,
    };

    // Parse major.minor.patch
    var iter = mem.splitScalar(u8, s, '.');
    if (iter.next()) |major_str| {
        // Handle trailing non-numeric (like "-async")
        const clean_major = blk: {
            for (major_str, 0..) |c, i| {
                if (c < '0' or c > '9') {
                    break :blk major_str[0..i];
                }
            }
            break :blk major_str;
        };
        parsed.major = std.fmt.parseInt(u32, clean_major, 10) catch 0;
    } else return null;

    if (iter.next()) |minor_str| {
        const clean_minor = blk: {
            for (minor_str, 0..) |c, i| {
                if (c < '0' or c > '9') {
                    break :blk minor_str[0..i];
                }
            }
            break :blk minor_str;
        };
        parsed.minor = std.fmt.parseInt(u32, clean_minor, 10) catch 0;
    }

    if (iter.next()) |patch_str| {
        const clean_patch = blk: {
            for (patch_str, 0..) |c, i| {
                if (c < '0' or c > '9') {
                    break :blk patch_str[0..i];
                }
            }
            break :blk patch_str;
        };
        parsed.patch = std.fmt.parseInt(u32, clean_patch, 10) catch 0;
    }

    return parsed;
}

// =============================================================================
// Vulkan 1.4 Integration
// =============================================================================

/// Check if DXVK can benefit from Vulkan 1.4 features
pub fn supportsVulkan14Features() bool {
    // In production: query the actual Vulkan version from nvvk
    return nvvk.vulkan.supportsVulkan14(nvvk.vulkan.VK_API_VERSION_1_4);
}

/// Get Vulkan 1.4 optimization hints for DXVK
pub fn getVulkan14Hints() Vulkan14Hints {
    return .{
        .use_push_descriptors = supportsVulkan14Features(),
        .use_maintenance6 = supportsVulkan14Features(),
        .use_dynamic_rendering_local_read = supportsVulkan14Features(),
        .use_scalar_block_layout = true, // Available since Vulkan 1.2 via extension
    };
}

/// Vulkan 1.4 optimization hints
pub const Vulkan14Hints = struct {
    /// Use push descriptors for faster descriptor updates
    use_push_descriptors: bool = false,
    /// Use maintenance 6 features
    use_maintenance6: bool = false,
    /// Use dynamic rendering local read
    use_dynamic_rendering_local_read: bool = false,
    /// Use scalar block layout for compute shaders
    use_scalar_block_layout: bool = false,
};

// =============================================================================
// Reflex Injection
// =============================================================================

/// Reflex injection configuration
pub const ReflexInjection = struct {
    /// Target application process name
    process_name: []const u8,
    /// Reflex mode
    mode: nvvk.low_latency.ModeConfig,
    /// Swapchain handle (set at runtime)
    swapchain: u64 = 0,
    /// Device dispatch (set at runtime)
    dispatch: ?*const nvvk.DeviceDispatch = null,

    /// Create injection config for a game
    pub fn forGame(process_name: []const u8) ReflexInjection {
        return .{
            .process_name = process_name,
            .mode = .{ .enabled = true, .boost = false },
        };
    }

    /// Create injection config with boost mode
    pub fn forGameWithBoost(process_name: []const u8) ReflexInjection {
        return .{
            .process_name = process_name,
            .mode = .{ .enabled = true, .boost = true },
        };
    }

    /// Check if this injection is active
    pub fn isActive(self: *const ReflexInjection) bool {
        return self.dispatch != null and self.swapchain != 0;
    }

    /// Apply injection to DXVK process
    pub fn apply(self: *ReflexInjection, device: nvvk.VkDevice, swapchain: u64, getDeviceProcAddr: anytype) !void {
        _ = getDeviceProcAddr;
        self.swapchain = swapchain;
        // In production: create DeviceDispatch and enable low latency mode
        _ = device;
    }
};

// =============================================================================
// DXVK-NVAPI Integration
// =============================================================================

/// DXVK-NVAPI features
pub const NvapiFeatures = struct {
    /// NVAPI DLL loaded
    nvapi_loaded: bool = false,
    /// DLSS support via NVAPI
    dlss_available: bool = false,
    /// Reflex support via NVAPI
    reflex_available: bool = false,
    /// GPU architecture
    gpu_arch: GpuArch = .unknown,

    pub const GpuArch = enum {
        unknown,
        turing,
        ampere,
        ada_lovelace,
        blackwell,
    };
};

/// Detect DXVK-NVAPI features
pub fn detectNvapiFeatures() NvapiFeatures {
    var features = NvapiFeatures{};

    // Check for DXVK-NVAPI environment
    if (posix.getenv("DXVK_ENABLE_NVAPI")) |val| {
        features.nvapi_loaded = mem.eql(u8, val, "1");
    }

    // Check for nvapi64.dll or nvapi.dll (Wine DLL overrides)
    if (posix.getenv("WINEDLLOVERRIDES")) |overrides| {
        if (mem.indexOf(u8, overrides, "nvapi") != null) {
            features.nvapi_loaded = true;
        }
    }

    if (features.nvapi_loaded) {
        // If NVAPI is loaded, assume modern features are available
        features.dlss_available = true;
        features.reflex_available = true;

        // Detect GPU architecture from nvvk if available
        if (nvvk.getDriverVersion(std.heap.page_allocator)) |driver| {
            if (driver.major >= 590) {
                // Driver 590+ indicates recent hardware
                features.gpu_arch = .ada_lovelace; // Assume modern for now
            }
        }
    }

    return features;
}

/// Generate DXVK configuration file content
pub fn generateConfigFile(config: DxvkConfig) []const u8 {
    // Generate dxvk.conf content
    // This is a simplified version - in production would be more comprehensive
    if (config.optimization_level == .experimental) {
        return
            \\# NVIDIA-optimized DXVK configuration
            \\# Generated by nvprime
            \\
            \\dxgi.customVendorId = 10de
            \\dxgi.nvapiHack = False
            \\dxvk.enableAsync = True
            \\dxvk.numCompilerThreads = 0
            \\d3d11.samplerAnisotropy = 16
            \\d3d11.maxFrameLatency = 1
            \\d3d9.forceSwapchainMSAA = 0
        ;
    } else if (config.optimization_level == .aggressive) {
        return
            \\# NVIDIA-optimized DXVK configuration (aggressive)
            \\dxgi.customVendorId = 10de
            \\dxvk.enableAsync = True
            \\d3d11.maxFrameLatency = 1
        ;
    } else {
        return
            \\# NVIDIA-compatible DXVK configuration
            \\dxgi.customVendorId = 10de
        ;
    }
}

test "nvdxvk config" {
    const config = DxvkConfig.default();
    try std.testing.expect(config.reflex_enabled);
    try std.testing.expectEqual(OptimizationLevel.basic, config.optimization_level);
}

test "nvdxvk low latency config" {
    const config = DxvkConfig.lowLatency();
    try std.testing.expect(config.reflex_mode.boost);
    try std.testing.expectEqual(OptimizationLevel.aggressive, config.optimization_level);
}

test "vulkan 1.4 hints" {
    const hints = getVulkan14Hints();
    // Just verify structure works
    _ = hints.use_push_descriptors;
}

test "reflex injection" {
    const injection = ReflexInjection.forGameWithBoost("game.exe");
    try std.testing.expect(injection.mode.boost);
    try std.testing.expect(!injection.isActive());
}
