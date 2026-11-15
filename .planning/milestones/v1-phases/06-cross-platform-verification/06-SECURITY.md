---
phase: 06-cross-platform-verification
slug: cross-platform-verification
status: verified
threats_open: 0
asvs_level: 1
created: 2026-10-24
---

# Phase 6 Security Report

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| CI runner 环境 → 测试诚实性 | skip/continue-on-error 可能掩盖失败 | 测试结果 |
| verify 构件 → integration job | 被测 libmpv 必须是 verify 层构建的那份 | 构件下载 |
| hook bundle → flutter-plugin 测试 | REQUIRE 模式下错误的库必须响亮失败 | 库路径 |

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-06-01 | Repudiation | 空洞断言(测试永真) | medium | mitigate | RED 证明 + 截止轮询 | closed |
| T-06-02 | DoS | 无 GPU runner 挂起 | low | mitigate | 30s 截止;software 后端按设计满足 | closed |
| T-06-03 | Repudiation | integration job 静默降级 | high | mitigate | 零 continue-on-error(断言);REQUIRE 响亮失败 | closed |
| T-06-04 | DoS | Linux 无显示器 | medium | mitigate | xvfb-run 包裹 | closed |
| T-06-05 | Tampering | 跨 OS 构件/库错配 | low | mitigate | 同一 workflow run 内按名下载(needs) | closed |
| T-06-06 | Repudiation | continue-on-error 掩盖 | high | mitigate | 显式 if-skip + check_matrix 审计(篡改证明) | closed |
| T-06-07 | Tampering | 矩阵静默削减 | medium | mitigate | check_matrix 六目标断言接入首个 CI job | closed |
| T-06-SC | Tampering | Package installs | high | mitigate | 仅仓库既有 distro/brew/flutter-action;无新依赖 | closed |

## Accepted Risks Log

| Risk | Rationale | Review |
|------|-----------|--------|
| Intel-VM MoltenVK abort(环境限制) | GitHub Intel 虚拟机的半虚拟 GPU 使 vkCreateInstance abort;真实 Intel Mac 不受影响;显式 if-skip 可见 | CI 供应商变化时复审 |
| CI 动态运行待 push | 结构性(本地无法跑 GitHub runner);静态断言 + 本地等价命令完备 | 下次 push 核对 |

## Security Audit Trail

- 威胁建模:三个 PLAN.md 的 `<threat_model>` 段(2026-10-24)。
- 安全 diff 审查:`git diff a87e197^..2522d26` —— 测试/CI/守卫;无生产 Dart 面改动、无网络新增、无凭据。
- 公共 API 冻结:api_freeze 通过。

## Sign-Off

- Status: verified, 0 open threats。ASVS-1 无 high 级未缓解安全项。
