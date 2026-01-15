//! NVAPI Bindings for Linux
//!
//! Provides low-latency (Reflex) functionality via:
//! - VK_NV_low_latency2 Vulkan extension (native Linux)
//! - NvLLVk library bindings (libnvidia-lowlatency-vulkan.so)
//!
//! For Wine/Proton, NVAPI is shimmed through nvngx-dxvk-wrap.

const std = @import("std");
const builtin = @import("builtin");

pub const version = "0.1.0-dev";

const log = std.log.scoped(.nvapi);

// ============================================================================
// NVAPI Error Codes
// ============================================================================

pub const NvAPI_Status = enum(i32) {
    ok = 0,
    err = -1,
    library_not_found = -2,
    no_implementation = -3,
    api_not_initialized = -4,
    invalid_argument = -5,
    nvidia_device_not_found = -6,
    end_enumeration = -7,
    invalid_handle = -8,
    incompatible_struct_version = -9,
    handle_invalidated = -10,
    opengl_context_not_current = -11,
    invalid_pointer = -17,
    no_gl_expert = -18,
    instrumentation_disabled = -19,
    no_gl_nsight = -20,
    expected_logical_gpu_handle = -100,
    expected_physical_gpu_handle = -101,
    expected_display_handle = -102,
    invalid_combination = -103,
    not_supported = -104,
    portid_not_found = -105,
    expected_unattached_display_handle = -106,
    invalid_perf_level = -107,
    device_busy = -108,
    nv_persist_file_not_found = -109,
    persist_data_not_found = -110,
    expected_tv_display = -111,
    expected_tv_display_on_dconnector = -112,
    no_active_sli_topology = -113,
    sli_rendering_mode_notallowed = -114,
    expected_digital_flat_panel = -115,
    argument_exceed_max_size = -116,
    device_switching_not_allowed = -117,
    testing_clocks_not_supported = -118,
    unknown_underscan_config = -119,
    timeout_reconfiguring_gpu_topo = -120,
    data_not_found = -121,
    expected_analog_display = -122,
    no_vidlink = -123,
    requires_reboot = -124,
    invalid_hybrid_mode = -125,
    mixed_target_types = -126,
    syswow64_not_supported = -127,
    implicit_set_gpu_topology_change_not_allowed = -128,
    request_user_to_close_non_migratable_apps = -129,
    out_of_memory = -130,
    was_still_drawing = -131,
    file_not_found = -132,
    too_many_unique_state_objects = -133,
    invalid_call = -134,
    d3d10_1_library_not_found = -135,
    function_not_found = -136,
    invalid_user_privilege = -137,
    expected_non_primary_display_handle = -138,
    expected_compute_gpu_handle = -139,
    stereo_not_initialized = -140,
    stereo_registry_access_failed = -141,
    stereo_registry_profile_type_not_supported = -142,
    stereo_registry_value_not_supported = -143,
    stereo_not_enabled = -144,
    stereo_not_turned_on = -145,
    stereo_invalid_device_interface = -146,
    stereo_parameter_out_of_range = -147,
    stereo_frustum_adjust_mode_not_supported = -148,
    topo_not_possible = -149,
    mode_change_failed = -150,
    d3d11_library_not_found = -151,
    invalid_address = -152,
    string_too_small = -153,
    matching_device_not_found = -154,
    driver_running = -155,
    driver_notrunning = -156,
    error_driver_reload_required = -157,
    set_not_allowed = -158,
    advanced_display_topology_required = -159,
    setting_not_found = -160,
    setting_size_too_large = -161,
    too_many_settings_in_profile = -162,
    profile_not_found = -163,
    profile_name_in_use = -164,
    profile_name_empty = -165,
    executable_not_found = -166,
    executable_already_in_use = -167,
    datatype_mismatch = -168,
    profile_removed = -169,
    unregistered_resource = -170,
    id_out_of_range = -171,
    displayconfig_validation_failed = -172,
    dpmst_changed = -173,
    insufficient_buffer = -174,
    access_denied = -175,
    mosaic_not_active = -176,
    share_resource_relocated = -177,
    request_user_to_disable_dw = -178,
    d3d_device_lost = -179,
    invalid_configuration = -180,
    stereo_handshake_not_done = -181,
    executable_path_is_ambiguous = -182,
    default_stereo_profile_is_not_defined = -183,
    default_stereo_profile_does_not_exist = -184,
    cluster_already_exists = -185,
    dpmst_display_id_expected = -186,
    invalid_display_id = -187,
    stream_is_out_of_sync = -188,
    incompatible_audio_driver = -189,
    value_already_set = -190,
    timeout = -191,
    gpu_workstation_feature_incomplete = -192,
    stereo_init_activation_not_done = -193,
    sync_not_active = -194,
    sync_master_not_found = -195,
    invalid_sync_topology = -196,
    ecid_sign_algo_unsupported = -197,
    ecid_key_verification_failed = -198,
    firmware_out_of_date = -199,
    firmware_revision_not_supported = -200,
    license_caller_authentication_failed = -201,
    d3d_device_not_registered = -202,
    resource_not_acquired = -203,
    timing_not_supported = -204,
    hdcp_encryption_failed = -205,
    pclk_limitation_failed = -206,
    no_connector_found = -207,
    hdcp_disabled = -208,
    api_in_use = -209,
    nvidia_display_not_found = -210,
    priv_sec_violation = -211,
    incorrect_vendor = -212,
    display_in_use = -213,
    unsupported_config_non_hdcp_hmd = -214,
    max_display_limit_reached = -215,
    invalid_direct_mode_display = -216,
    gpu_in_debug_mode = -217,
    d3d_context_not_found = -218,
    stereo_video_not_active = -219,
    unregistered_gat_resource = -220,
    invalid_frl_data = -221,
    expected_tiled_display = -222,
    no_connector_for_hmd = -223,
    bpc_mode_not_supported = -224,
    invalid_display_modes = -225,
    _,

    pub fn isSuccess(self: NvAPI_Status) bool {
        return self == .ok;
    }

    pub fn toError(self: NvAPI_Status) ?NvApiError {
        return switch (self) {
            .ok => null,
            .library_not_found => NvApiError.LibraryNotFound,
            .no_implementation => NvApiError.NoImplementation,
            .api_not_initialized => NvApiError.NotInitialized,
            .invalid_argument => NvApiError.InvalidArgument,
            .nvidia_device_not_found => NvApiError.DeviceNotFound,
            .not_supported => NvApiError.NotSupported,
            .timeout => NvApiError.Timeout,
            else => NvApiError.Unknown,
        };
    }
};

