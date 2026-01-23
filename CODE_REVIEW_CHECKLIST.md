## Code Review Checklist

- **Build & Tooling**: Verify `zig build` (debug/release) and `zig build test` succeed; confirm `build.zig.zon` dependency hashes (nvvk, ghostVK, nvhud, nvlatency, nvsync, nvshader, zeus) are current and sources reachable; validate optional flags `-Dnvml`/`-Ddrm` paths on target distros.
- **Subsystem Coverage**: Read `src/root.zig` wiring and ensure each subsystem (nvcore, nvpower, nvdisplay, nvruntime, nvdlss, nvcaps, nvhud) exposes consistent API and error handling; confirm C API in `src/capi`/`include/nvprime.h` matches Zig exports.
- **Runtime Gaps**: Inspect TODO hotspots: `primetime/primetime.zig` (Vulkan context pass-through, VRR toggles), `nvstream/nvstream.zig` (connection setup, encoder reconfig, data pump), `dbus/dbus.zig` (multi-GPU); assess feasibility and add issues/tasks.
- **Display/DRM**: Test `-Ddrm=true` paths; validate VRR/HDR/GSYNC toggles and multimonitor handling; ensure wlroots/DRM shims compile even when unused; check fallback when DRM/NVML absent.
- **Latency/Overlay**: Confirm integration contracts with nvlatency/nvhud/nvvk/ghostVK/nvsync: ABI expectations, feature flags, and version pins; add smoke tests for overlay/latency paths if available.
- **Performance & Safety**: Audit power/thermal/clock setters for limits and clamp logic; ensure fail-closed on NVML errors; verify no UB from unchecked pointer casts or FFI structs in bindings.
- **Packaging & Install**: Review `pkg/`, `systemd/`, `udev/` assets and defaults (`nvprime.conf`); confirm permissions, service ordering, and environment variables; document platform requirements.
- **Testing Strategy**: Identify missing unit/integration tests per subsystem; add minimal harnesses for bindings, DRM feature flags, and C API surface; decide on CI matrix (with/without NVML/DRM).
- **Docs & UX**: Align README/TODO with current capabilities; describe feature flags and typical workflows; ensure CLI help covers subsystems and error messages are actionable.
