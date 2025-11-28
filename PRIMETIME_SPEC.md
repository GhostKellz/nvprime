# PrimeTime – NVIDIA-Optimized Wayland Gaming Compositor (NVPrime Module)

> **Location (target):** `nvprime/src/nvruntime/primetime/`  
> **Role:** Internal NVPrime subsystem – *not* a standalone project  
> **Goal:** Be the NVIDIA-aware, low-latency Wayland compositor core that VENOM and nvcontrol build on top of.

---

## 1. Purpose & Scope

PrimeTime is the **gaming compositor core** inside NVPrime.  
It is not a full desktop environment and not a generic “one compositor to rule them all.”

Instead, it focuses on:

- **NVIDIA-first tuning**:
  - Reflex / VK_NV_low_latency2
  - HDR / VRR / G-Sync
  - Direct scan-out and low-latency frame pacing
- **Fullscreen & borderless gaming paths**:
  - Single-game fullscreen sessions (Gamescope-like)
  - Controlled multi-output support with deterministic behavior
- **Integration with NVPrime**:
  - Uses `nvcaps`, `nvcore`, `nvpower`, `nvdisplay` for GPU + display control
  - Exposes telemetry to `nvhud` and higher-level tools (VENOM, Ghostflare)

PrimeTime is the **engine**.  
VENOM is the **shell**.  
nvcontrol / Ghostflare are the **brains / UI**.

---

## 2. High-Level Design

### 2.1 Responsibilities

PrimeTime is responsible for:

- Creating and managing a **Wayland compositor instance** optimized for games
- Managing **outputs** (monitors, modes, HDR/VRR flags)
- Managing **surfaces**:
  - One “primary game” surface per session
  - Optional overlay surfaces (HUD, notifications)
- Providing **NVIDIA-aware frame scheduling** hooks:
  - VRR on/off per-output
  - Frame cap / limiter inputs (for nvsync)
  - Latency markers for nvlatency
- Exposing a **control/telemetry API** for:
  - VENOM to launch a “game session”
  - nvcontrol to visualize state
  - Ghostflare to switch modes/presets later

PrimeTime is **not** responsible for:

- Multi-tenant desktop window management
- Tiling, stacking, and generic DE behaviors
- Input remapping layers for every use-case
- Complex policy (that lives in VENOM / Ghostflare)

---

## 3. Integration Points

### 3.1 NVPrime Subsystems

PrimeTime relies on other NVPrime subsystems:

- `nvcaps`
  - Query available GPUs, driver version, supported features
  - Decide whether low-latency / Reflex / HDR / VRR are truly available

- `nvcore`
  - Read and optionally set clock/power profiles for **game sessions**
  - Provide safe ranges and constraints so PrimeTime never hardcodes risk

- `nvpower`
  - Real-time telemetry for:
    - GPU power draw
    - Temperatures (GPU, memory, hotspot)
  - Emission of “thermal stress” events for HUD & Ghostflare

- `nvdisplay`
  - Enumerate outputs, supported modes, VRR ranges
  - Set modes (resolution, refresh rate) for the compositor device
  - Turn HDR on/off, configure HDR metadata

PrimeTime uses those subsystems via a **clean Zig API**, internal to NVPrime.

---

### 3.2 External Libraries

PrimeTime is built on:

- **wlroots** (C): Wayland compositor framework
- **wlroots-zig** (if/when used): Zig bindings/abstractions around wlroots
- **Vulkan**:
  - Rendering pipeline for composition
  - Integration with NV Vulkan extensions (via `nvvk` where useful)

We treat wlroots and Vulkan as “plumbing”; the NVIDIA-specific logic comes from:

- `nvvk` (Vulkan helpers & NV extensions)
- `nvlatency` (Reflex / VK_NV_low_latency2 integration)
- `nvsync` (frame pacing, VRR helpers)

---

### 3.3 Higher-Level Users

PrimeTime is consumed by:

- **VENOM**:
  - Starts PrimeTime, attaches to a specific output/mode
  - Requests a “session” to host a game surface
  - Uses PrimeTime to handle window focus, exclusive fullscreen, overlays

- **Ghostflare**:
  - Indirectly – sets “Gaming” or “Creator” modes that may instruct VENOM/PrimeTime to:
    - Enable/disable VRR
    - Cap FPS
    - Prefer HDR vs SDR
    - Select different latency profiles

- **nvhud**:
  - Receives telemetry and frame timing data from PrimeTime
  - Renders overlay via Vulkan layer (or child surface) on top of the game

PrimeTime itself is **headless in terms of UX**. It’s a service, not a product.

---

## 4. Core Concepts & APIs

### 4.1 Sessions

PrimeTime exposes a conceptual API (pseudocode-ish):

- `primetime::SessionId primetime_start_session(SessionConfig)`
- `primetime_stop_session(SessionId)`
- `primetime_attach_game_surface(SessionId, SurfaceHandle)`
- `primetime_attach_overlay(SessionId, OverlayHandle)`
- `primetime_set_mode(SessionId, OutputSelection, ModeSelection)`
- `primetime_set_frame_policy(SessionId, FramePolicy)`
- `primetime_query_state(SessionId) -> SessionState`

This maps to a limited set of use patterns:

- **Single Game Fullscreen**:
  - One session, one primary output, one fullscreen surface
- **Game + HUD**:
  - Same as above, plus an overlay surface
- **Dual Output (future)**:
  - Main game on primary monitor
  - Mirrored or secondary output with same frame pacing policy

### 4.2 Configuration Structures (Conceptual)