pub const NvApiError = error{
    LibraryNotFound,
    NoImplementation,
    NotInitialized,
    InvalidArgument,
    DeviceNotFound,
    NotSupported,
    Timeout,
    Unknown,
};

// ============================================================================
// Low Latency / Reflex Types
// ============================================================================

/// Reflex/Low Latency mode
pub const NV_LATENCY_MARKER_TYPE = enum(u32) {
    SIMULATION_START = 0,
    SIMULATION_END = 1,
    RENDERSUBMIT_START = 2,
    RENDERSUBMIT_END = 3,
    PRESENT_START = 4,
    PRESENT_END = 5,
    INPUT_SAMPLE = 6,
    TRIGGER_FLASH = 7,
    PC_LATENCY_PING = 8,
    OUT_OF_BAND_RENDERSUBMIT_START = 9,
    OUT_OF_BAND_RENDERSUBMIT_END = 10,
    OUT_OF_BAND_PRESENT_START = 11,
    OUT_OF_BAND_PRESENT_END = 12,
};

/// Low latency mode setting
pub const NV_LATENCY_MODE = enum(u32) {
    OFF = 0,
    ON = 1,
    ULTRA = 2, // ON + Boost
};

/// Frame report for latency statistics
pub const NV_LATENCY_RESULT_PARAMS = extern struct {
    version: u32 = NV_LATENCY_RESULT_PARAMS_VER,
    frame_reports: [64]FrameReport = [_]FrameReport{.{}} ** 64,

    pub const NV_LATENCY_RESULT_PARAMS_VER = 0x00010000 | @sizeOf(NV_LATENCY_RESULT_PARAMS);
};

