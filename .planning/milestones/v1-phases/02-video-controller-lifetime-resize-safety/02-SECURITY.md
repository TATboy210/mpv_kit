---
phase: 02-video-controller-lifetime-resize-safety
slug: video-controller-lifetime-resize-safety
status: verified
threats_open: 0
asvs_level: 1
created: 2026-10-24
---

# Phase 2 Security Report

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| Dart isolate → native plugin (method channel) | create 响应是不可信数据,其形状决定资源所有权 | create 响应 map、dispose/setSize 调用 |
| native render thread → Dart | native 在 Dart 看到响应前已分配 context + texture;回滚必须跨回 | 事件 (event) 调用 |
| app listener/hook → teardown 路径 | 应用代码在 dispose 期间同步运行,可能重入 | 任意调用 |
| CI artifact producer → coverage job | 覆盖率任务信任 linux 任务构建的 libmpv 构件 | stage/lib + stage/deps |
| CI runner → 覆盖率门禁 | 覆盖率数字决定合并资格 | lcov.info 的 LF/LH 行 |

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-02-01 | Tampering | create 响应解析 | high | mitigate | 显式字段校验先于构造;畸形 shape 抛 `PlatformException(code: render_init)` 并带观察到的类型 | closed |
| T-02-02 | DoS | create 失败的 native 上下文泄漏 | high | mitigate | `_release(textureId)` best-effort 释放 + `_rollback` 移除 `_live` 条目与 hook;无孤儿测试 | closed |
| T-02-03 | Repudiation | 静默后端降级 | medium | mitigate | backend 必须严格为 `vulkan`/`software`;garbage 抛错 | closed |
| T-02-04 | DoS | controller dispose 通道失败 | high | mitigate | try/finally 无条件关闭 `_events`;错误重抛;二次 dispose 保持 no-op | closed |
| T-02-05 | Tampering | dispose 后在途 resize | medium | mitigate | catch 路径内 `_disposed` 复检,只丢弃 dispose 赢得的竞态;活控制器错误重抛 | closed |
| T-02-06 | DoS | 重入 dispose 死锁(Player) | high | mitigate | teardown 完成前的调用共享 future;hook 内 await 共享 future 的死锁模式在文档中明令禁止;Phase 1 固化的 unawaited 重入模式回归测试钉住 | closed |
| T-02-07 | Repudiation | 双调用方结果分歧 | medium | mitigate | 共享 `_disposeFuture`;同一 future、同一错误对象 | closed |
| T-02-08 | DoS | 跨循环记账泄漏 | medium | mitigate | 100-cycle soak 断言零残留 hook、每轮流关闭 | closed |
| T-02-09 | Tampering | awk 门禁解析 | medium | mitigate | 复用 mpv_kit 已验证的 LF/LH 模式;`<verify>` 标记 grep 确认接线 | closed |
| T-02-10 | DoS | 缺失 libmpv 构件 → 测试 skip → 低覆盖 | high | mitigate | 构件缺失时 download-artifact 步骤先于测试失败;`MPV_KIT_LIBMPV_PATH` 指向构件,skip 路径不可达 | closed |
| T-02-11 | Repudiation | 第二次 libmpv 构建漂移 | medium | mitigate | 构件只消费;job 内无构建步骤(diff 审查) | closed |
| T-02-SC | Tampering | Package installs | high | mitigate | 三个计划均无 npm/pip/cargo/pub 安装任务;CI 仅使用仓库已在用的 actions(actions/*、subosito/flutter-action);`dart pub global activate coverage` 与 Phase 1 一致 | closed |

## Accepted Risks Log

| Risk | Rationale | Review |
|------|-----------|--------|
| 无 textureId 的畸形响应无法释放 native 上下文(协议断裂时进程生命周期泄漏) | 无 id 则无释放句柄;新增 wire 调用违反 API 冻结;场景要求插件与 Dart 版本断裂 | Phase 3 复审 |
| hook 内 `await p.dispose()` 会死锁(共享 teardown future) | 重入与并发调用不可区分;死锁模式已文档化;Phase 1 固化的 unawaited 模式安全 | Phase 3 复审 |

## Security Audit Trail

- 威胁建模:三个 PLAN.md 的 `<threat_model>` 段(2026-10-24)。
- 安全相关 diff 审查:`git diff 4bf65d8..HEAD`(5 文件,+518/−76)——无新增外部输入解析、无网络、无文件系统写入、无凭据处理;所有 catch 块均有注释说明吞/抛语义。
- 公共 API 冻结:`api_freeze_test.dart` 通过(2026-10-24)。

## Sign-Off

- Status: verified, 0 open threats. ASVS-1 关卡无 high 级未缓解项。