```text
SessionConfig:
  gpu_id: GpuId           # from nvcaps
  primary_output: OutputId
  mode: ModeSelection     # 3840x2160@240, etc.
  hdr: bool
  vrr: bool
  latency_profile: LowLatencyProfile   # e.g., Ultra / On / Off
  vsync_policy: VSyncPolicy            # Off / On / Adaptive / Uncapped

FramePolicy:
  fps_cap: Option<u32>                 # None = uncapped
  low_latency: LowLatencyProfile
  vrr_enabled: bool
  present_mode: PresentMode            # immediate / mailbox / fifo variants
```

These are implemented in Zig, but they correspond to stable concepts that:

VENOM can serialize from config

Ghostflare can influence via high-level modes

---

## 5. Rendering & Latency Pipeline
### 5.1 Rendering Path

Standard path:

wlroots manages Wayland protocol, DRM/KMS device, inputs.

PrimeTime registers a Vulkan renderer:

Backed by a device created with nvvk helpers.

Client surfaces (game, overlay) are composed into the output framebuffer.

Frame is submitted using:

Present modes chosen to align with VRR / frame cap / latency profile.

Swapchain & present logic incorporate nvsync rules for:

VRR boundaries

Frame pacing

Tear/timing behavior (for competitive modes).

### 5.2 Latency & Reflex Hooks

At frame boundaries, PrimeTime calls into nvlatency:

Set latency markers (simulation start, render submit, present).

Query timing data for HUD.

If VK_NV_low_latency2 is available:

Use vkLatencySleepNV and vkSetLatencySleepModeNV to adjust wake-up timing.

Provide hooks for:

“Boost” / “Ultra” low-latency modes

Frame time histogram data for Ghostflare / logging;

---

## 6. HDR, VRR, and Multi-Monitor
### 6.1 HDR

PrimeTime relies on nvdisplay & nvvk to:

Detect HDR capabilities (HDR10, etc.)

Switch modes in a safe way:

Ensure compositor & game both see consistent color space

Manage HDR metadata:

Peak brightness, mastering data, etc.

Initially:

Single HDR pipeline per session (primary monitor only).

Future: better handling when UI is SDR and game is HDR (VENOM UX layer).

### 6.2 VRR / G-Sync

Through nvdisplay + nvsync we:

Enable/disable VRR per-output

Query VRR range

Choose frame pacing that:

Stays within VRR band when possible

Avoids oscillations for “variable” FPS games

Expose a few VRR presets:

Competitive (tight cap just below max Hz)

Smooth (looser cap for cinematic games)

Off (for determinism or capture)

### 6.3 Multi-Monitor Strategy (Initial)

Initial PrimeTime goals:

Primary output first:

Always pick one “game output”

Other outputs either:

Mirrored (same content, same timing)

Turned off for minimal noise

Later:

Extended desktop-like behavior is handled by VENOM, not PrimeTime’s core.

## 7. Control & IPC

PrimeTime will provide an internal control plane that can be wrapped for:

In-process embedding by VENOM:

VENOM links directly against nvprime and calls PrimeTime APIs.

IPC (future):

Unix socket or D-Bus-style interface for remote control / scripting.

Ghostflare or external tools can toggle modes without direct linking.

For now, the spec focuses on library-style embedding, not network control.

## 8. Milestones (Implementation Phases)

These are PrimeTime-specific milestones inside the NVPrime roadmap.

Phase PT-1 – Skeleton

 Create nvruntime/primetime module

 Wire basic wlroots compositor (no NVIDIA-specific magic yet)

 One output, one fullscreen surface, basic input support

 Minimal session API (start_session, stop_session)

Phase PT-2 – NVPrime Integration

 Integrate nvcaps to pick GPU / features

 Integrate nvdisplay for mode selection & VRR flags

 Integrate nvcore / nvpower for basic telemetry

 Expose frame timing and events to nvhud hooks

Phase PT-3 – Low-Latency & VRR

 Wire in nvsync for frame pacing logic

 Integrate nvlatency for latency markers & control

 Implement VRR-aware present modes

 Provide frame cap presets (e.g., “240Hz competitive”, “120Hz cinematic”)

Phase PT-4 – HDR & Overlays

 HDR mode switching via nvdisplay + Vulkan

 Basic HDR metadata emission

 Add overlay support for nvhud (HUD as child surface or Vulkan overlay)

 Expose API to toggle overlay visibility and positioning

Phase PT-5 – VENOM Integration & Polish

 Define stable PrimeTime API boundary for VENOM

 Implement example “venom run” path using PrimeTime session API

 Add diagnostics: primetime --debug-session (or via env vars)

 Document PrimeTime usage in docs/PRIMETIME.md (developer-facing)

9. Non-Goals (Explicit)

To keep PrimeTime lean and focused:

❌ No “full DE” features (tiling, taskbar, notifications center, etc.)

❌ No input macros / keybinding editor (that’s VENOM / Ghostflare territory)

❌ No generic multi-user seat management

❌ No support for arbitrary XWayland window zoo – only what’s needed to run games cleanly

❌ No vendor-agnostic abstractions – PrimeTime is unapologetically NVIDIA-focused

10. Summary

PrimeTime is:

The NVIDIA-tuned Wayland gaming compositor core for NVPrime

A library-like subsystem consumed by VENOM and nvcontrol

Built on wlroots + Vulkan, wired tightly into:

nvcaps, nvcore, nvpower, nvdisplay

nvsync, nvlatency, nvvk, nvhud

If VENOM is your “Gamescope killer,”
PrimeTime is the engine that makes it possible.