/// Individual frame timing report
pub const FrameReport = extern struct {
    frame_id: u64 = 0,
    input_sample_time: u64 = 0,
    sim_start_time: u64 = 0,
    sim_end_time: u64 = 0,
    render_submit_start_time: u64 = 0,
    render_submit_end_time: u64 = 0,
    present_start_time: u64 = 0,
    present_end_time: u64 = 0,
    driver_start_time: u64 = 0,
    driver_end_time: u64 = 0,
    os_render_queue_start_time: u64 = 0,
    os_render_queue_end_time: u64 = 0,
    gpu_render_start_time: u64 = 0,
    gpu_render_end_time: u64 = 0,
    gpu_active_render_time_us: u32 = 0,
    gpu_frame_time_us: u32 = 0,
    _padding: [8]u8 = [_]u8{0} ** 8,

    /// Get total PC latency in microseconds
    pub fn getPcLatencyUs(self: *const FrameReport) u64 {
        if (self.gpu_render_end_time > self.sim_start_time) {
            return self.gpu_render_end_time - self.sim_start_time;
        }
        return 0;
    }

    /// Get game latency (simulation time) in microseconds
    pub fn getGameLatencyUs(self: *const FrameReport) u64 {
        if (self.sim_end_time > self.sim_start_time) {
            return self.sim_end_time - self.sim_start_time;
        }
        return 0;
    }

    /// Get render latency in microseconds
    pub fn getRenderLatencyUs(self: *const FrameReport) u64 {
        if (self.render_submit_end_time > self.render_submit_start_time) {
            return self.render_submit_end_time - self.render_submit_start_time;
        }
        return 0;
    }
};

/// Sleep mode parameters
pub const NV_SET_SLEEP_MODE_PARAMS = extern struct {
    version: u32 = NV_SET_SLEEP_MODE_PARAMS_VER,
    enable_low_latency: u32 = 0, // 0=off, 1=on
    enable_boost: u32 = 0, // 0=off, 1=on (GPU boost for lower latency)
    minimum_interval_us: u32 = 0, // Minimum frame interval in microseconds
    _reserved: [8]u32 = [_]u32{0} ** 8,

    pub const NV_SET_SLEEP_MODE_PARAMS_VER = 0x00010000 | @sizeOf(NV_SET_SLEEP_MODE_PARAMS);

    pub fn fromMode(mode: NV_LATENCY_MODE) NV_SET_SLEEP_MODE_PARAMS {
        return switch (mode) {
            .OFF => .{ .enable_low_latency = 0, .enable_boost = 0 },
            .ON => .{ .enable_low_latency = 1, .enable_boost = 0 },
            .ULTRA => .{ .enable_low_latency = 1, .enable_boost = 1 },
        };
    }
};

/// Latency marker parameters
pub const NV_LATENCY_MARKER_PARAMS = extern struct {
    version: u32 = NV_LATENCY_MARKER_PARAMS_VER,
    frame_id: u64 = 0,
    marker_type: NV_LATENCY_MARKER_TYPE = .SIMULATION_START,
    _reserved: [8]u32 = [_]u32{0} ** 8,

    pub const NV_LATENCY_MARKER_PARAMS_VER = 0x00010000 | @sizeOf(NV_LATENCY_MARKER_PARAMS);
};

// ============================================================================
// VK_NV_low_latency2 Extension Types
// ============================================================================

/// VkLatencySleepModeInfoNV for VK_NV_low_latency2
pub const VkLatencySleepModeInfoNV = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_LATENCY_SLEEP_MODE_INFO_NV,
    pNext: ?*const anyopaque = null,
    lowLatencyMode: u32 = 0, // VkBool32
    lowLatencyBoost: u32 = 0, // VkBool32
    minimumIntervalUs: u32 = 0,

    pub const VK_STRUCTURE_TYPE_LATENCY_SLEEP_MODE_INFO_NV = 1000505000;
};

/// VkLatencySleepInfoNV
pub const VkLatencySleepInfoNV = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_LATENCY_SLEEP_INFO_NV,
    pNext: ?*const anyopaque = null,
    signalSemaphore: u64 = 0, // VkSemaphore
    value: u64 = 0,

    pub const VK_STRUCTURE_TYPE_LATENCY_SLEEP_INFO_NV = 1000505001;
};

/// VkSetLatencyMarkerInfoNV
pub const VkSetLatencyMarkerInfoNV = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_SET_LATENCY_MARKER_INFO_NV,
    pNext: ?*const anyopaque = null,
    presentID: u64 = 0,
    marker: NV_LATENCY_MARKER_TYPE = .SIMULATION_START,

    pub const VK_STRUCTURE_TYPE_SET_LATENCY_MARKER_INFO_NV = 1000505002;
};

