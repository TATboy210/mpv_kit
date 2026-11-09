---
phase: 08-debug-hud-drag-and-drop
slug: debug-hud-drag-and-drop
status: verified
threats_open: 0
asvs_level: 1
created: 2026-10-25
---

# Phase 8 Security Report

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| 拖放路径 → player.open | 任意文件系统路径;仅视频扩展名/URL 放行 | 文件路径 |
| HUD 轮询 → mpv | tryGetProperty 频率 1s 有界 | 属性读取 |

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-08-01 | Tampering | 非视频拖放打开任意文件 | medium | mitigate | isVideoPlayable 白名单(扩展名+协议);测试矩阵覆盖 | closed |
| T-08-02 | DoS | HUD 轮询触热路径 | low | mitigate | 1s Timer;capture 只读 .value/tryGetProperty | closed |
| T-08-03 | Tampering | notice 注入持久误导 | low | mitigate | 3s 自动清除;仅本地显示 | closed |
| T-08-SC | Tampering | Package installs | high | mitigate | desktop_drop ^0.7.1 caret 钉定;pub.dev 发布;workspace lock 提交 | closed |

## Accepted Risks Log

| Risk | Rationale | Review |
|------|-----------|--------|
| av://http(s):// 直通(任意 URL 可开) | mpv 自身处理协议/网络;与路径输入框同等能力 | Phase 11 复审 |

## Security Audit Trail

- 威胁建模:08-01-PLAN `<threat_model>`。
- diff 审查:git range 仅 example/* + lock;无生产包改动、无网络新增(desktop_drop 为拖放事件读取)、无凭据。
- 供应链:desktop_drop 0.7.1(pub.dev,2026-04 发布,活跃维护——研究阶段结论)。

## Sign-Off

- Status: verified, 0 open threats。ASVS-1 无 high 级未缓解安全项。
