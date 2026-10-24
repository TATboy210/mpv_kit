---
phase: 03-error-surfacing
slug: error-surfacing
status: verified
threats_open: 0
asvs_level: 1
created: 2026-10-24
---

# Phase 3 Security Report

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| app stream source → bridge | 用户源码在 mpv 请求处理内运行,其异常决定播放命运 | 异常对象、错误码 |
| native event payload → drain | 事件负载是不可信形状 | mpv_node、事件 id |
| filesystem/env → library loader | MPV_KIT_LIBMPV_PATH 可能指向不可加载库 | 候选路径、失败原因 |
| app options map → mpv | 选项名/值不可信;未知名容忍,非法值拒绝 | 选项名、错误 |
| diagnostic seams → apps/tests | 新增静态/字段不得成为可变配置面 | 只读诊断值 |

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-03-01 | Tampering | 流源异常改写播放语义 | high | mitigate | 上报旁路,mpv 错误码逐字节不变 | closed |
| T-03-02 | DoS | 上报回调自身抛错 | medium | mitigate | `_report` 内 try/catch | closed |
| T-03-03 | Repudiation | seek 失败静默 | medium | mitigate | 带 operation 上下文上抛;不终止播放语义文档化 | closed |
| T-03-04 | DoS | teardown 期上报 | low | mitigate | isClosed 守卫;shutdown 分支包含保持 | closed |
| T-03-05 | DoS | 事件排空中断 | high | mitigate | 逐事件 containment;排空存活测试 | closed |
| T-03-06 | Tampering | 解析器异常伪造状态 | medium | mitigate | `_bind` 捕获,保持旧值 | closed |
| T-03-07 | DoS | 被弃 reply 未处理错误 | medium | mitigate | 5 个错误路径全部 `future.ignore()` | closed |
| T-03-08 | Repudiation | IN-02 语义漂移 | low | mitigate | 文档化重定基线;表更新;专项测试 | closed |
| T-03-09 | Repudiation | 误导性回退原因 | medium | mitigate | interopReason() 诚实文案(HRESULT) | closed |
| T-03-10 | DoS | CreateImage 空引用 | medium | mitigate | 入口守卫 | closed |
| T-03-11 | Repudiation | 选项吞没掩盖拼写错误 | medium | mitigate | ignoredOptionsForTesting + developer.log | closed |
| T-03-12 | Repudiation | 库回落静默(错 DLL) | high | mitigate | resolvedPath/lastOpenAttempts + 警告 | closed |
| T-03-13 | DoS | 精简构建 shader-cache 炸 create | low | mitigate | propertyNotFound 容忍 + 记录 | closed |
| T-03-SC | Tampering | Package installs | high | mitigate | 无安装任务;无新依赖;`dart:developer` 为 SDK | closed |

## Accepted Risks Log

| Risk | Rationale | Review |
|------|-----------|--------|
| 精简/畸形 native 载荷下,挂起的 command reply 永不完成(仅 developer.log) | Dart 侧不可达的极端断裂;挂起不劣于崩溃;补齐需 per-request 超时(新行为) | Phase 4 复审 |
| 用户监听器抛错仍进 zone(Dart 同步控制器标准语义) | mpv_kit 不吞用户代码;Player 自身监听器已全containment | Phase 4 复审 |

## Security Audit Trail

- 威胁建模:四个 PLAN.md 的 `<threat_model>` 段(2026-10-24)。
- 安全 diff 审查:`git diff 06e5718..6c621ea`(13 文件)——无新增外部输入解析面、无网络、无文件写入、无凭据;诊断静态为只读;`future.ignore()` 不吞调用方可见性。
- 公共 API 冻结:api_freeze 通过(3 个文档化接缝)。

## Sign-Off

- Status: verified, 0 open threats. ASVS-1 无 high 级未缓解项。
