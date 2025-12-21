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
