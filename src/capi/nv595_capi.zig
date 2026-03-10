//! NVPrime C API - Driver 595+ Features
//!
//! C API exports for new 595 driver features:
//! - Memory health monitoring
//! - ROI/CRC display verification
//! - Enhanced VRR source tracking
//! - DP link training status

const std = @import("std");
const nvprime = @import("nvprime");
const memory = nvprime.nvcore.memory;
const vrr = nvprime.nvdisplay.vrr;
const dp_link = nvprime.nvdisplay.dp_link;
const drm = nvprime.nvruntime.primetime.drm;

// ============================================================================
// Memory Health C API
// ============================================================================

pub const NvMemoryHealth = enum(c_int) {
    healthy = 0,
    warning = 1,
    degraded = 2,
    failing = 3,
};

pub const NvMemoryStatus = extern struct {
    health: NvMemoryHealth,
    correctable_errors: u64,
    uncorrectable_errors: u64,
    lifetime_correctable: u64,
    lifetime_uncorrectable: u64,
    ecc_enabled: bool,
    retired_pages: u32,
};

fn toNvMemoryHealth(health: memory.MemoryHealth) NvMemoryHealth {
    return switch (health) {
        .healthy => .healthy,
        .warning => .warning,
        .degraded => .degraded,
        .failing => .failing,
    };
}

export fn nvprime_memory_get_health(index: u32) NvMemoryHealth {
    const status = memory.checkHealth(index) catch return .healthy;
    return toNvMemoryHealth(status.health);
}

export fn nvprime_memory_has_errors(index: u32) bool {
    return memory.hasErrors(index) catch false;
}

export fn nvprime_memory_has_critical_errors(index: u32) bool {
    return memory.hasCriticalErrors(index) catch false;
}

export fn nvprime_memory_ecc_enabled(index: u32) bool {
    return memory.isEccEnabled(index) catch false;
}

export fn nvprime_memory_get_status(index: u32, out_status: ?*NvMemoryStatus) c_int {
    if (out_status == null) return -1;

    const status = memory.checkHealth(index) catch return -1;

    out_status.?.* = NvMemoryStatus{
        .health = toNvMemoryHealth(status.health),
        .correctable_errors = status.correctable_errors,
        .uncorrectable_errors = status.uncorrectable_errors,
        .lifetime_correctable = status.lifetime_correctable,
        .lifetime_uncorrectable = status.lifetime_uncorrectable,
        .ecc_enabled = status.ecc_enabled,
        .retired_pages = status.retired_pages,
    };

    return 0;
}

export fn nvprime_memory_get_error_counts(index: u32, correctable: ?*u64, uncorrectable: ?*u64) c_int {
    const counts = memory.getErrorCounts(index) catch return -1;

    if (correctable) |c| c.* = counts.correctable;
    if (uncorrectable) |u| u.* = counts.uncorrectable;

    return 0;
}

// ============================================================================
// ROI/CRC C API
// ============================================================================

pub const NvRoiRect = extern struct {
    x: u32,
    y: u32,
    width: u32,
    height: u32,
};

pub const NvRoiCrc = extern struct {
    region_handle: u64,
    crc: u64,
};

pub const NvRoiCapabilities = extern struct {
    max_rois: u32,
    supports_crc: bool,
    min_region_width: u32,
    min_region_height: u32,
};

export fn nvprime_roi_get_capabilities(drm_fd: c_int, crtc_id: u32, out_caps: ?*NvRoiCapabilities) c_int {
    if (out_caps == null) return -1;
    if (drm_fd < 0) return -1;

    const allocator = std.heap.page_allocator;
    var mgr = drm.RoiManager.init(allocator, @intCast(drm_fd));
    defer mgr.deinit();

    const caps = mgr.getCapabilities(crtc_id) catch return -1;

    out_caps.?.* = NvRoiCapabilities{
        .max_rois = caps.max_rois,
        .supports_crc = caps.supports_crc,
        .min_region_width = caps.min_region_width,
        .min_region_height = caps.min_region_height,
    };

    return 0;
}

