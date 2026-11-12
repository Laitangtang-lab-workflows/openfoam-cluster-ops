---
name: openfoam-cluster-ops
description: >-
  Operations handbook for running OpenFOAM on HPC clusters under SLURM (deploy · patrol · harvest · capacity · troubleshooting). Use when running OpenFOAM cases on a cluster (sbatch/squeue/sacct/scancel), deploying case bundles, patrolling job progress, harvesting finished cases back to the local machine, managing cluster storage quota, or troubleshooting slow nodes and failed jobs. Trigger words: cluster, SLURM, sbatch, squeue, sacct, array jobs, slow node, harvest, prune, quota, transfer back, reconstruct segment ends. Chinese companion: SKILL.zh-CN.md.
---

# OpenFOAM Cluster Ops — cluster operations handbook

**Deploying, patrolling, harvesting, capacity management and troubleshooting** OpenFOAM simulation cases on an HPC cluster under SLURM scheduling. Covers the full lifecycle from "case bundle uploaded" to "results transferred back home". Field-tested on the SCNet platform.

## Quick reference

| Dimension | Iron rule |
|---|---|
| Deploy | Pre-extract the bundle **once on the login node** (concurrent array extraction always races); the `if [ ! -d ]` inside sbatch is only a fallback |
| Physical cores | `mpirun --bind-to core:overload-allowed` (`--hint=compute` may not be supported by your SLURM build) |
| Time limit | Partition limits can be long, but **TimeLimit of a running job cannot be changed** (scontrol update is refused) — give `-t` enough headroom at design time |
| Deletion | **Fixed whitelists only**, never dynamic `grep End` detection (new cases can finish inside your harvest window) |
| Blocking | A failed step must `exit` (`\|\| tail` swallows the error and lets a later rm proceed) — run stepwise, confirm each step before the next |
| Verify | Delete on the cluster only after the transferred-back data passes verification (expected time directories present) — **transfer and deletion are always separate steps** |
| Cadence | **Harvest at End, roll continuously** (storage space first): on patrol, harvest finished cases immediately through the five steps and delete once verified, never wait for the batch to finish; for multi-day cases, `-newTimes` incremental transfer during patrol is the insurance |
| Capacity | Keep segment-end N + sliding-window N time dirs (keeping everything will blow the quota); prune once daily |
| Environment | Running OpenFOAM tools over ssh requires `source bashrc + module load` (missing environment = command not found) |
| Variables | Under `set -u`, initialize every variable before use (`VAR=""`) |

## Content map

| File | Content |
|---|---|
| [references/slurm-pitfalls.md](references/slurm-pitfalls.md) | SLURM scheduling pitfalls: unsupported --hint, refused scontrol updates, array extraction races, job re-scheduling, half-occupied CPUs on slow nodes |
| [references/transfer-storage.md](references/transfer-storage.md) | Network and storage: slow transfers (~100KB/s), /tmp cleanup, 100G quota management, rsync resume |
| [references/harvest-workflow.md](references/harvest-workflow.md) | Harvest workflow: reconstruct segment ends → pack → rsync back → local verify → whitelist delete (stepwise safety discipline) |
| [references/diagnosis.md](references/diagnosis.md) | The three-step slow-case diagnosis + a common-failure troubleshooting table |
| [scripts/](scripts/) | Executable ops scripts (patrol / prune / auto_cycle / sbatch templates) |

## Scripts

All scripts read a sibling `_env.sh` (copy from `_env.example` and edit; gitignored) that carries every machine- and project-specific value: the SSH alias, the deploy directory, the case list, the segment-end time table, the sliding-window width.

| Script | Purpose | Usage |
|---|---|---|
| `scripts/patrol.sh` | Quick patrol (queue / progress / capacity) | `bash patrol.sh` after `_env.sh` is set up |
| `scripts/prune_keepseg.sh` | Capacity management (segment-end + sliding-window pruning) | run after `_env.sh` defines the segment table |
| `scripts/auto_cycle.sh` | Automatic harvest loop (20 rounds × 10 min) | run in background, logging is automatic |
| `scripts/sbatch_template.sh` | Job submission template (clean rerun) | replace `<>` placeholders, then sbatch |
| `scripts/sbatch_resume_template.sh` | Resume template (keeps processor progress) | replace placeholders, then sbatch |
