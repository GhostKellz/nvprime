/**
 * @file nvprime.h
 * @brief NVPrime C API - Unified NVIDIA Linux Platform
 *
 * This header provides the C API for NVPrime, a comprehensive library
 * for managing NVIDIA GPUs on Linux.
 *
 * ## Quick Start
 * ```c
 * #include <nvprime.h>
 *
 * int main() {
 *     if (nvprime_init() != 0) return 1;
 *
 *     int count = nvprime_get_gpu_count();
 *     printf("Found %d GPU(s)\n", count);
 *
 *     for (int i = 0; i < count; i++) {
 *         NvGpuCapabilities caps;
 *         if (nvprime_get_gpu_caps(i, &caps) == 0) {
 *             printf("GPU %d: %s (%s)\n", i, caps.name,
 *                    nvprime_get_arch_name(caps.architecture));
 *             printf("  VRAM: %lu MB\n", caps.vram_total_mb);
 *             printf("  RTX: %s, DLSS: %s, Reflex: %s\n",
 *                    caps.supports_rtx ? "yes" : "no",
 *                    caps.supports_dlss ? "yes" : "no",
 *                    caps.supports_reflex ? "yes" : "no");
 *         }
 *     }
 *
 *     nvprime_shutdown();
 *     return 0;
 * }
 * ```
 *
 * ## Linking
 * Link against: -lnvprime -lnvidia-ml
 */

#ifndef NVPRIME_H
#define NVPRIME_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * Version
 * ============================================================================ */

#define NVPRIME_VERSION "0.1.0"
#define NVPRIME_VERSION_MAJOR 0
#define NVPRIME_VERSION_MINOR 1
#define NVPRIME_VERSION_PATCH 0

/** Get library version string */
const char* nvprime_version(void);

/** Get library version as packed integer (major * 10000 + minor * 100 + patch) */
int nvprime_version_int(void);

/* ============================================================================
 * Initialization
 * ============================================================================ */

/**
 * Initialize the NVPrime library.
 * Must be called before any other nvprime functions.
 * @return 0 on success, negative on error
 */
int nvprime_init(void);

/**
 * Shutdown the NVPrime library.
 * Call when done using nvprime.
 */
void nvprime_shutdown(void);

/* ============================================================================
 * GPU Architecture
 * ============================================================================ */

typedef enum {
    NV_ARCH_UNKNOWN = 0,
    NV_ARCH_KEPLER = 1,
    NV_ARCH_MAXWELL = 2,
    NV_ARCH_PASCAL = 3,
    NV_ARCH_VOLTA = 4,
    NV_ARCH_TURING = 5,
    NV_ARCH_AMPERE = 6,
    NV_ARCH_ADA_LOVELACE = 7,
    NV_ARCH_HOPPER = 8,
    NV_ARCH_BLACKWELL = 9,
} NvArchitecture;

/** Get human-readable architecture name */
const char* nvprime_get_arch_name(NvArchitecture arch);

/* ============================================================================
 * GPU Capabilities (nvcaps)
 * ============================================================================ */

typedef struct {
    uint32_t index;
    char name[96];
    char uuid[96];
    NvArchitecture architecture;
    int32_t compute_major;
    int32_t compute_minor;
    uint64_t vram_total_mb;
    uint64_t vram_used_mb;
    char pcie_bus_id[32];
    uint32_t pcie_gen;
    uint32_t pcie_width;
    bool supports_rtx;
    bool supports_dlss;
    bool supports_dlss3;
    bool supports_reflex;
    bool supports_nvenc;
    bool supports_power_management;
    bool supports_clock_control;
    bool supports_fan_control;
    uint32_t temperature_c;
    float power_draw_w;
    float power_limit_w;
    uint32_t gpu_clock_mhz;
    uint32_t mem_clock_mhz;
    uint32_t pstate;
} NvGpuCapabilities;

/** Get number of detected GPUs */
int nvprime_get_gpu_count(void);