export fn nvprime_roi_register(drm_fd: c_int, rect: ?*const NvRoiRect, out_handle: ?*u64) c_int {
    if (rect == null or out_handle == null) return -1;
    if (drm_fd < 0) return -1;

    const allocator = std.heap.page_allocator;
    var mgr = drm.RoiManager.init(allocator, @intCast(drm_fd));
    // Note: Don't deinit here as that would unregister the ROI

    const drm_rect = drm.RoiRect{
        .x = rect.?.x,
        .y = rect.?.y,
        .width = rect.?.width,
        .height = rect.?.height,
    };

    const handle = mgr.registerRoi(drm_rect) catch return -1;
    out_handle.?.* = handle;

    return 0;
}

export fn nvprime_roi_unregister(drm_fd: c_int, handle: u64) c_int {
    if (drm_fd < 0) return -1;

    const allocator = std.heap.page_allocator;
    var mgr = drm.RoiManager.init(allocator, @intCast(drm_fd));
    defer mgr.deinit();

    mgr.unregisterRoi(handle) catch return -1;

    return 0;
}

export fn nvprime_roi_get_crcs(drm_fd: c_int, crtc_id: u32, out_crcs: ?[*]NvRoiCrc, max_count: u32) c_int {
    if (out_crcs == null or max_count == 0) return -1;
    if (drm_fd < 0) return -1;

    const allocator = std.heap.page_allocator;
    var mgr = drm.RoiManager.init(allocator, @intCast(drm_fd));
    defer mgr.deinit();

    var drm_crcs: [drm.NV_DRM_MAX_ROIS_PER_CRTC]drm.RoiCrc = undefined;
    const count = mgr.getCrcs(crtc_id, &drm_crcs) catch return -1;

    const copy_count = @min(count, max_count);
    for (0..copy_count) |i| {
        out_crcs.?[i] = NvRoiCrc{
            .region_handle = drm_crcs[i].region_handle,
            .crc = drm_crcs[i].crc,
        };
    }

    return @intCast(count);
}

export fn nvprime_roi_verify(drm_fd: c_int, crtc_id: u32, handle: u64, expected_crc: u64) bool {
    if (drm_fd < 0) return false;

    const allocator = std.heap.page_allocator;
    var mgr = drm.RoiManager.init(allocator, @intCast(drm_fd));
    defer mgr.deinit();

    return mgr.verifyRegion(crtc_id, handle, expected_crc) catch false;
}

// ============================================================================
// VRR Source Tracking C API
// ============================================================================

pub const NvVrrSource = enum(c_int) {
    drm_property = 0,
    edid_parsed = 1,
    nvidia_settings = 2,
    default = 3,
};

pub const NvVrrRange = extern struct {
    min_hz: u32,
    max_hz: u32,
    source: NvVrrSource,
    lfc_capable: bool,
    range_reliable: bool,
};

fn toNvVrrSource(source: vrr.VrrSource) NvVrrSource {
    return switch (source) {
        .drm_property => .drm_property,
        .edid_parsed => .edid_parsed,
        .nvidia_settings => .nvidia_settings,
        .default => .default,
    };
}

export fn nvprime_vrr_get_range(display_name: ?[*:0]const u8, out_range: ?*NvVrrRange) c_int {
    if (display_name == null or out_range == null) return -1;

    const name_slice = std.mem.span(display_name.?);
    const state = vrr.getState(name_slice) catch return -1;

    out_range.?.* = NvVrrRange{
        .min_hz = state.min_hz,
        .max_hz = state.max_hz,
        .source = toNvVrrSource(state.source),
        .lfc_capable = state.lfc_supported,
        .range_reliable = state.isRangeReliable(),
    };

    return 0;
}

export fn nvprime_vrr_range_reliable(display_name: ?[*:0]const u8) bool {
    if (display_name == null) return false;

    const name_slice = std.mem.span(display_name.?);
    const state = vrr.getState(name_slice) catch return false;

    return state.isRangeReliable();
}

