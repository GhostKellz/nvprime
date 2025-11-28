<div align="center">

# NVPrime

![Built with Zig](https://img.shields.io/badge/Built%20with-Zig-F7A41D?style=for-the-badge&logo=zig&logoColor=white)
![NVIDIA](https://img.shields.io/badge/NVIDIA-76B900?style=for-the-badge&logo=nvidia&logoColor=white)
![Wayland](https://img.shields.io/badge/Wayland-FFBC00?style=for-the-badge&logo=wayland&logoColor=black)
![Vulkan](https://img.shields.io/badge/Vulkan-AC162C?style=for-the-badge&logo=vulkan&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)

![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)
![Platform](https://img.shields.io/badge/Platform-Linux%20x86__64-lightgrey?style=flat-square)
![Driver](https://img.shields.io/badge/NVIDIA%20Driver-535%2B-76B900?style=flat-square)
![Status](https://img.shields.io/badge/Status-In%20Development-orange?style=flat-square)

**Unified NVIDIA Linux Platform**

*The comprehensive NVIDIA subsystem layer for Linux*

</div>

NVPrime is the comprehensive NVIDIA subsystem layer for Linux — not just gaming, not just drivers, but everything NVIDIA touches on Linux. Think of it as AMD's ROCm, but broader: gaming, workstation, AI/compute, streaming, and creative workflows unified under one platform.

## Vision

```
┌─────────────────────────────────────────────────────────────┐
│            Games / AI / Creative Apps / Streaming           │
├─────────────────────────────────────────────────────────────┤
│                    Ghostflare UI & HUD                       │
├─────────────────────────────────────────────────────────────┤
│                     NVPrime Platform                         │
├─────────────────────────────────────────────────────────────┤
│                      GhostKernel                             │
├─────────────────────────────────────────────────────────────┤
│                        Linux                                 │
└─────────────────────────────────────────────────────────────┘
```

## Architecture

NVPrime is organized into focused subsystems:

```
NVPrime
├── nvruntime/        # Gaming runtime stack
│   ├── nvvulkan      # NVIDIA-optimized Vulkan layers
│   ├── nvdxvk        # NVIDIA-specific DXVK patches
│   ├── nvwine        # Wine patches for NVIDIA gaming
│   ├── primetime     # Gaming compositor (wlroots-based, Gamescope alternative)
│   └── nvstream      # Low-latency game streaming
│
├── nvcore/           # GPU fundamentals
│   ├── clocks        # GPU/memory clock management
│   ├── pstates       # Performance state control
│   ├── boost         # Boost clock logic
│   └── voltage       # Voltage curve management
│
├── nvpower/          # Power & thermals
│   ├── limits        # Power limit management
│   ├── thermals      # Temperature monitoring/control
│   ├── fans          # Fan curve management
│   └── efficiency    # Power efficiency modes
│
├── nvdisplay/        # Display pipeline
│   ├── gsync         # G-Sync / VRR control
│   ├── hdr           # HDR management
│   ├── vrr           # Variable refresh rate
│   └── multimon      # Multi-monitor orchestration
│
├── nvdlss/           # AI features gateway
│   ├── dlss          # DLSS integration
│   ├── reflex        # Reflex low-latency
│   ├── broadcast     # RTX Broadcast features
│   └── video         # RTX Video enhancements
│
├── nvhud/            # Overlay & telemetry
│   ├── overlay       # In-game overlay system
│   ├── metrics       # Performance metrics
│   ├── logging       # Telemetry logging
│   └── alerts        # System alerts/notifications
│
├── nvcaps/           # Capability discovery
│   ├── detect        # Hardware detection
│   ├── profiles      # Capability profiles
│   ├── features      # Feature availability
│   └── compat        # Compatibility checking
│
└── nvpkg/            # System integration
    ├── install       # Installation management
    ├── update        # Update system
    ├── config        # Configuration management
    └── hooks         # System hooks (udev, systemd)
```

## Subsystem Details

### nvruntime - Gaming Runtime Stack

The gaming-focused runtime, equivalent to what we discussed as "nvruntime" standalone:

```
nvruntime
├── nvvulkan     # Vulkan extensions & layers for gaming
│   └── VK_NV_low_latency2, diagnostics, memory extensions
│
├── nvdxvk       # NVIDIA-specific DXVK patches
│   └── Reflex injection, async compute optimization
│
├── nvwine       # Wine patches for NVIDIA
│   └── NVAPI stubs, driver compatibility
│
├── primetime    # Gaming compositor (wlroots-based, Gamescope alternative)
│   └── NVIDIA-native, low latency, FSR/NIS integration
│
└── nvstream     # Low-latency game streaming
    └── NVENC optimization, Moonlight integration
```

### nvcore - GPU Fundamentals

Low-level GPU control:

```zig
const nvcore = @import("nvprime").core;

// Clock management
try nvcore.clocks.setGpuClock(.{ .min = 1500, .max = 2100 });
try nvcore.clocks.setMemoryClock(.{ .target = 10501 });

// P-state control
try nvcore.pstates.lock(.p0);  // Lock to highest performance
try nvcore.pstates.unlock();   // Return to dynamic

// Boost management
try nvcore.boost.setOffset(100);  // +100MHz offset
```

### nvpower - Power & Thermals

```zig
const nvpower = @import("nvprime").power;

// Power limits
try nvpower.limits.set(.{ .watts = 320, .percent = 100 });

// Fan control
try nvpower.fans.setCurve(&[_]FanPoint{
    .{ .temp = 40, .speed = 30 },
    .{ .temp = 60, .speed = 50 },
    .{ .temp = 80, .speed = 100 },
});

// Thermal targets
try nvpower.thermals.setTarget(83);  // 83°C target
```

### nvdisplay - Display Pipeline

```zig
const nvdisplay = @import("nvprime").display;

// G-Sync control
try nvdisplay.gsync.enable("DP-1");
try nvdisplay.gsync.setRange(.{ .min = 30, .max = 165 });

// HDR
try nvdisplay.hdr.enable("DP-1", .{
    .format = .hdr10,
    .peak_brightness = 1000,
});

// VRR
try nvdisplay.vrr.setMode(.gsync_compatible);
```

### nvdlss - AI Features Gateway

```zig
const nvdlss = @import("nvprime").dlss;

// Check DLSS support
const caps = try nvdlss.getCapabilities();
if (caps.dlss_supported) {
    std.log.info("DLSS {s} supported", .{caps.dlss_version});
}

// Reflex control
try nvdlss.reflex.setMode(.boost);
const latency = try nvdlss.reflex.getLatency();
```

## CLI Interface

```bash
# Overall status
nvprime status

# Subsystem-specific
nvprime core status
nvprime power status
nvprime display status
nvprime runtime status

# Configuration
nvprime core clock --gpu 2100 --memory 10501
nvprime power limit --watts 320
nvprime display gsync enable --monitor DP-1

# Gaming runtime
nvprime runtime vulkan status
nvprime runtime dxvk patch --apply
nvprime runtime compositor start

# Profiles
nvprime profile gaming      # Apply gaming profile
nvprime profile workstation # Apply workstation profile
nvprime profile efficiency  # Apply power-saving profile
```

## Integration with Ecosystem

### Relationship to Existing nv* Projects

| Project | Relationship | Status |
|---------|--------------|--------|
| **nvcontrol** | GUI/TUI frontend for NVPrime | Calls nvprime APIs |
| **nvlatency** | Implements nvruntime/reflex | Merged into nvprime |
| **nvshader** | Standalone, nvprime-aware | Integrates via IPC |
| **nvsync** | Implements nvdisplay/vrr | Merged into nvprime |
| **nvvk** | Implements nvruntime/nvvulkan | Merged into nvprime |
| **nvproton** | Orchestration layer | Calls nvprime runtime |
| **envyhub** | Implements nvhud | Merged into nvprime |

### GhostKernel Integration

```
GhostKernel (Zig kernel + NVIDIA open driver)
     ↓
NVPrime (userspace NVIDIA platform)
     ↓
Applications (games, AI, creative)
```

NVPrime provides the userspace complement to GhostKernel's kernel-level NVIDIA integration.

### Ghostflare Integration

Ghostflare (your gaming UI) sits on top:

```
Ghostflare (Gaming UI)
     ↓ uses
NVPrime APIs
     ↓ uses
nvhud for overlays
nvruntime for game launching
nvdisplay for monitor config
```

## Why Zig?

NVPrime is written in Zig because:

1. **Kernel-adjacent** - Works closely with GhostKernel
2. **Zero GC** - Critical for low-latency gaming paths
3. **C ABI** - Easy integration with NVIDIA libraries (NVML, CUDA)
4. **Performance** - GPU control paths must be fast
5. **Consistency** - Matches nvvk, nvlatency, nvshader, etc.

Rust is used for:
- nvcontrol (GUI)
- nvproton (orchestration)
- Web services
- CLIs with complex argument parsing

## Building

```bash
# Build all subsystems
zig build -Doptimize=ReleaseFast

# Build specific subsystem
zig build nvcore -Doptimize=ReleaseFast
zig build nvruntime -Doptimize=ReleaseFast

# Build with all features
zig build -Doptimize=ReleaseFast -Dall-subsystems=true

# Run tests
zig build test
```

## Installation

```bash
# System-wide install
sudo zig build install --prefix /usr/local

# Install systemd services
sudo cp systemd/*.service /etc/systemd/system/
sudo systemctl enable nvprime.service

# Install udev rules
sudo cp udev/*.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
```

## Target Audiences

| Audience | Primary Subsystems |
|----------|-------------------|
| **Gamers** | nvruntime, nvdisplay, nvhud, nvdlss |
| **Workstation** | nvcore, nvpower, nvdisplay |
| **AI/ML** | nvcore, nvpower, nvcaps |
| **Streamers** | nvruntime/nvstream, nvhud, nvdlss |
| **Creators** | nvdisplay, nvdlss, nvcore |

## Requirements

- NVIDIA GPU (Maxwell or newer for full features)
- NVIDIA driver 535+ (open kernel modules recommended)
- Linux 5.15+ (6.x recommended)
- Zig 0.12+
- Optional: GhostKernel for optimal integration

## License

MIT License - See [LICENSE](LICENSE)

## Contributing

See [TODO.md](TODO.md) for the development roadmap.

---

*NVPrime: The foundation for NVIDIA on Linux*
