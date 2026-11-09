# API Coverage — mpv D3D11 render API (render_d3d11.h, upstream 4255130de4), libplacebo pl_d3d11, Direct3D 11 sync/sharing, shaderc/SPIRV-Cross

> Full coverage by default. Opt-outs are explicit, reasoned decisions.

| capability | decision | reason |
|---|---|---|
| mpv MPV_RENDER_API_TYPE_D3D11 render context | INTEGRATE | |
| mpv MPV_RENDER_PARAM_D3D11_INIT_PARAMS (host device) | INTEGRATE | |
| mpv MPV_RENDER_PARAM_D3D11_FBO (host texture target) | INTEGRATE | |
| mpv gpu renderer on D3D11 (libmpv_gpu_context_d3d11) | INTEGRATE | |
| mpv gpu-next renderer on D3D11 (patch 0004 branch) | INTEGRATE | |
| mpv renderer report via get_info under D3D11 | INTEGRATE | |
| mpv persistent shader cache under D3D11 (DXBC) | INTEGRATE | |
| render_d3d11.h threading contract (immediate context, render thread only) | INTEGRATE | |
| render_d3d11.h cross-device sync via keyed mutex | OPT-OUT | Flutter's ANGLE consumer never acquires a keyed mutex (ADR 0003); producer fence plus quarantine 4 instead |
| D3D11 single-threaded device flag | OPT-OUT | render_d3d11.h: it limits hwdec to d3d11va-copy; the device is always multithread-protected |
| libplacebo pl_d3d11_create on the host device | INTEGRATE | |
| libplacebo pl_d3d11_wrap of the host texture | INTEGRATE | |
| libplacebo pl_d3d11 swapchain | OPT-OUT | not needed: libmpv renders into a host texture, there is no window |
| libplacebo pl_d3d11 debug layer | OPT-OUT | release bundle; validation is not shipped to applications |
| Direct3D 11 ID3D11Fence producer completion | INTEGRATE | |
| Direct3D 11 D3D11_QUERY_EVENT completion fallback | INTEGRATE | |
| Direct3D 11 legacy KMT MISC_SHARED texture sharing | INTEGRATE | |
| Direct3D 11 NT-handle shared resources | OPT-OUT | Flutter opens the handle with OpenSharedResource, which takes KMT handles only (ADR 0003) |
| Direct3D 11 device removal detection (GetDeviceRemovedReason) | INTEGRATE | |
| Direct3D 11 typed UAV on shared BGRA8 textures | OPT-OUT | not needed: shared targets keep RT+SRV binds like the Vulkan path; measured in 14-01 for the record |
| mpv d3d11va zero-copy hwdec (hwdec_d3d11va) | OPT-OUT | explicitly out of scope: default hwdec list and zero-copy proof are Phase 16 (HWD-01/HWD-02) |
| SPIRV-Cross SPIR-V to HLSL (shared DLL) | INTEGRATE | |
| shaderc GLSL to SPIR-V for ra_d3d11 | INTEGRATE | |
