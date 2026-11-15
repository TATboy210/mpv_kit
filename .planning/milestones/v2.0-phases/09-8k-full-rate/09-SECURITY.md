---
phase: 09-8k-full-rate
slug: 8k-full-rate
status: verified
threats_open: 0
asvs_level: 1
created: 2026-10-25
---

# Phase 9 Security Report

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| 用户选项 → auto-tune | 显式 setProperty 的队列值必须永不被覆盖 | 属性值 |
| videoParams → budget → setProperty | 调参失败不得抛入事件流 | 整型字节数 |

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-09-01 | Tampering | auto-tune 覆盖用户设置 | medium | mitigate | 所有权检查：当前值 ≠ pack 默认 且 ≠ 上次自设值 → 永久停用；集成测试证明 777MiB 覆盖后换源保持 | closed |
| T-09-02 | DoS | 调参异常抛入事件流 | low | mitigate | try 语义吞错（best-effort），失败仅跳过本次调参 | closed |
| T-09-03 | DoS | 预算饿死读前（卡顿） | medium | mitigate | 64 帧预算在 1080p ≈199MiB 仍覆盖 1s@60fps；三档实测 0 丢帧/0 delayed | closed |
| T-09-SC | Tampering | Package installs | high | mitigate | 本阶段零新依赖（git range 仅 player.dart + 测试 + 文档） | closed |

## Accepted Risks Log

| Risk | Rationale | Review |
|------|-----------|--------|
| 巨帧条款下 8K 前向预算 256MiB（约 5 帧）低于 64 帧名义预算 | 巨帧下总提交受限优先于读前深度；lavfi 实测 0 丢帧 | Phase 11 复审（真实 8K 片源） |

## Security Audit Trail

- 威胁建模：09-01-PLAN `<threat_model>`（T-09-01/02/03 全部 mitigate）。
- diff 审查：`e9baee6` 仅 packages/mpv_kit（player.dart + 两个测试）；无网络、无凭据、无文件系统写入、无新依赖。
- 输入面：公式输入为 mpv 上报的 video-params 宽高（不可信值 → 纯整数运算，≤0/异常维度返回 null，无溢出面：int 范围内 w·h·1.5 最大 ~2^54 远离 Dart int 溢出）。

## Sign-Off

- Status: verified, 0 open threats。ASVS-1 无 high 级未缓解安全项。
