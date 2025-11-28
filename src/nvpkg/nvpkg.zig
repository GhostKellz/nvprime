//! nvpkg - System Integration & Package Management
//!
//! Installation, updates, configuration, and system hooks.
//! Phase 10 implementation - currently stubbed.

const std = @import("std");

pub const version = "0.1.0-dev";

/// Installation status
pub const InstallStatus = enum {
    not_installed,
    installed,
    needs_update,
    broken,
};

/// Get installation status
pub fn getStatus() InstallStatus {
    return .not_installed;
}

/// Configuration paths
pub const Paths = struct {
    config_dir: []const u8,
    data_dir: []const u8,
    cache_dir: []const u8,

    pub fn default() Paths {
        return Paths{
            .config_dir = "/etc/nvprime",
            .data_dir = "/usr/share/nvprime",
            .cache_dir = "/var/cache/nvprime",
        };
    }

    pub fn user() Paths {
        // Would use XDG paths
        return Paths{
            .config_dir = "~/.config/nvprime",
            .data_dir = "~/.local/share/nvprime",
            .cache_dir = "~/.cache/nvprime",
        };
    }
};

test "nvpkg stub" {
    try std.testing.expectEqual(InstallStatus.not_installed, getStatus());
}
