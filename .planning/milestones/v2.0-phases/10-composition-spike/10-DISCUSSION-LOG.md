# Phase 10: Composition Spike - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-24
**Phase:** 10-Composition Spike
**Areas discussed:** REA 取证深度, Impeller 冒烟范围, 引擎版本, 「可行」的判定门槛

---

## REA 取证深度

| Option | Description | Selected |
|--------|-------------|----------|
| 符号级 + 调用链 | 定位两种表面类型的绑定函数、fence/设备使用点与 DXGI 设备归属，给出地址、符号与关键反汇编片段 | |
| 逐路径反编译到伪代码 | 对纹理消费路径给完整伪代码，逐点标注 allocation/fence/设备；本机 DLL 可能缺符号 | ✓ |
| 以动态观测为主 | 挂载运行中的引擎观察真实 DXGI 设备与调用序列，静态只作旁证 | |

**User's choice:** 逐路径反编译到伪代码
**Notes:** 目标是让 Phase 11 可以直接照着实现，而不是只知道结论。

---

## Impeller 冒烟范围

| Option | Description | Selected |
|--------|-------------|----------|
| 最小链路 + 一帧 4K | create → 渲一帧 → dispose，外加一次 4K 帧；忠实于 ROADMAP 成功标准 | ✓ |
| 加 resize/dispose 交错与 30 秒连续 | 再加 ≥100 轮 resize/dispose 与 30 秒连续播放 | |
| 全量：再加长时间与回退矩阵 | 再加 N 分钟稳定性与回退矩阵一致性 | |

**User's choice:** 最小链路 + 一帧 4K
**Notes:** 与「判定门槛」一题的选择合并后，冒烟实际包含三段；排除 N 分钟稳定性与完整回退矩阵。

---

## 引擎版本

| Option | Description | Selected |
|--------|-------------|----------|
| 只测锁定的 3.47.6 | 与 CI 的 FLUTTER_VERSION 一致，结论对应当前可发布状态 | ✓ |
| 3.47.6 + 一个含修复的新版 | 额外试含 PR #191017 的版本作对照，需另搭版本切换环境 | |

**User's choice:** 只测锁定的 3.47.6
**Notes:** 若失败，报告需记录升级所需版本与前置条件，但不代为验证。

---

## 「可行」的判定门槛

| Option | Description | Selected |
|--------|-------------|----------|
| 单帧成功即可行 | 渲出一帧即判可行，稳定性留给 Phase 11 | |
| 30 秒 + 100 轮 resize 不崩 | 必须证明共享句柄在反复 acquire/release 下不崩 | ✓ |
| 再加延迟实测与预算参数化 | 还要求实测 compositor 延迟并参数化 quarantine 预算 | |
| 不裁决可行性 | 只记录崩/不崩，判断留给 Phase 11 | |

**User's choice:** 30 秒 + 100 轮 resize 不崩
**Notes:** 该门槛是 costly 可逆：一旦按「可行」批准，Phase 11 的范围与排期随之锁定。

---

## Claude's Discretion

- **回退契约与 quarantine 预算** — 用户未选择讨论此方向。两项目前归属 Phase 11（该阶段成功标准已要求路径上报与延迟参数化），Phase 10 不锁定。

## Deferred Ideas

None — 讨论未越出阶段边界。
