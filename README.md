# openfoam-cluster-ops

**Run OpenFOAM on a SLURM HPC cluster without losing cases or data: deployment, patrol, harvest, quota management and troubleshooting — the full lifecycle from bundle upload to results back home.**

> [!NOTE]
> This repository is **written and maintained entirely by AI agents** under human direction — see [AI-maintained](#ai-maintained).
> Documentation is English-first; a Chinese README is available ([README.zh-CN.md](README.zh-CN.md)), and a Chinese SKILL companion ([SKILL.zh-CN.md](SKILL.zh-CN.md)).

## Why

HPC clusters punish improvisation: array jobs race each other unpacking bundles, running jobs cannot get their time limit extended, quota fills up mid-batch, scp silently delivers 0-byte files, and one careless `rm` erases the only true mesh. This handbook is the codified scar tissue of real incidents — every iron rule traces to a confirmed failure — plus five operational scripts that carry the discipline for you:

- **Deployment** — pre-extract bundles on the login node; sbatch templates for clean rerun *and* true resume (progress-preserving).
- **Patrol** — one read-only command for queue, per-case progress and capacity.
- **Harvest** — a strict five-step pipeline (detect End → reconstruct segment ends → pack with `constant/` → rsync back → verify) where transfer and deletion are always separate steps and deletion only ever runs against a fixed whitelist.
- **Capacity** — segment-end + sliding-window pruning so N cases fit a finite quota without losing anything scientifically needed.
- **Diagnosis** — the three-step slow-case diagnosis (same-family comparison → CPU occupancy → iteration health) and a troubleshooting table covering ABI mismatches, PETSc link errors, scotch-vs-geometric decomposition and more.

## The skill format

The core of this repository is a **`SKILL.md` agent skill** (the convention used by Claude Code, DeepSeek Harness and other agent harnesses). Drop the repo into your harness's skill directory and an AI session picks up the whole methodology with it:

```
git clone https://github.com/Laitangtang-lab-workflows/openfoam-cluster-ops ~/.agents/skills/openfoam-cluster-ops
```

You can equally read `SKILL.md` and `references/` as plain documentation, or run the scripts directly — no harness required.

## Scripts and configuration

All scripts read a sibling `_env.sh` (copy from `scripts/_env.example`; gitignored) holding every machine- and project-specific value — the SSH alias, the deploy directory, the case list, the segment-end time table, the sliding-window width. The repo itself carries zero machine paths.

```bash
cd scripts && cp _env.example _env.sh   # then edit for your cluster and project
bash patrol.sh                          # read-only: queue / progress / capacity
```

| Script | Purpose |
|---|---|
| `patrol.sh` | Quick patrol (queue / per-case progress / capacity) |
| `prune_keepseg.sh` | Capacity management (segment-end + sliding-window pruning) |
| `auto_cycle.sh` | Automatic harvest loop (20 rounds × 10 min, whitelist-deletes only after local verification) |
| `sbatch_template.sh` | Job submission template — clean rerun |
| `sbatch_resume_template.sh` | Job submission template — resume (keeps processor progress) |

The two sbatch templates contain `<placeholders>` and are meant to be copied and filled in — they will not run as-is.

## Repository layout

| Path | Content |
|---|---|
| `SKILL.md` | Skill entry point, iron-rule quick reference |
| `references/` | The handbook: SLURM pitfalls, network & storage, harvest workflow, slow-case diagnosis |
| `scripts/` | Five operational scripts + `_env.example` |

## AI-maintained

Every file in this repository — code, documentation, this README — is written and updated by AI agents under human supervision. The iron rules were distilled from real incidents on live research batches where AI sessions were the primary operators. Expect commits to be machine-authored; humans review direction and decisions, not lines.

## License

[CC0-1.0](LICENSE) — released to the public domain. Use, fork and vendor it into anything, no attribution required (a nod is always appreciated).

By submitting a pull request you agree that your contributions are dedicated under CC0 as well.
