# Project Research — STACK (milestone v2.0)

**Dimension:** 技术栈与关键 API——绕过 Windows ANGLE 的可行路径
**Date:** 2026-10-24 · **Method:** 本地引擎头文件实证(example/windows/flutter/ephemeral,Flutter 3.47.6)+ 网络调研

## 关键事实(本地实证,最高置信度)

Flutter 3.47.6 的 `flutter_texture_registrar.h`(example/windows/flutter/ephemeral)定义两种 GPU 表面类型:

- `kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle` — 传 `HANDLE`(我们当前使用的,mpv_kit_video_plugin.cpp:219)
- `kFlutterDesktopGpuSurfaceTypeD3d11Texture2D` — 传裸 `ID3D11Texture2D*`,要求资源"stay valid until opened by Flutter",配 `release_callback`

另有 `FlutterDesktopViewGetGraphicsAdapter`(flutter_windows.h:305)暴露引擎渲染用的 `IDXGIAdapter`(我们已用它建自己的 D3D11 设备)。

## 引擎后端真相(网络调研)

- **Skia+ANGLE 后端**(当前 Windows 默认):引擎的 `ExternalTextureD3d`/`ExternalTextureDXGI` **两种表面类型最终都经 ANGLE** 绑定为 GL 纹理——切换表面类型枚举**不构成**真正的 ANGLE 绕过。ANGLE 路径的已知缺陷(我们已逆向记录,d3d11_interop.h:27-32):无 GPU fence、仅靠交换链队列深度(~3 帧)+当前帧界定采样安全,我们的 quarantine=4 即为此设计。
- **Impeller(Windows)**:外部纹理走原生 D3D 合成路径——这才是"绕过 ANGLE"。但 [flutter#191468](https://github.com/flutter/flutter/issues/191468)(P2):DXGI shared-handle 纹理在 Impeller 下于 3.47.0 stable 首帧 access violation,`--no-enable-impeller` 可避,PR #191017 于 main 修复(2026-09 确认)。3.47.6 是否含修复未验证——我们的 UHD 长跑(3.47.6,默认后端)全绿,说明默认(Skia/ANGLE)路径稳定。
- **media-kit 的 Windows 管线**([media-kit](https://github.com/media-kit/media-kit)):libmpv → ANGLE(GLES→D3D11)→ 共享纹理 → Flutter。社区痛点集中在 ANGLE 开销、共享句柄生命周期、驱动差异;上游"Flutter 引擎新的 ID3D11Texture2D 直接支持正在减少 ANGLE 翻译层"(与上条一致)。

## 结论:绕过 ANGLE 的真实选项

| 选项 | 机制 | 依赖/风险 |
|------|------|-----------|
| A. Impeller 原生路径(spike 优先) | 应用开启 Impeller(或等待默认),桥接保持/切换到 D3d11Texture2D;引擎原生 D3D 合成 | 需验证 3.47.6 是否含 #191017;Impeller Windows 成熟度;允许 REA 逆向 flutter_windows.dll 确认其纹理消费路径(用户已授权) |
| B. D3d11Texture2D 表面类型(Skia 后端下) | 裸指针要求同设备——需在**引擎的** D3D11 设备上创建纹理(而非我们自建设备) | Skia/ANGLE 后端下仍经 ANGLE,收益仅省一次 handle 打开;引擎设备未直接暴露(需 EGL 查询或 REA) |
| C. 直接渲染窗口合成(DirectComposition 子窗口) | mpv 渲染进自己的 swapchain,DComp 视觉层叠加在 Flutter 窗口上 | 完全绕过 Flutter 纹理系统;失去 widget 合成(遮挡/圆角/变换);media-kit 生态未采用;仅作后备 |

**推荐方向:** 先做选项 A 的 spike(REA 验证 3.47.6 引擎二进制的纹理消费路径 + Impeller 开关验证),保留现有 DxgiSharedHandle 为回退;选项 B 作为 Skia 后端下的增量优化;C 仅记录不采用。

## 集成点

- `d3d11_interop.{h,cpp}`:`vulkan()` 门控、`CreateImage`(KMT 纹理创建)、`CompositorLatency()=4`(ANGLE 无 fence 的 quarantine 预算)
- `mpv_kit_video_plugin.cpp:210-230`:纹理注册回调(表面类型选择点)
- 桥接后端协商:`MpvVideoEventKind`/`reason` 通道(Phase 3 的诚实 reason 基建)可承载"composited via Impeller/D3D"信息

## 不做什么

- 不引入新的第三方渲染依赖;不改 Dart 公共 API 的既有签名(新增只读诊断字段可在需求阶段确认)
- 不在未验证 #191017 前把 Impeller 设为默认

**Sources:** [flutter#191468](https://github.com/flutter/flutter/issues/191468) · [flutter_texture_registrar.h (local, 3.47.6)](https://docs.flutter.dev/platform-integration/windows/building) · [media-kit](https://github.com/media-kit/media-kit) · [media_kit_video changelog](https://pub.dev/packages/media_kit_video/changelog) · [windows_gpu_recovery(ANGLE/D3D11 故障模式参考)](https://pub.dev/packages/windows_gpu_recovery)