/** Get capabilities for a specific GPU */
int nvprime_get_gpu_caps(uint32_t index, NvGpuCapabilities* out_caps);

/** Feature support queries */
bool nvprime_gpu_supports_rtx(uint32_t index);
bool nvprime_gpu_supports_dlss(uint32_t index);
bool nvprime_gpu_supports_dlss3(uint32_t index);
bool nvprime_gpu_supports_reflex(uint32_t index);
bool nvprime_gpu_supports_nvenc(uint32_t index);

/** Get GPU name (copies to buffer, returns bytes written or -1 on error) */
int nvprime_get_gpu_name(uint32_t index, char* buffer, size_t buffer_size);

/** Get VRAM info */
uint64_t nvprime_get_vram_total(uint32_t index);
uint64_t nvprime_get_vram_used(uint32_t index);

/* ============================================================================
 * GPU Core State (nvcore)
 * ============================================================================ */

typedef enum {
    NV_PROFILE_MAXIMUM = 0,
    NV_PROFILE_BALANCED = 1,
    NV_PROFILE_EFFICIENT = 2,
    NV_PROFILE_QUIET = 3,
} NvPerformanceProfile;

typedef struct {
    uint32_t gpu_clock_mhz;
    uint32_t mem_clock_mhz;
    uint32_t sm_clock_mhz;
    uint32_t video_clock_mhz;
    uint32_t pstate;
    uint32_t gpu_utilization;
    uint32_t mem_utilization;
} NvCoreState;

typedef struct {
    uint32_t min_gpu_mhz;
    uint32_t max_gpu_mhz;
    uint32_t min_mem_mhz;
    uint32_t max_mem_mhz;
    uint32_t default_gpu_mhz;
    uint32_t default_mem_mhz;
} NvClockLimits;

/** Get current core state */
int nvprime_core_get_state(uint32_t index, NvCoreState* out_state);

/** Get clock limits */
int nvprime_core_get_clock_limits(uint32_t index, NvClockLimits* out_limits);

/** Clock queries */
int nvprime_core_get_gpu_clock(uint32_t index);
int nvprime_core_get_mem_clock(uint32_t index);
int nvprime_core_get_sm_clock(uint32_t index);
int nvprime_core_get_video_clock(uint32_t index);
int nvprime_core_get_max_gpu_clock(uint32_t index);
int nvprime_core_get_max_mem_clock(uint32_t index);

/** P-state and utilization */
int nvprime_core_get_pstate(uint32_t index);
int nvprime_core_get_gpu_utilization(uint32_t index);
int nvprime_core_get_mem_utilization(uint32_t index);

/** Profile helpers */
uint32_t nvprime_profile_gpu_clock_percent(NvPerformanceProfile profile);
uint32_t nvprime_profile_mem_clock_percent(NvPerformanceProfile profile);
uint32_t nvprime_profile_power_limit_percent(NvPerformanceProfile profile);

/* ============================================================================
 * Power & Thermal (nvpower)
 * ============================================================================ */

typedef enum {
    NV_FAN_AUTO = 0,
    NV_FAN_MANUAL = 1,
    NV_FAN_CURVE = 2,
    NV_FAN_ZERO_RPM = 3,
} NvFanMode;

typedef enum {
    NV_HEALTH_OPTIMAL = 0,
    NV_HEALTH_MODERATE = 1,
    NV_HEALTH_THROTTLING = 2,
    NV_HEALTH_CRITICAL = 3,
} NvPowerHealth;

typedef enum {
    NV_EFF_PERFORMANCE = 0,
    NV_EFF_BALANCED = 1,
    NV_EFF_QUIET = 2,
    NV_EFF_EFFICIENCY = 3,
} NvEfficiencyMode;

