---
phase: 05-build-provenance-repository-hygiene
verified: 2026-10-24T19:00:00Z
status: passed
score: 12/12 must-haves verified
covered_files:
  - .planning/phases/05-build-provenance-repository-hygiene/05-01-PLAN.md
  - .planning/phases/05-build-provenance-repository-hygiene/05-01-SUMMARY.md
  - .planning/phases/05-build-provenance-repository-hygiene/05-02-PLAN.md
  - .planning/phases/05-build-provenance-repository-hygiene/05-02-SUMMARY.md
  - .planning/phases/05-build-provenance-repository-hygiene/05-03-PLAN.md
  - .planning/phases/05-build-provenance-repository-hygiene/05-03-SUMMARY.md
  - tools/check_patches.sh
  - tools/check_consistency.dart
  - tools/pin_bundles.dart
  - .github/workflows/native-verify.yml
  - .github/workflows/release.yml
  - native/patches/UPSTREAM.md
  - native/patches/0004-libmpv-gpu-next-render-backend-and-renderer-report.patch
  - native/patches/0008-vendor-integration-fixes.patch
  - .gitignore
  - pubspec.lock
  - README.md
behavior_unverified: 1
overrides_applied: 0
re_verification:
  previous_status: none
  previous_score: null
  gaps_closed: []
  gaps_remaining: []
  regressions: []
deferred:
  - truth: "release.yml publish 自洽校验的动态证明"
    addressed_in: "Next tag push (the publish job only runs on tags)"
    evidence: "Inline bash statically verified (sha256sum/tar semantics straightforward); the local PATCH-DRIFT/PINS/CONSISTENCY gates all ran for real"
advisory:
  - finding: "native/mpv/.code-review-graph 工具垃圾目录已在本地删除;若其他克隆存在同名目录需同样清理(check_patches 不再排除它,会直接报差异)"
    category: hygiene
    reason: "本地性;git 未跟踪"
    evidence_status: local_only
---

# Phase 5: Build Provenance & Repository Hygiene Verification Report

## 结论摘要

Phase 5 的四条 ROADMAP criteria 全部达成:补丁漂移 CI 门禁(经重生成补丁集后字节级成立)、仓库卫生(bt/ 出库 + lock 政策)、一致性检查器(全部漂移修复)、发布自证 + pin 新鲜度。全部门禁本地实跑通过;CI 作业的动态验证留待 push(逻辑本体已本地证明)。

## Goal Achievement

### Observable Truths

| # | Truth | Evidence | Status |
|---|-------|----------|--------|
| 1 | base+patches == native/mpv 字节级成立 | `bash tools/check_patches.sh` → PATCH-DRIFT OK base=fd9265a905 patches=7 | ✓ |
| 2 | 篡改检测:单行 vendor 改动 → exit 1;恢复 → OK | 篡改测试(MPV_VERSION) | ✓ |
| 3 | patch-drift 是 native-verify 的首个 job | grep + YAML 解析 | ✓ |
| 4 | bt/ 不再被跟踪且被忽略;本地副本保留 | git ls-files bt/ = 0;test -d bt | ✓ |
| 5 | pubspec.lock 已入库,.gitignore 排除已移除,政策文档化 | git ls-files pubspec.lock = 1;README "Dependency locking" | ✓ |
| 6 | 离线 pub get 用已提交锁正常解析 | dart pub get --offline OK | ✓ |
| 7 | 文档无残留 bt/ 可执行命令引用 | grep -rn "D:/mpv_kit/bt" docs/ README.md = 0 | ✓ |
| 8 | 一致性检查器全绿(8 不变量) | dart run tools/check_consistency.dart | ✓ |
| 9 | 篡改检测(sdk 约束改动 → exit 1,2 FAIL) | 篡改测试 | ✓ |
| 10 | 漂移修复:podspec 12.0、sdk ^3.10.0 ×5、README 精确版本、ADR-0002 重写、rev-eng 日期 | checker 不变量 + git diff | ✓ |
| 11 | pin 新鲜度:PINS OK tag=v0.1.0-dev.3 targets=6,已接入 native-verify | dart run tools/pin_bundles.dart --check | ✓ |
| 12 | release.yml publish 自洽校验(SHA256SUMS ↔ tar ↔ MANIFEST) | 静态审查(动态证明待下次 tag) | ✓(静态) |

### Roadmap Success Criteria

1. **CI 干净树应用补丁,不一致即失败** — ✓(truths 1-3;补丁集重生成使字节级成立)。
2. **六目标 bundle 可复现重建 + sha256/MANIFEST 校验** — ✓(truth 11 + release 自洽校验;hook 的逐文件 MANIFEST 校验自 Phase 2 起已存在)。注:跨机器字节级 bit-reproducibility 不在承诺内(编译器非确定性),承诺的是"当前树经 build.sh+package.sh 产出的 bundle 通过 sha256/MANIFEST 校验"。
3. **文档/版本一致 + 检查** — ✓(truths 8-10)。
4. **bt/ 出库 + lock 政策** — ✓(truths 4-7)。

### Requirements Coverage

- BUILD-01: Complete(05-01)
- BUILD-02: Complete(05-03 增补;hook 逐文件校验既有)
- BUILD-03: Complete(05-03)
- BUILD-04: Complete(05-02)

### Prohibitions (must-NOT)

- BUILD-01「MUST NOT silently exclude vendor differences」— 排除仅 .git/.gitignore;wayland/io.c 差异进 0008 显式记录。✓
- BUILD-03「MUST NOT widen version claims」— 文档向真值源对齐。✓
- BUILD-04「MUST NOT delete working-tree bt/」— test -d bt 通过。✓

## Key Link Verification

- `MPV_VERSION → clone → patch -p1 ×7 → diff vs native/mpv → CI gate` — truths 1-2。✓
- `pin_bundles --check → live SHA256SUMS → bundles.dart` — truth 11。✓
- `release publish → SHA256SUMS + MANIFEST → gh release create` — truth 12(静态)。✓
- `check_consistency → MPV_VERSION/podspec/pubspecs/README/ffmpeg.sh` — truths 8-10。✓

## Behavioral Spot-Checks

- mpv_kit 112 passed / 2 skipped(开发过程中一次 6-fail 是 Git Bash PATH 形式问题,非回归——POSIX 形式即恢复,已写入 README)。
- 仓库文件数 1264 → 1248(bt/ 22 DLL 出库,patch 0005 删除,0008/工具/lock 增加)。
- api_freeze 通过;双包 analyzer 零输出。

## Anti-Patterns Found

- 无新增 stub;两个脚本均为可执行验证器而非文档性检查。

## Human Verification Required

1. release.yml publish 自洽校验的动态运行(下次 tag push)。
2. patch-drift 与 pin-check 在 CI runner 上的首次运行(push 触发)。

## Gaps Summary

- 无阻塞缺口。1 条 deferred(publish 动态证明,结构性留待 tag)+ 1 条 advisory(其他克隆的 .code-review-graph 清理)。
