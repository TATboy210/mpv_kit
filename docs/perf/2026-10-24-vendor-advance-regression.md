# Vendor-Advance Regression Record — mpv 0.41.0-1115 (REBASE-02)

**Date:** 2026-10-24 · **New base:** `b2c255c13e8e`（2026-10-09 upstream，blob 匹配 + 全树 diff=0 识别）· **Old base:** `fd9265a905`

## Build source（显式记录）

**回归目标二进制 = mpv_kit_libs hook 构建 `v0.1.0-dev.3`（2026-10-23，`windows-x64/lib/libmpv-2.dll`）。**
正当性：07-01 证明新 vendor 树与旧 vendor 树**除 MPV_VERSION 文本外字节级等同**（`git diff --cached --stat native/mpv` 仅 1 文件 1 行；wayland/io.c 两处 delta 已被上游 b2c255c 前的两个提交吸收，v1 vendoring 时即已存在于树中）。dev.3 构建的源 = 旧 vendor = 新 vendor 的功能等同源；对该二进制回归即对新 vendor 源回归。本地无 MSYS2/meson 工具链（`native/out/win64` 是 CI 构件解包，非本地构建），无法另行本地重建——按计划退路评估后采用上述等同性论证并在此明示。CI push 后将从新树真实构建六目标（native-verify/build.sh）。

## 结果总表

| 项 | 结果 | 证据 |
|----|------|------|
| PATCH-DRIFT（新基线） | ✅ `PATCH-DRIFT OK base=b2c255c13e8e patches=7` | 07-01 提交 9590dca |
| CONSISTENCY / PINS / MATRIX | ✅ 三门禁全绿 | 同上 |
| mpv_kit 套件 | ✅ 112 passed / 2 skipped | dev.3 二进制 |
| mpv_kit_video 套件 | ✅ 21 passed | 同上 |
| api_freeze | ✅ 通过 | 同上 |
| seek 恢复回归（新测试） | ✅ `SEEK-RECOVERY OK media=lavfi events=[]`——forward-mid/near-end/rapid-followup 全部精确落位恢复，无 renderError 风暴、无 deviceLost | 提交 d193173；RED 证据：修复前 pos=11.5 在 30s 窗口外失败 |
| decode 微基准 | ✅ double 130 ns/op、map 1088 ns/op（v1 after 带宽 102-113/927-950 内噪声） | 本机 |
| 4K 30 分钟 endurance | ⛔ **环境阻塞：磁盘满**（见下） | /tmp/uhd_4k_rebase*.log |
| 六目标 CI + 三平台 integration | ⏳ 随 push 动态执行 | — |

## 4K endurance 环境阻塞（如实记录）

本日多次 4K 长播尝试全部失败，**根因为宿主磁盘写满，非代码回归**：

1. `D:` 100%（0 GB free）、`C:` 99%（2 GB）——释放会话产物后仍 100%（磁盘总占用系宿主数据，非本仓库）。
2. 失败签名与 v1 的 8K 提交耗尽**不同**：无新 WER 事件（最后一条仍是 16:01 的 v1 8K 记录）；进程死亡于 10s–2min 不等；同时段 640x360 的 seek/集成测试全绿。
3. 独立佐证：**完全相同的二进制（dev.3）当日 15:56 在本机通过过 4K 30 分钟全门禁**（v1 Phase 4 记录，docs/perf/2026-10-24-uhd-endurance.md）；其源与新 vendor 字节等同（见上）。磁盘写满亦复现了 CMakeCache 截断（320 行处 parse error）导致 example 无法重建的连锁故障。

**解除条件：** 宿主释放 ≥10 GB 磁盘后，独占重跑
`MPV_KIT_BENCH_SIZE=3840x2160 MPV_KIT_BENCH_SECONDS=1800 ... flutter test integration_test/uhd_endurance_test.dart -d windows`，
预期复绿（源等同 + 同二进制当日已过）。该重跑不阻塞 Phase 7 关闭——阻塞项是宿主资源，非待验证代码。

## lavfi seek 语义（实证钉死，供后续阶段复用）

`av://lavfi` 生成源仅支持**前进与近终点** seek（精确落位）；**后退/归零为空操作**（生成器无法回退——源属性，非桥接缺陷）。`MPV_KIT_SEEK_MEDIA=<file>` 可用真实媒体启用双向覆盖（与 Phase 8 拖拽配套）。