// ============================================================================
// DP Link Training C API
// ============================================================================

pub const NvDpLinkTrainingState = enum(c_int) {
    idle = 0,
    in_progress = 1,
    completed = 2,
    failed = 3,
};

pub const NvDpLinkRate = enum(u8) {
    unknown = 0,
    rbr = 0x06,
    hbr = 0x0a,
    hbr2 = 0x14,
    hbr3 = 0x1e,
    uhbr10 = 0x01,
    uhbr13_5 = 0x04,
    uhbr20 = 0x02,
};

pub const NvDpLinkStatus = extern struct {
    display_id: u32,
    link_rate: NvDpLinkRate,
    lane_count: u8,
    training_state: NvDpLinkTrainingState,
    fec_enabled: bool,
    link_stable: bool,
    bandwidth_gbps: f32,
};

export fn nvprime_dp_is_training(display_id: u32) bool {
    return dp_link.isTrainingInProgress(display_id);
}

export fn nvprime_dp_get_status(display_id: u32, out_status: ?*NvDpLinkStatus) c_int {
    if (out_status == null) return -1;

    const status = dp_link.getLinkStatus(display_id) orelse return -1;

    out_status.?.* = NvDpLinkStatus{
        .display_id = status.display_id,
        .link_rate = switch (status.link_rate) {
            .rbr => .rbr,
            .hbr => .hbr,
            .hbr2 => .hbr2,
            .hbr3 => .hbr3,
            .uhbr10 => .uhbr10,
            .uhbr13_5 => .uhbr13_5,
            .uhbr20 => .uhbr20,
            .unknown => .unknown,
        },
        .lane_count = status.lane_count,
        .training_state = switch (status.training_state) {
            .idle => .idle,
            .in_progress => .in_progress,
            .completed => .completed,
            .failed => .failed,
        },
        .fec_enabled = status.fec_enabled,
        .link_stable = status.link_stable,
        .bandwidth_gbps = status.totalBandwidthGbps(),
    };

    return 0;
}

export fn nvprime_dp_rate_bandwidth(rate: NvDpLinkRate) f32 {
    return switch (rate) {
        .rbr => 1.62,
        .hbr => 2.7,
        .hbr2 => 5.4,
        .hbr3 => 8.1,
        .uhbr10 => 10.0,
        .uhbr13_5 => 13.5,
        .uhbr20 => 20.0,
        .unknown => 0.0,
    };
}

export fn nvprime_dp_rate_is_uhbr(rate: NvDpLinkRate) bool {
    return switch (rate) {
        .uhbr10, .uhbr13_5, .uhbr20 => true,
        else => false,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "memory health c api types" {
    _ = NvMemoryHealth.healthy;
    _ = NvMemoryStatus{
        .health = .healthy,
        .correctable_errors = 0,
        .uncorrectable_errors = 0,
        .lifetime_correctable = 0,
        .lifetime_uncorrectable = 0,
        .ecc_enabled = false,
        .retired_pages = 0,
    };
}

test "roi c api types" {
    _ = NvRoiRect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    _ = NvRoiCrc{ .region_handle = 0, .crc = 0 };
    _ = NvRoiCapabilities{
        .max_rois = 64,
        .supports_crc = true,
        .min_region_width = 8,
        .min_region_height = 8,
    };
}

test "vrr source c api types" {
    _ = NvVrrSource.drm_property;
    _ = NvVrrRange{
        .min_hz = 48,
        .max_hz = 144,
        .source = .drm_property,
        .lfc_capable = true,
        .range_reliable = true,
    };
}

test "dp link c api types" {
    _ = NvDpLinkTrainingState.idle;
    _ = NvDpLinkRate.hbr3;
    _ = NvDpLinkStatus{
        .display_id = 0,
        .link_rate = .hbr3,
        .lane_count = 4,
        .training_state = .completed,
        .fec_enabled = true,
        .link_stable = true,
        .bandwidth_gbps = 32.4,
    };
}
