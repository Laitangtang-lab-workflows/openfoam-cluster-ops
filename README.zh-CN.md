# openfoam-cluster-ops

**在 SLURM 集群上跑 OpenFOAM 而不丢案不丢数据：部署、巡检、收割、配额管理与排障，覆盖从算例包上传到结果回传本地的完整生命周期。**

> [!NOTE]
> 本仓**全部内容由 AI 维护**，人类定方向、做决策，详见 [AI 维护声明](#ai-维护声明)。英文说明见 [README.md](README.md)。

## 解决什么问题

HPC 集群惩罚即兴操作：array 作业并发解包互相踩、运行中的作业改不了时限、配额在批次中途爆掉、scp 静默传空文件、一次随手 `rm` 就抹掉唯一的真网格。本手册是真实事故结出来的制度——**每条铁律都能追溯到一次实锤**——配五个运维脚本替你执行纪律：

- **部署**——bundle 登录节点预解包；sbatch 模板分干净重跑与真续跑（保进度）两版
- **巡检**——一条只读命令看队列、逐案进度、容量
- **收割**——严格五步管线（检测 End → 重构段末 → 含 `constant/` 打包 → rsync 回传 → 验证），传输与删除永远分步，删除只认固定白名单
- **容量**——段末加滑动窗清理，N 案塞进有限配额而不丢科学上需要的档
- **诊断**——慢案三板斧（同族对照 → CPU 占用 → 迭代健康）加一张覆盖 ABI 错位、PETSc 链接、scotch 分解等问题的排障表

## skill 形态与安装

本仓核心是一个 **`SKILL.md` 格式的 agent skill**（Claude Code、DeepSeek Harness 等框架通用）。clone 进技能目录，AI 会话即可带着整套纪律工作：

```
git clone https://github.com/Laitangtang-lab-workflows/openfoam-cluster-ops ~/.agents/skills/openfoam-cluster-ops
```

也可以把 `SKILL.md` 与 `references/` 当普通文档读，或直接跑脚本，不需要任何框架。

## 脚本与配置

所有脚本读同目录 `_env.sh`（从 `scripts/_env.example` 复制改写，不入仓），本机与项目差异全在那里——SSH 别名、部署目录、案名清单、段末时刻表、滑动窗宽度。仓本身零机器路径。

```bash
cd scripts && cp _env.example _env.sh   # 按你的集群与项目改写
bash patrol.sh                          # 只读巡检：队列 / 进度 / 容量
```

| 脚本 | 用途 |
|---|---|
| `patrol.sh` | 快速巡检（队列 / 逐案进度 / 容量） |
| `prune_keepseg.sh` | 容量管理（段末 + 滑动窗清理） |
| `auto_cycle.sh` | 自动收割循环（20 轮 × 10 分钟，本地验证通过才白名单删除） |
| `sbatch_template.sh` | 作业提交模板（干净重跑） |
| `sbatch_resume_template.sh` | 作业提交模板（续跑，保 processor 进度） |

两个 sbatch 模板含 `<占位符>`，属复制后填写的模板，不能直接运行。

## 仓库结构

| 路径 | 内容 |
|---|---|
| `SKILL.md` | skill 入口与铁律速查 |
| `references/` | 手册本体：SLURM 坑、网络与存储、收割流程、慢案诊断 |
| `scripts/` | 五个运维脚本加 `_env.example` |

## AI 维护声明

本仓全部内容（代码、文档、本 README）由 AI 会话在人类监督下编写与更新。铁律提炼自 AI 作为主操作者的真实研究批次事故。提交均由机器生成，人类把关方向与决策，不逐行审码。

## 证书

[CC0-1.0](LICENSE)——公有领域贡献。可任意使用、fork、并入任何项目，无须署名（注明出处是善意但非义务）。

提交 PR 即表示同意你的贡献同样以 CC0 贡献。