/// VkGetLatencyMarkerInfoNV
pub const VkGetLatencyMarkerInfoNV = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_GET_LATENCY_MARKER_INFO_NV,
    pNext: ?*const anyopaque = null,
    timingCount: u32 = 0,
    pTimings: ?*VkLatencyTimingsFrameReportNV = null,

    pub const VK_STRUCTURE_TYPE_GET_LATENCY_MARKER_INFO_NV = 1000505003;
};

/// VkLatencyTimingsFrameReportNV
pub const VkLatencyTimingsFrameReportNV = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_LATENCY_TIMINGS_FRAME_REPORT_NV,
    pNext: ?*const anyopaque = null,
    presentID: u64 = 0,
    inputSampleTimeUs: u64 = 0,
    simStartTimeUs: u64 = 0,
    simEndTimeUs: u64 = 0,
    renderSubmitStartTimeUs: u64 = 0,
    renderSubmitEndTimeUs: u64 = 0,
    presentStartTimeUs: u64 = 0,
    presentEndTimeUs: u64 = 0,
    driverStartTimeUs: u64 = 0,
    driverEndTimeUs: u64 = 0,
    osRenderQueueStartTimeUs: u64 = 0,
    osRenderQueueEndTimeUs: u64 = 0,
    gpuRenderStartTimeUs: u64 = 0,
    gpuRenderEndTimeUs: u64 = 0,

    pub const VK_STRUCTURE_TYPE_LATENCY_TIMINGS_FRAME_REPORT_NV = 1000505004;

    pub fn toFrameReport(self: *const VkLatencyTimingsFrameReportNV) FrameReport {
        return FrameReport{
            .frame_id = self.presentID,
            .input_sample_time = self.inputSampleTimeUs,
            .sim_start_time = self.simStartTimeUs,
            .sim_end_time = self.simEndTimeUs,
            .render_submit_start_time = self.renderSubmitStartTimeUs,
            .render_submit_end_time = self.renderSubmitEndTimeUs,
            .present_start_time = self.presentStartTimeUs,
            .present_end_time = self.presentEndTimeUs,
            .driver_start_time = self.driverStartTimeUs,
            .driver_end_time = self.driverEndTimeUs,
            .os_render_queue_start_time = self.osRenderQueueStartTimeUs,
            .os_render_queue_end_time = self.osRenderQueueEndTimeUs,
            .gpu_render_start_time = self.gpuRenderStartTimeUs,
            .gpu_render_end_time = self.gpuRenderEndTimeUs,
        };
    }
};

/// VkOutOfBandQueueTypeInfoNV
pub const VkOutOfBandQueueTypeInfoNV = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_OUT_OF_BAND_QUEUE_TYPE_INFO_NV,
    pNext: ?*const anyopaque = null,
    queueType: VkOutOfBandQueueTypeNV = .RENDER,

    pub const VK_STRUCTURE_TYPE_OUT_OF_BAND_QUEUE_TYPE_INFO_NV = 1000505005;
};

pub const VkOutOfBandQueueTypeNV = enum(u32) {
    RENDER = 0,
    PRESENT = 1,
};

/// VkLatencySubmissionPresentIdNV
pub const VkLatencySubmissionPresentIdNV = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_LATENCY_SUBMISSION_PRESENT_ID_NV,
    pNext: ?*const anyopaque = null,
    presentID: u64 = 0,

    pub const VK_STRUCTURE_TYPE_LATENCY_SUBMISSION_PRESENT_ID_NV = 1000505006;
};

/// VkSwapchainLatencyCreateInfoNV
pub const VkSwapchainLatencyCreateInfoNV = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_SWAPCHAIN_LATENCY_CREATE_INFO_NV,
    pNext: ?*const anyopaque = null,
    latencyModeEnable: u32 = 0, // VkBool32

    pub const VK_STRUCTURE_TYPE_SWAPCHAIN_LATENCY_CREATE_INFO_NV = 1000505007;
};

// ============================================================================
// NVAPI Function Pointers
// ============================================================================

