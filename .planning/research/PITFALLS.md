# Project Research — PITFALLS (milestone v2.0)

**Dimension:** 常见陷阱与预防——新增功能(gpu-next 升级/ANGLE 绕过/8K/HUD/拖拽)在本系统上的坑
**Date:** 2026-10-24 · **Method:** media-kit 社区反馈 + v1 经验(CONCERNS/UPSTREAM/perf docs)

## P1. 重定基陷阱(mpv-master 推进)

- **警告:** 0004 历史上 13 hunk 中 5 个需手工重排(UPSTREAM.md 记录了 master 对 vo_gpu_next 的重构点);本次 380 行差异预示同类工作。`git apply` 在本机**假成功**(每 hunk 静默 skip)——必须 GNU `patch -p1` + 事后 diff。
- **预防:** 复用 Phase 5 流程:更新 MPV_VERSION → `check_patches.sh` 红 → 重放补丁 → 绿;手工重排 hunk 逐条记录进 UPSTREAM.md;重定基后立即跑六目标 CI + integration test。

## P2. Impeller/引擎版本陷阱(ANGLE 绕过)

- **警告:** [flutter#191468](https://github.com/flutter/flutter/issues/191468):Impeller 下 DXGI 共享句柄纹理在 3.47.0 首帧崩溃(access violation),#191017 于 main 修复——**3.47.6 是否包含未验证**;Impeller Windows 尚未默认,行为随版本漂移。
- **预防:** spike 先行(REA 逆向本机 flutter_windows.dll 的纹理消费路径 + `--enable-impeller` 冒烟);桥接保留 DxgiSharedHandle 回退(运行时探测/事件上报);CI 锁定 Flutter 版本(一致性检查器已有 SDK 约束项,可加 Flutter 版本核对);禁 MPO/HAGS 类环境问题只文档化(HUD 观测,不强求修复,#15196 教训)。

## P3. 合成路径切换的帧生命周期陷阱

- **警告:** v1 逆向结论:ANGLE 绑定**无 GPU fence**,仅交换链队列深度(~3 帧)界定安全窗口——我们 quarantine=4 由此而来。切换合成路径(或收紧 quarantine)若高估回收时机 → use-after-release 崩溃;低估 → 白增 4 帧延迟(8K 下 4×33ms=132ms)。
- **预防:** 每条合成路径各自实测安全预算(基准 + 长播);`CompositorLatency()` 按路径参数化而非拍脑袋;deviceLost/renderError 风暴检测已有,保持。

## P4. 8K 内存修复的层次陷阱

- **警告:** 在错误的层修(如 native 环里硬编码特判、或全局调小 demuxer 队列伤 1080p 吞吐)会造成"8K 能跑但 4K 变差"。
- **预防:** 修复在 Player 选项包层按帧尺寸推导(ARCHITECTURE §3);1080p/4K/8K 三档回归基准同时把关;修复后 8K 30 分钟长播门禁才算关闭。

## P5. media-kit 同源问题域(共享架构的坑,应主动排查)

- 共享句柄生命周期/释放竞争(media-kit 反复出现的黑帧/崩溃家族)——我们 Phase 2 的 resize-while-playing 阻塞问题(退休图像未消费)同族;v2 改动帧生命周期时须重跑 100 轮交错 soak
- 驱动差异(NVIDIA/AMD/Intel)——我们 CI 只有 lavapipe/MoltenVK 软件侧;真机矩阵(用户 RTX 4060)是唯一硬证据
- seek 后冻结([mpv#17258](https://github.com/mpv-player/mpv/issues/17258),2026-01)——重定基后在我们的桥接上显式回归 seek→画面恢复

## P6. HUD/拖拽的低风险陷阱

- desktop_drop 与 MpvVideo 的手势冲突:DropTarget 需正确 hit-test 包裹(不吞播放器点击);多文件拖入只取首个视频文件,其余忽略并在 HUD 提示
- HUD 轮询属性(`demuxer-cache-state` 是大 map)每秒一次足够——别学 stats.lua 帧级轮询打进生产热路径(Phase 4 刚优化过)

## P7. 版本/溯源一致性(v1 建立的门禁别丢)

- 重定基 = MPV_VERSION 变 → README/ARCHITECTURE/一致性检查器联动(CONSISTENCY 门禁会抓)
- 若 Flutter 版本因 Impeller 需要锁定/升级:五处 pubspec + flutter-plugin.yml + 一致性检查同步(新增 Flutter-floor 核对项)

**各坑的归属阶段:** P1→重定基层;P2/P3→桥接层(spike 先行);P4→8K 层;P5→桥接与回归层;P6→example 层;P7→收尾层。
