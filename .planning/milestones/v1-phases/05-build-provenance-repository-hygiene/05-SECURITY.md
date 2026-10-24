---
phase: 05-build-provenance-repository-hygiene
slug: build-provenance-repository-hygiene
status: verified
threats_open: 0
asvs_level: 1
created: 2026-10-24
---

# Phase 5 Security Report

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| upstream mpv repo → vendor tree | vendor 树声称的来源必须可证明 | 补丁应用结果 |
| patch files → CI build tiers | 过时补丁 = 构建的是谎言 | vendor 树 |
| published release → bundles.dart pins | 过期 pin 下载旧行为的 bundle | SHA256SUMS |
| release artifacts → consumers | SHA256SUMS/MANIFEST 是消费方的信任锚 | tar.gz 内容 |
| docs → truth sources | 版本声明静默漂移 | 版本串/部署目标/SDK 约束 |

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-05-01 | Repudiation | vendor/补丁漂移 | high | mitigate | 字节级 diff 门禁;篡改测试证明 | closed |
| T-05-02 | DoS | CI 中 upstream 不可达 | low | accepted | 失败即响亮报错(github.com 是检查自身的硬依赖) | closed |
| T-05-03 | DoS | 依赖 bt/ 的消费方 | low | mitigate | README 替代工作流;本地副本保留 | closed |
| T-05-04 | Tampering | lock 政策反复 | medium | mitigate | 政策 + 理由文档化于 README | closed |
| T-05-05 | Repudiation | 文档/版本漂移 | medium | mitigate | 机械检查器(8 不变量,精确锚定) | closed |
| T-05-06 | Repudiation | 发布后 pin 过期 | high | mitigate | --check CI step 对照 live SHA256SUMS | closed |
| T-05-07 | Tampering | 发布物不一致 | high | mitigate | publish 自洽校验先于 gh release create | closed |
| T-05-08 | Tampering | 检查器误报掩盖 | medium | mitigate | 篡改测试证明检测能力(sdk 编辑 → exit 1) | closed |
| T-05-09 | Tampering | CRLF 混入 diff(autocrlf 泄漏) | medium | mitigate | clone + 新仓库双点固定 autocrlf=false | closed |
| T-05-SC | Tampering | Package installs | high | mitigate | 无安装任务;fetch 均为项目自身 release 资产 | closed |

## Accepted Risks Log

| Risk | Rationale | Review |
|------|-----------|--------|
| 8K 崩溃(Phase 4 发现)持续存在 | 用户确认无 8K 测试条件;记录保留 | 8K 支持时重启 |
| patch-drift 依赖 github.com 可达 | 检查本身即上游验证;失败响亮 | Phase 6 观察 |

## Security Audit Trail

- 威胁建模:三个 PLAN.md 的 `<threat_model>` 段(2026-10-24)。
- 安全 diff 审查:`git diff 2d4e2c9..HEAD`(脚本/CI/git/文档)——无生产 Dart 行为改动、无网络服务新增(check_patches 的上游 clone 是只读 provenance 验证)、无凭据。
- 公共 API 冻结:api_freeze 通过(无 Dart 生产面改动)。

## Sign-Off

- Status: verified, 0 open threats。ASVS-1 无 high 级未缓解安全项。