typedef struct {
    float power_draw_w;
    float power_limit_w;
    float power_limit_default_w;
    float power_limit_min_w;
    float power_limit_max_w;
    uint32_t gpu_temp_c;
    uint32_t memory_temp_c;
    uint32_t hotspot_temp_c;
    uint32_t thermal_target_c;
    uint32_t thermal_slowdown_c;
    uint32_t thermal_shutdown_c;
    uint32_t fan_speed_percent;
    uint32_t fan_speed_rpm;
    uint32_t fan_target_percent;
    NvFanMode fan_mode;
} NvPowerState;

/** Get current power/thermal state */
int nvprime_power_get_state(uint32_t index, NvPowerState* out_state);

/** Get power health status */
NvPowerHealth nvprime_power_get_health(uint32_t index);

/** Throttling checks */
bool nvprime_power_is_thermal_throttling(uint32_t index);
bool nvprime_power_is_power_throttling(uint32_t index);

/** Power queries */
float nvprime_power_get_power_draw(uint32_t index);
float nvprime_power_get_power_limit(uint32_t index);

/** Set power limit in milliwatts (requires elevated privileges) */
int nvprime_power_set_power_limit(uint32_t index, uint32_t limit_mw);

/** Thermal queries */
int nvprime_power_get_temperature(uint32_t index);
int nvprime_power_get_fan_speed(uint32_t index);

/** Efficiency mode helpers */
uint32_t nvprime_efficiency_power_percent(NvEfficiencyMode mode);
uint32_t nvprime_efficiency_thermal_target(NvEfficiencyMode mode);

/* ============================================================================
 * Memory Health (Driver 595+)
 * ============================================================================ */

typedef enum {
    NV_MEM_HEALTHY = 0,
    NV_MEM_WARNING = 1,
    NV_MEM_DEGRADED = 2,
    NV_MEM_FAILING = 3,
} NvMemoryHealth;

typedef struct {
    NvMemoryHealth health;
    uint64_t correctable_errors;
    uint64_t uncorrectable_errors;
    uint64_t lifetime_correctable;
    uint64_t lifetime_uncorrectable;
    bool ecc_enabled;
    uint32_t retired_pages;
} NvMemoryStatus;

/** Get memory health status */
NvMemoryHealth nvprime_memory_get_health(uint32_t index);

/** Check if GPU has memory errors */
bool nvprime_memory_has_errors(uint32_t index);

/** Check if GPU has critical (uncorrectable) errors */
bool nvprime_memory_has_critical_errors(uint32_t index);

/** Check if ECC is enabled */
bool nvprime_memory_ecc_enabled(uint32_t index);

/** Get full memory status */
int nvprime_memory_get_status(uint32_t index, NvMemoryStatus* out_status);

/** Get ECC error counts */
int nvprime_memory_get_error_counts(uint32_t index, uint64_t* correctable, uint64_t* uncorrectable);

/* ============================================================================
 * ROI/CRC Display Verification (Driver 595+)
 * ============================================================================ */

typedef struct {
    uint32_t x;
    uint32_t y;
    uint32_t width;
    uint32_t height;
} NvRoiRect;

typedef struct {
    uint64_t region_handle;
    uint64_t crc;
} NvRoiCrc;

typedef struct {
    uint32_t max_rois;
    bool supports_crc;
    uint32_t min_region_width;
    uint32_t min_region_height;
} NvRoiCapabilities;

/** Get ROI capabilities for a CRTC */
int nvprime_roi_get_capabilities(int drm_fd, uint32_t crtc_id, NvRoiCapabilities* out_caps);

/** Register a region of interest */
int nvprime_roi_register(int drm_fd, const NvRoiRect* rect, uint64_t* out_handle);

/** Unregister a region of interest */
int nvprime_roi_unregister(int drm_fd, uint64_t handle);

/** Get CRCs for all registered ROIs on a CRTC */
int nvprime_roi_get_crcs(int drm_fd, uint32_t crtc_id, NvRoiCrc* out_crcs, uint32_t max_count);

