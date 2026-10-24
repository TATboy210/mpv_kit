---
phase: 04-measured-performance-uhd-endurance
slug: measured-performance-uhd-endurance
status: verified
threats_open: 0
asvs_level: 1
created: 2026-10-24
---

# Phase 4 Security Report

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| benchmark → production code | 04-01/04-03 为测量计划,任何生产改动都会使基线失效 | 无 |
| native payload → decode | 节点形状不可信;单次解码必须保持 format-none 语义 | mpv_node |
| wall clock → throttle | DateTime 可被调整;节流须单调 | 微秒整数 |
| GPU/driver → endurance run | 8K 压力下驱动/内存子系统可能失败 | 进程存活性 |

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-04-01 | Repudiation | 基线晚于优化 | high | mitigate | 严格计划顺序;基线提交先于优化提交(eebf406 < 2785bd5) | closed |
| T-04-02 | DoS | idle 路径污染数据 | medium | mitigate | 可见性要求文档化;fps/掉帽数据异常即显形 | closed |
| T-04-03 | Tampering | 解码语义回归 | high | mitigate | 计数器测试 + format-none 覆盖保持 + 类不变 | closed |
| T-04-04 | Repudiation | 无数据的优化声明 | medium | mitigate | after-record 对照已提交基线 | closed |
| T-04-05 | Repudiation | 放松门禁强过 8K | high | mitigate | 门禁固定在代码中;失败记录为数据 | closed |
| T-04-06 | DoS | 8K 最小化挂起 | medium | mitigate | 可见性要求 + deviceLost/renderError 风暴检测 | closed |
| T-04-07 | Tampering | testsrc2 生成率混淆 fps | medium | mitigate | estimated-vf-fps 记录;积压门禁不依赖 fps | closed |
| T-04-08 | DoS | 8K 提交内存耗尽(新发现) | high | recorded | 进程死亡 = 数据;修复归 8K stability insertion(队列按帧尺寸缩放、优雅压力事件) | recorded |
| T-04-SC | Tampering | Package installs | high | mitigate | 无安装任务;integration_test 为 SDK 依赖 | closed |

## Accepted Risks Log

| Risk | Rationale | Review |
|------|-----------|--------|
| 8K 提交内存耗尽进程死亡(本阶段发现) | 属产品稳定性缺陷;测量阶段不修;候选修复已记录;4K 不受影响 | 8K stability insertion |
| 50-cycle Vulkan RSS 45.1 MiB 逼近门禁 | 门禁内;纯 Dart soak 无法覆盖 Vulkan 上下文;数字已入基线 | Phase 5+ 观察 |

## Security Audit Trail

- 威胁建模:三个 PLAN.md 的 `<threat_model>` 段(2026-10-24)。
- 安全 diff 审查:`git diff e4407ab..353533f`(13 文件)——生产改动仅 events.dart/player.dart 内部;无外部输入解析新增、无网络、无凭据。
- 公共 API 冻结:api_freeze 通过(propDecodesForTesting 为 ForTesting 自动豁免)。

## Sign-Off

- Status: verified, 0 open threats(8K 崩溃记录为 stability finding,非安全威胁)。ASVS-1 无 high 级未缓解安全项。