/// Function pointer types for NVAPI (D3D/Desktop)
pub const NvApiFunctions = struct {
    // Initialization
    NvAPI_Initialize: ?*const fn () callconv(.C) NvAPI_Status = null,
    NvAPI_Unload: ?*const fn () callconv(.C) NvAPI_Status = null,
    NvAPI_GetErrorMessage: ?*const fn (NvAPI_Status, [*]u8) callconv(.C) NvAPI_Status = null,

    // Low Latency
    NvAPI_D3D_SetSleepMode: ?*const fn (?*anyopaque, *NV_SET_SLEEP_MODE_PARAMS) callconv(.C) NvAPI_Status = null,
    NvAPI_D3D_GetSleepStatus: ?*const fn (?*anyopaque, *NV_SET_SLEEP_MODE_PARAMS) callconv(.C) NvAPI_Status = null,
    NvAPI_D3D_Sleep: ?*const fn (?*anyopaque) callconv(.C) NvAPI_Status = null,
    NvAPI_D3D_SetLatencyMarker: ?*const fn (?*anyopaque, *NV_LATENCY_MARKER_PARAMS) callconv(.C) NvAPI_Status = null,
    NvAPI_D3D_GetLatency: ?*const fn (?*anyopaque, *NV_LATENCY_RESULT_PARAMS) callconv(.C) NvAPI_Status = null,

    // Library handle
    lib_handle: ?std.DynLib = null,
};

/// Function pointer types for VK_NV_low_latency2
pub const VkLowLatencyFunctions = struct {
    vkSetLatencySleepModeNV: ?*const fn (
        device: *anyopaque, // VkDevice
        swapchain: u64, // VkSwapchainKHR
        pSleepModeInfo: *const VkLatencySleepModeInfoNV,
    ) callconv(.C) i32 = null, // VkResult

    vkLatencySleepNV: ?*const fn (
        device: *anyopaque, // VkDevice
        swapchain: u64, // VkSwapchainKHR
        pSleepInfo: *const VkLatencySleepInfoNV,
    ) callconv(.C) i32 = null,

    vkSetLatencyMarkerNV: ?*const fn (
        device: *anyopaque, // VkDevice
        swapchain: u64, // VkSwapchainKHR
        pLatencyMarkerInfo: *const VkSetLatencyMarkerInfoNV,
    ) callconv(.C) void = null,

    vkGetLatencyTimingsNV: ?*const fn (
        device: *anyopaque, // VkDevice
        swapchain: u64, // VkSwapchainKHR
        pLatencyMarkerInfo: *VkGetLatencyMarkerInfoNV,
    ) callconv(.C) void = null,

    vkQueueNotifyOutOfBandNV: ?*const fn (
        queue: *anyopaque, // VkQueue
        pQueueTypeInfo: *const VkOutOfBandQueueTypeInfoNV,
    ) callconv(.C) void = null,
};

// ============================================================================
// NVAPI Context
// ============================================================================