/** Verify a region's CRC matches expected value */
bool nvprime_roi_verify(int drm_fd, uint32_t crtc_id, uint64_t handle, uint64_t expected_crc);

/* ============================================================================
 * VRR Source Tracking (Driver 595+)
 * ============================================================================ */

typedef enum {
    NV_VRR_SOURCE_DRM_PROPERTY = 0,  /**< From DRM vrr_min_hz/vrr_max_hz properties (most reliable) */
    NV_VRR_SOURCE_EDID_PARSED = 1,   /**< Parsed from EDID Display Range Limits */
    NV_VRR_SOURCE_NVIDIA_SETTINGS = 2, /**< From nvidia-settings query */
    NV_VRR_SOURCE_DEFAULT = 3,       /**< Default fallback values */
} NvVrrSource;

typedef struct {
    uint32_t min_hz;
    uint32_t max_hz;
    NvVrrSource source;
    bool lfc_capable;
    bool range_reliable;  /**< True if source is DRM property */
} NvVrrRange;

/** Get VRR range with source information */
int nvprime_vrr_get_range(const char* display_name, NvVrrRange* out_range);

/** Check if VRR range is from a reliable source (DRM property) */
bool nvprime_vrr_range_reliable(const char* display_name);

/* ============================================================================
 * DP Link Training (Driver 595+)
 * ============================================================================ */

typedef enum {
    NV_DP_LT_IDLE = 0,
    NV_DP_LT_IN_PROGRESS = 1,
    NV_DP_LT_COMPLETED = 2,
    NV_DP_LT_FAILED = 3,
} NvDpLinkTrainingState;

typedef enum {
    NV_DP_RATE_UNKNOWN = 0,
    NV_DP_RATE_RBR = 0x06,      /**< 1.62 Gbps */
    NV_DP_RATE_HBR = 0x0a,      /**< 2.7 Gbps */
    NV_DP_RATE_HBR2 = 0x14,     /**< 5.4 Gbps */
    NV_DP_RATE_HBR3 = 0x1e,     /**< 8.1 Gbps */
    NV_DP_RATE_UHBR10 = 0x01,   /**< 10 Gbps (DP 2.0) */
    NV_DP_RATE_UHBR13_5 = 0x04, /**< 13.5 Gbps (DP 2.0) */
    NV_DP_RATE_UHBR20 = 0x02,   /**< 20 Gbps (DP 2.0) */
} NvDpLinkRate;

typedef struct {
    uint32_t display_id;
    NvDpLinkRate link_rate;
    uint8_t lane_count;
    NvDpLinkTrainingState training_state;
    bool fec_enabled;
    bool link_stable;
    float bandwidth_gbps;  /**< Total bandwidth (rate * lanes) */
} NvDpLinkStatus;

/** Check if DP link training is in progress */
bool nvprime_dp_is_training(uint32_t display_id);

/** Get DP link status */
int nvprime_dp_get_status(uint32_t display_id, NvDpLinkStatus* out_status);

/** Get link rate bandwidth in Gbps */
float nvprime_dp_rate_bandwidth(NvDpLinkRate rate);

/** Check if rate is UHBR (DP 2.0) */
bool nvprime_dp_rate_is_uhbr(NvDpLinkRate rate);

/* ============================================================================
 * Convenience aliases
 * ============================================================================ */

/** Alias for common queries */
#define nvprime_get_gpu_temperature(idx) nvprime_power_get_temperature(idx)
#define nvprime_get_gpu_power_usage(idx) ((int)(nvprime_power_get_power_draw(idx) * 1000))
#define nvprime_get_gpu_clock(idx) nvprime_core_get_gpu_clock(idx)
#define nvprime_get_mem_clock(idx) nvprime_core_get_mem_clock(idx)
#define nvprime_get_pstate(idx) nvprime_core_get_pstate(idx)

#ifdef __cplusplus
}
#endif

#endif /* NVPRIME_H */
