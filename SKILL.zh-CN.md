---
name: openfoam-cluster-ops
description: >-
  OpenFOAM 集群运维手册（SLURM/SCNet 部署·巡检·收割·容量·排障）。当用户要
  在集群上跑 OpenFOAM 算例（sbatch/squeue/sacct/scancel）、部署算例包、
  巡检作业进度、收割完成案数据回传本地、管理集群存储容量、排查慢节点或
  作业失败时触发。触发词：集群、SCNet、SLURM、sbatch、squeue、sacct、
  array 作业、慢节点、收割、prune、容量、配额、回传、重构段末。英文正本见 SKILL.md。
---

# OpenFOAM Cluster Ops — 集群运维手册（中文伴侣件）

> 本文件为中文速览，英文正本（内容一致、以它为准）见 [SKILL.md](SKILL.md)，深读材料 references/ 仅有英文版。

OpenFOAM 仿真算例在 HPC 集群（SLURM 调度）上的**部署、巡检、收割、容量管理与故障排查**。
覆盖从"算例包上传"到"结果回传本地"的完整生命周期。

## 核心速查

| 维度 | 铁律 |
|---|---|
| 部署 | bundle 在**登录节点预解包**（array 并发解包必竞争）；sbatch 内 `if [ ! -d ]` 只做兜底 |
| 物理核 | `mpirun --bind-to core:overload-allowed`（`--hint=compute` 可能不被 SLURM 版本支持） |
| 时限 | 分区上限可能很长但**运行中作业改不了 TimeLimit**（scontrol update 被拒）——设计时给足 `-t` |
| 删除 | **只用固定白名单**，绝不用 `grep End` 动态检测（完成案在收割窗口内可能新增） |
| 阻断 | 脚本失败必须 `exit`（`\|\| tail` 吞错会让后续 rm 继续）——分步执行、确认上一步成功再进下一步 |
| 验证 | 回传验证通过（目标档数到位）才删集群端——**传输与删除永远分步** |
| 节奏 | **End 即割、滚动收割**（存储空间优先）：巡检见 End 立即五步收割、验证过即删，不等批次收官；长案巡检时 `-newTimes` 增量回传作保险 |
| 容量 | 段末 N 档 + 滑动窗 N 档保留（全档必超配额）；每日 prune 一次 |
| 环境 | ssh 内跑 OpenFOAM 命令必须 `source bashrc + module load`（缺环境 = command not found） |
| 变量 | `set -u` 下所有变量先初始化再使用（`VAR=""`） |

## 脚本清单

| 脚本 | 用途 | 用法 |
|---|---|---|
| `scripts/patrol.sh` | 快速巡检（状态/进度/容量） | 配好 `scripts/_env.sh` 后 `bash patrol.sh` |
| `scripts/prune_keepseg.sh` | 容量管理（段末+滑动窗清理） | `_env.sh` 定义段末表后执行 |
| `scripts/auto_cycle.sh` | 自动收割循环（20轮×10min） | 后台运行，日志自动记录 |
| `scripts/sbatch_template.sh` | 作业提交模板（重跑版） | 替换 `<>` 占位符后 sbatch |
| `scripts/sbatch_resume_template.sh` | 续跑模板（保 processor 进度） | 替换占位符后 sbatch |

脚本统一读同目录 `_env.sh`（从 `_env.example` 复制改写，不入仓）：SSH 别名、部署目录、案名清单、段末时刻表、滑动窗宽度等本机与项目差异全部在那里。
