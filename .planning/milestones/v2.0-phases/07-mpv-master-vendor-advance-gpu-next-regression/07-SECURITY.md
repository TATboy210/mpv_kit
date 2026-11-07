---
phase: 07-mpv-master-vendor-advance-gpu-next-regression
slug: mpv-master-vendor-advance-gpu-next-regression
status: verified
threats_open: 0
asvs_level: 1
created: 2026-10-24
---

# Phase 7 Security Report

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| 无元数据快照 → vendor 树 | zip 来源必须以 blob 证据精确归因 | 树内容 |
| 手工移植 → 补丁集 | 重放后的补丁必须编码全部 delta | 补丁文件 |
| 回归二进制 → 被测源 | 测试目标必须是新源的构建 | libmpv 二进制 |

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-07-01 | Repudiation | 错误基线归因 | high | mitigate | 多文件 blob 归因 + 全树 diff=0 验证 | closed |
| T-07-02 | Tampering | 垃圾/排除混入 vendor | medium | mitigate | .code-review-graph 显式排除;门禁禁其他排除 | closed |
| T-07-03 | Repudiation | 移植丢 hunk | high | mitigate | 与旧 vendor 全树 diff=0 其他差异(机械证明) | closed |
| T-07-04 | Repudiation | 过期二进制测错源 | high | mitigate | 字节等同论证(0 其他 diff)+ CI push 真建;记录在案 | closed |
| T-07-05 | DoS | 长播窗口失效 | medium | accepted | 磁盘满导致的环境阻塞按证据记录;解除条件明确 | closed |
| T-07-SC | Tampering | Package installs | high | mitigate | 无安装;上游 clone 只读 | closed |

## Accepted Risks Log

| Risk | Rationale | Review |
|------|-----------|--------|
| 4K 复验待磁盘释放 | 环境项;同二进制当日证据 + 等同性论证 | 用户释放后重跑 |
| CI 动态首跑待 push | 结构就绪;本地门禁全绿 | push 后核对 |

## Security Audit Trail

- 威胁建模:两个 PLAN.md 的 `<threat_model>` 段。
- diff 审查:`git diff 19642cf..d193173`——vendor 树、补丁、UPSTREAM/README/docs、测试、记录;无生产 Dart 改动。
- api_freeze 通过。

## Sign-Off

- Status: verified, 0 open threats。ASVS-1 无 high 级未缓解安全项。