/// NVAPI runtime context
pub const NvApiContext = struct {
    allocator: std.mem.Allocator,
    initialized: bool = false,

    // Native NVAPI (for D3D under Wine/Proton)
    nvapi_fns: NvApiFunctions = .{},
    nvapi_available: bool = false,

    // Vulkan low latency extension
    vk_ll_fns: VkLowLatencyFunctions = .{},
    vk_ll_available: bool = false,

    // Active device/swapchain for Vulkan
    vk_device: ?*anyopaque = null,
    vk_swapchain: u64 = 0,

    // Current state
    current_mode: NV_LATENCY_MODE = .OFF,
    frame_id: u64 = 0,

    const Self = @This();

    /// Initialize NVAPI context
    pub fn init(allocator: std.mem.Allocator) Self {
        var ctx = Self{
            .allocator = allocator,
        };

        // Try to load native NVAPI (Wine/Proton or native shim)
        ctx.loadNvApi();

        // Vulkan extension is loaded separately via setVulkanDevice

        ctx.initialized = true;
        return ctx;
    }

    /// Cleanup
    pub fn deinit(self: *Self) void {
        if (self.nvapi_fns.NvAPI_Unload) |unload| {
            _ = unload();
        }

        if (self.nvapi_fns.lib_handle) |*lib| {
            lib.close();
            self.nvapi_fns.lib_handle = null;
        }

        self.initialized = false;
    }

    fn loadNvApi(self: *Self) void {
        // Try to load nvapi64.dll (Wine/Proton) or libnvapi-linux.so (native shim)
        const lib_paths = [_][]const u8{
            "libnvapi.so",
            "libnvapi-linux.so",
            "/usr/lib/libnvapi.so",
        };

        for (lib_paths) |path| {
            if (std.DynLib.open(path)) |lib| {
                self.nvapi_fns.lib_handle = lib;
                self.loadNvApiFunctions();
                break;
            } else |_| {
                continue;
            }
        }

        if (self.nvapi_fns.lib_handle == null) {
            log.debug("NVAPI library not found (expected on native Linux without shim)", .{});
            return;
        }

        // Initialize NVAPI
        if (self.nvapi_fns.NvAPI_Initialize) |init_fn| {
            const result = init_fn();
            if (result.isSuccess()) {
                self.nvapi_available = true;
                log.info("NVAPI initialized successfully", .{});
            } else {
                log.warn("NVAPI initialization failed: {}", .{@intFromEnum(result)});
            }
        }
    }

    fn loadNvApiFunctions(self: *Self) void {
        const lib = self.nvapi_fns.lib_handle orelse return;

        self.nvapi_fns.NvAPI_Initialize = lib.lookup(
            *const fn () callconv(.C) NvAPI_Status,
            "NvAPI_Initialize",
        );

        self.nvapi_fns.NvAPI_Unload = lib.lookup(
            *const fn () callconv(.C) NvAPI_Status,
            "NvAPI_Unload",
        );

        self.nvapi_fns.NvAPI_D3D_SetSleepMode = lib.lookup(
            *const fn (?*anyopaque, *NV_SET_SLEEP_MODE_PARAMS) callconv(.C) NvAPI_Status,
            "NvAPI_D3D_SetSleepMode",
        );

        self.nvapi_fns.NvAPI_D3D_Sleep = lib.lookup(
            *const fn (?*anyopaque) callconv(.C) NvAPI_Status,
            "NvAPI_D3D_Sleep",
        );

        self.nvapi_fns.NvAPI_D3D_SetLatencyMarker = lib.lookup(
            *const fn (?*anyopaque, *NV_LATENCY_MARKER_PARAMS) callconv(.C) NvAPI_Status,
            "NvAPI_D3D_SetLatencyMarker",
        );

        self.nvapi_fns.NvAPI_D3D_GetLatency = lib.lookup(
            *const fn (?*anyopaque, *NV_LATENCY_RESULT_PARAMS) callconv(.C) NvAPI_Status,
            "NvAPI_D3D_GetLatency",
        );
    }

    /// Set Vulkan device and load VK_NV_low_latency2 functions
    pub fn setVulkanDevice(
        self: *Self,
        device: *anyopaque,
        swapchain: u64,
        get_device_proc_addr: *const fn (*anyopaque, [*:0]const u8) callconv(.C) ?*anyopaque,
    ) void {
        self.vk_device = device;
        self.vk_swapchain = swapchain;

        // Load VK_NV_low_latency2 functions
        self.vk_ll_fns.vkSetLatencySleepModeNV = @ptrCast(get_device_proc_addr(device, "vkSetLatencySleepModeNV"));
        self.vk_ll_fns.vkLatencySleepNV = @ptrCast(get_device_proc_addr(device, "vkLatencySleepNV"));
        self.vk_ll_fns.vkSetLatencyMarkerNV = @ptrCast(get_device_proc_addr(device, "vkSetLatencyMarkerNV"));
        self.vk_ll_fns.vkGetLatencyTimingsNV = @ptrCast(get_device_proc_addr(device, "vkGetLatencyTimingsNV"));
        self.vk_ll_fns.vkQueueNotifyOutOfBandNV = @ptrCast(get_device_proc_addr(device, "vkQueueNotifyOutOfBandNV"));

        self.vk_ll_available = self.vk_ll_fns.vkSetLatencySleepModeNV != null;

        if (self.vk_ll_available) {
            log.info("VK_NV_low_latency2 extension loaded", .{});
        } else {
            log.debug("VK_NV_low_latency2 extension not available", .{});
        }
    }

    /// Update swapchain (after recreation)
    pub fn updateSwapchain(self: *Self, swapchain: u64) void {
        self.vk_swapchain = swapchain;
    }

    /// Set low latency mode
    pub fn setLatencyMode(self: *Self, mode: NV_LATENCY_MODE) NvApiError!void {
        self.current_mode = mode;

        // Try Vulkan first (native Linux)
        if (self.vk_ll_available) {
            const device = self.vk_device orelse return NvApiError.NotInitialized;

            const sleep_mode_info = VkLatencySleepModeInfoNV{
                .lowLatencyMode = if (mode != .OFF) 1 else 0,
                .lowLatencyBoost = if (mode == .ULTRA) 1 else 0,
                .minimumIntervalUs = 0,
            };

            if (self.vk_ll_fns.vkSetLatencySleepModeNV) |set_fn| {
                const result = set_fn(device, self.vk_swapchain, &sleep_mode_info);
                if (result != 0) { // VK_SUCCESS
                    log.warn("vkSetLatencySleepModeNV failed: {}", .{result});
                    return NvApiError.Unknown;
                }
                log.info("Vulkan low latency mode set: {s}", .{@tagName(mode)});
                return;
            }
        }

        // Fallback to D3D NVAPI (Wine/Proton)
        if (self.nvapi_available) {
            if (self.nvapi_fns.NvAPI_D3D_SetSleepMode) |set_fn| {
                var params = NV_SET_SLEEP_MODE_PARAMS.fromMode(mode);
                const result = set_fn(null, &params);
                if (!result.isSuccess()) {
                    log.warn("NvAPI_D3D_SetSleepMode failed: {}", .{@intFromEnum(result)});
                    if (result.toError()) |err| return err;
                    return NvApiError.Unknown;
                }
                log.info("NVAPI low latency mode set: {s}", .{@tagName(mode)});
                return;
            }
        }

        log.debug("No low latency API available, mode change ignored", .{});
    }

    /// Sleep to synchronize CPU with GPU (reduces input latency)
    pub fn sleep(self: *Self, semaphore: ?u64, value: u64) NvApiError!void {
        if (self.current_mode == .OFF) return;

        // Try Vulkan first
        if (self.vk_ll_available) {
            const device = self.vk_device orelse return NvApiError.NotInitialized;

            const sleep_info = VkLatencySleepInfoNV{
                .signalSemaphore = semaphore orelse 0,
                .value = value,
            };

            if (self.vk_ll_fns.vkLatencySleepNV) |sleep_fn| {
                const result = sleep_fn(device, self.vk_swapchain, &sleep_info);
                if (result != 0) {
                    return NvApiError.Unknown;
                }
                return;
            }
        }

        // Fallback to D3D NVAPI
        if (self.nvapi_available) {
            if (self.nvapi_fns.NvAPI_D3D_Sleep) |sleep_fn| {
                const result = sleep_fn(null);
                if (!result.isSuccess()) {
                    if (result.toError()) |err| return err;
                    return NvApiError.Unknown;
                }
                return;
            }
        }
    }

    /// Set latency marker for timing measurement
    pub fn setMarker(self: *Self, marker: NV_LATENCY_MARKER_TYPE) void {
        if (self.current_mode == .OFF) return;

        // Try Vulkan first
        if (self.vk_ll_available) {
            const device = self.vk_device orelse return;

            const marker_info = VkSetLatencyMarkerInfoNV{
                .presentID = self.frame_id,
                .marker = marker,
            };

            if (self.vk_ll_fns.vkSetLatencyMarkerNV) |set_fn| {
                set_fn(device, self.vk_swapchain, &marker_info);
                return;
            }
        }

        // Fallback to D3D NVAPI
        if (self.nvapi_available) {
            if (self.nvapi_fns.NvAPI_D3D_SetLatencyMarker) |set_fn| {
                var params = NV_LATENCY_MARKER_PARAMS{
                    .frame_id = self.frame_id,
                    .marker_type = marker,
                };
                _ = set_fn(null, &params);
                return;
            }
        }
    }

    /// Get latency timing reports
    pub fn getLatencyTimings(self: *Self, reports: []FrameReport) NvApiError!usize {
        // Try Vulkan first
        if (self.vk_ll_available) {
            const device = self.vk_device orelse return NvApiError.NotInitialized;

            // First call to get count
            var marker_info = VkGetLatencyMarkerInfoNV{};
            if (self.vk_ll_fns.vkGetLatencyTimingsNV) |get_fn| {
                get_fn(device, self.vk_swapchain, &marker_info);

                if (marker_info.timingCount == 0) {
                    return 0;
                }

                // Allocate temp buffer for Vulkan reports
                var vk_timings = self.allocator.alloc(VkLatencyTimingsFrameReportNV, marker_info.timingCount) catch {
                    return NvApiError.Unknown;
                };
                defer self.allocator.free(vk_timings);

                marker_info.pTimings = vk_timings.ptr;
                get_fn(device, self.vk_swapchain, &marker_info);

                // Convert to FrameReport
                const count = @min(marker_info.timingCount, @as(u32, @intCast(reports.len)));
                for (0..count) |i| {
                    reports[i] = vk_timings[i].toFrameReport();
                }

                return count;
            }
        }

        // Fallback to D3D NVAPI
        if (self.nvapi_available) {
            if (self.nvapi_fns.NvAPI_D3D_GetLatency) |get_fn| {
                var params = NV_LATENCY_RESULT_PARAMS{};
                const result = get_fn(null, &params);
                if (!result.isSuccess()) {
                    if (result.toError()) |err| return err;
                    return NvApiError.Unknown;
                }

                // Copy reports
                const count = @min(params.frame_reports.len, reports.len);
                for (0..count) |i| {
                    reports[i] = params.frame_reports[i];
                }

                return count;
            }
        }

        return 0;
    }

    /// Begin frame - call at simulation start
    pub fn beginFrame(self: *Self) void {
        self.frame_id += 1;
        self.setMarker(.SIMULATION_START);
    }

    /// End simulation - call after game logic
    pub fn endSimulation(self: *Self) void {
        self.setMarker(.SIMULATION_END);
    }

    /// Begin render submit
    pub fn beginRenderSubmit(self: *Self) void {
        self.setMarker(.RENDERSUBMIT_START);
    }

    /// End render submit
    pub fn endRenderSubmit(self: *Self) void {
        self.setMarker(.RENDERSUBMIT_END);
    }

    /// Begin present
    pub fn beginPresent(self: *Self) void {
        self.setMarker(.PRESENT_START);
    }

    /// End present
    pub fn endPresent(self: *Self) void {
        self.setMarker(.PRESENT_END);
    }

    /// Mark input sample time
    pub fn markInputSample(self: *Self) void {
        self.setMarker(.INPUT_SAMPLE);
    }

    /// Get current latency mode
    pub fn getLatencyMode(self: *const Self) NV_LATENCY_MODE {
        return self.current_mode;
    }

    /// Check if any low latency API is available
    pub fn isAvailable(self: *const Self) bool {
        return self.vk_ll_available or self.nvapi_available;
    }
};

