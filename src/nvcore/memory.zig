//! nvcore/memory - GPU Memory Health Monitoring
//!
//! Memory error detection and health assessment for GPU reliability monitoring.
//! Uses NVML ECC (Error Correcting Code) APIs to detect memory errors before
//! they cause crashes or data corruption.
//!
//! Driver 595+ provides enhanced memory subsystem error detection.

const std = @import("std");
const nvml = @import("../bindings/nvml.zig");

/// Memory health status levels
pub const MemoryHealth = enum {
    /// No errors detected, memory is operating normally
    healthy,
    /// Some correctable errors detected (ECC corrected them)
    /// GPU is still functional but should be monitored
    warning,
    /// Multiple correctable errors or approaching thresholds
    /// Consider scheduling maintenance
    degraded,
    /// Uncorrectable errors detected - data corruption possible
    /// Immediate attention required
    failing,

    pub fn description(self: MemoryHealth) []const u8 {
        return switch (self) {
            .healthy => "Memory operating normally",
            .warning => "Correctable errors detected (ECC corrected)",
            .degraded => "Multiple errors - monitor closely",
            .failing => "Uncorrectable errors - immediate attention required",
        };
    }

    pub fn isCritical(self: MemoryHealth) bool {
        return self == .failing;
    }
};

/// Comprehensive memory status
pub const MemoryStatus = struct {
    health: MemoryHealth,
    /// Errors corrected by ECC (since driver load)
    correctable_errors: u64,
    /// Errors that could not be corrected (data corruption possible)
    uncorrectable_errors: u64,
    /// Lifetime accumulated correctable errors
    lifetime_correctable: u64,
    /// Lifetime accumulated uncorrectable errors
    lifetime_uncorrectable: u64,
    /// Whether ECC is enabled on this GPU
    ecc_enabled: bool,
    /// Number of pages retired due to errors
    retired_pages: u32,

    pub fn print(self: MemoryStatus, writer: anytype) !void {
        try writer.print("Memory Health: {s}\n", .{self.health.description()});
        try writer.print("  ECC Enabled: {}\n", .{self.ecc_enabled});
        try writer.print("  Correctable Errors: {} (lifetime: {})\n", .{
            self.correctable_errors,
            self.lifetime_correctable,
        });
        try writer.print("  Uncorrectable Errors: {} (lifetime: {})\n", .{
            self.uncorrectable_errors,
            self.lifetime_uncorrectable,
        });
        if (self.retired_pages > 0) {
            try writer.print("  Retired Pages: {}\n", .{self.retired_pages});
        }
    }
};

/// Thresholds for health classification
const HealthThresholds = struct {
    /// Correctable errors before warning
    warning_correctable: u64 = 10,
    /// Correctable errors before degraded
    degraded_correctable: u64 = 100,
    /// Any uncorrectable error is failing
    failing_uncorrectable: u64 = 1,
};

const default_thresholds = HealthThresholds{};

/// Determine health level based on error counts
fn classifyHealth(correctable: u64, uncorrectable: u64, thresholds: HealthThresholds) MemoryHealth {
    if (uncorrectable >= thresholds.failing_uncorrectable) {
        return .failing;
    }
    if (correctable >= thresholds.degraded_correctable) {
        return .degraded;
    }
    if (correctable >= thresholds.warning_correctable) {
        return .warning;
    }
    return .healthy;
}

/// Check memory health for a GPU
pub fn checkHealth(device_index: u32) !MemoryStatus {
    const device = nvml.getDeviceByIndex(device_index) catch |err| {
        return err;
    };

    // Check if ECC is enabled
    const ecc_enabled = nvml.isEccEnabled(device) catch false;

    // Get volatile (since driver load) error counts
    const volatile_counts = nvml.getEccErrorCounts(device) catch nvml.EccErrorCounts{
        .correctable = 0,
        .uncorrectable = 0,
    };

    // Get aggregate (lifetime) error counts
    const aggregate_counts = nvml.getAggregateEccErrorCounts(device) catch nvml.EccErrorCounts{
        .correctable = 0,
        .uncorrectable = 0,
    };

    // Get retired pages
    const retired = nvml.getRetiredPages(device) catch .{
        .due_to_multiple_single_bit = 0,
        .due_to_double_bit = 0,
    };
    const total_retired = retired.due_to_multiple_single_bit + retired.due_to_double_bit;

    // Classify health
    const health = classifyHealth(
        volatile_counts.correctable,
        volatile_counts.uncorrectable,
        default_thresholds,
    );

    return MemoryStatus{
        .health = health,
        .correctable_errors = volatile_counts.correctable,
        .uncorrectable_errors = volatile_counts.uncorrectable,
        .lifetime_correctable = aggregate_counts.correctable,
        .lifetime_uncorrectable = aggregate_counts.uncorrectable,
        .ecc_enabled = ecc_enabled,
        .retired_pages = total_retired,
    };
}

/// Quick check if device has any memory errors
pub fn hasErrors(device_index: u32) !bool {
    const device = try nvml.getDeviceByIndex(device_index);
    return nvml.hasMemoryErrors(device) catch false;
}

/// Quick check if device has critical (uncorrectable) errors
pub fn hasCriticalErrors(device_index: u32) !bool {
    const device = try nvml.getDeviceByIndex(device_index);
    return nvml.hasUncorrectableErrors(device) catch false;
}

/// Check if ECC is enabled on the device
pub fn isEccEnabled(device_index: u32) !bool {
    const device = try nvml.getDeviceByIndex(device_index);
    return nvml.isEccEnabled(device) catch false;
}

/// Get error counts without full status
pub fn getErrorCounts(device_index: u32) !struct { correctable: u64, uncorrectable: u64 } {
    const device = try nvml.getDeviceByIndex(device_index);
    const counts = try nvml.getEccErrorCounts(device);
    return .{
        .correctable = counts.correctable,
        .uncorrectable = counts.uncorrectable,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "memory health classification" {
    // No errors = healthy
    try std.testing.expectEqual(MemoryHealth.healthy, classifyHealth(0, 0, default_thresholds));

    // Some correctable = warning
    try std.testing.expectEqual(MemoryHealth.warning, classifyHealth(15, 0, default_thresholds));

    // Many correctable = degraded
    try std.testing.expectEqual(MemoryHealth.degraded, classifyHealth(150, 0, default_thresholds));

    // Any uncorrectable = failing
    try std.testing.expectEqual(MemoryHealth.failing, classifyHealth(0, 1, default_thresholds));
    try std.testing.expectEqual(MemoryHealth.failing, classifyHealth(100, 1, default_thresholds));
}

test "memory status struct" {
    const status = MemoryStatus{
        .health = .healthy,
        .correctable_errors = 0,
        .uncorrectable_errors = 0,
        .lifetime_correctable = 5,
        .lifetime_uncorrectable = 0,
        .ecc_enabled = true,
        .retired_pages = 0,
    };

    try std.testing.expect(!status.health.isCritical());
    try std.testing.expect(status.ecc_enabled);
}

test "memory health enum" {
    try std.testing.expect(MemoryHealth.failing.isCritical());
    try std.testing.expect(!MemoryHealth.healthy.isCritical());
    try std.testing.expect(!MemoryHealth.warning.isCritical());
    try std.testing.expect(!MemoryHealth.degraded.isCritical());
}