// ============================================================================
// Public API
// ============================================================================

/// Check if NVAPI or VK_NV_low_latency2 is available
pub fn isLowLatencyAvailable() bool {
    // Check for Vulkan extension availability via driver
    // This is a heuristic - actual availability is per-device
    const driver_paths = [_][]const u8{
        "/usr/lib/libvulkan_nvidia.so",
        "/usr/lib64/libvulkan_nvidia.so",
        "/usr/lib/x86_64-linux-gnu/libvulkan_nvidia.so",
    };

    for (driver_paths) |path| {
        if (std.Io.Dir.accessAbsolute(std.Io.Threaded.global_single_threaded.io(), path, .{})) |_| {
            return true; // NVIDIA Vulkan driver present
        } else |_| {}
    }

    return false;
}

/// Create NVAPI context
pub fn createContext(allocator: std.mem.Allocator) NvApiContext {
    return NvApiContext.init(allocator);
}

// ============================================================================
// Tests
// ============================================================================

test "frame report latency calculation" {
    var report = FrameReport{
        .sim_start_time = 1000,
        .sim_end_time = 2000,
        .render_submit_start_time = 2000,
        .render_submit_end_time = 3000,
        .gpu_render_start_time = 3000,
        .gpu_render_end_time = 5000,
    };

    try std.testing.expectEqual(@as(u64, 4000), report.getPcLatencyUs());
    try std.testing.expectEqual(@as(u64, 1000), report.getGameLatencyUs());
    try std.testing.expectEqual(@as(u64, 1000), report.getRenderLatencyUs());
}

test "sleep mode params from mode" {
    const off = NV_SET_SLEEP_MODE_PARAMS.fromMode(.OFF);
    try std.testing.expectEqual(@as(u32, 0), off.enable_low_latency);
    try std.testing.expectEqual(@as(u32, 0), off.enable_boost);

    const on = NV_SET_SLEEP_MODE_PARAMS.fromMode(.ON);
    try std.testing.expectEqual(@as(u32, 1), on.enable_low_latency);
    try std.testing.expectEqual(@as(u32, 0), on.enable_boost);

    const ultra = NV_SET_SLEEP_MODE_PARAMS.fromMode(.ULTRA);
    try std.testing.expectEqual(@as(u32, 1), ultra.enable_low_latency);
    try std.testing.expectEqual(@as(u32, 1), ultra.enable_boost);
}

test "nvapi context init" {
    const allocator = std.testing.allocator;
    var ctx = NvApiContext.init(allocator);
    defer ctx.deinit();

    try std.testing.expect(ctx.initialized);
}
