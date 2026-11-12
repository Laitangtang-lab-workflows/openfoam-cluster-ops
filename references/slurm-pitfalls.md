# SLURM scheduling pitfalls (6 confirmed + 1 resubmission defense; battle-tested 2026-10 batches)

## 1. --hint=compute not supported

**Symptom**: `sbatch: error: unrecognized --hint argument "compute"` (older SLURM or a build with it stripped).

**Fix**: physical-core pinning is carried by `mpirun --bind-to core:overload-allowed` + `OMP_NUM_THREADS=1`. `overload-allowed` still pins to physical cores on healthy nodes and relaxes on crowded ones.

## 2. scontrol update refused for running jobs

**Symptom**: `scontrol update JobID=xxx TimeLimit=200:00:00` → `Access/permission denied`.

**Fix**: the time limit of a running job cannot be changed. Give `-t` enough headroom at design time (check the partition limit: `sinfo -p <partition> -o %l`). After a timeout kill and resubmission — **a true resume skips decomposePar** (if processor0 exists, don't decompose; `startFrom latestTime` resumes from the newest processor time and progress is preserved); `decomposePar -force` wipes and re-decomposes, and **with no intermediate time dir at the case root that means a restart from 0 and lost progress** (not a resume!). The default for resubmission is the resume variant (`scripts/sbatch_resume_template.sh`, conditional decompose skip).

## 3. Array-job concurrent extraction races

**Symptom**: 27 array tasks start simultaneously, each running `tar xzf bundle.tar.gz` → partial write conflicts (`Cannot open: File exists` / `Cannot write: No such file`) → tasks FAILED.

**Fix**: **pre-extract once on the login node** (`ssh <cluster> "tar xzf ... -C dir/"`); the `if [ ! -d _shared ]; then tar xzf; fi` inside sbatch is only a fallback.

## 4. Job re-scheduling (log overwrite)

**Symptom**: SLURM may re-schedule a job wholesale (node failure / load balancing). The sbatch script re-executes from the top on restart.

**Notes**: ① `log.run` written with `>` gets overwritten (the resume script switches to `>>` append); ② whether field data survives depends on the decompose handling — the `-force` variant wipes processors and restarts from 0 (data lost), the resume variant (conditional skip) continues from the newest processor time (data kept); ③ estimate rates with `sacct -j <jobid> -o Elapsed` (total runtime), not log-header timestamps.

## 5. Slow nodes (half-occupied CPUs)

**Symptom**: one case advances 1% in 20 h while same-family, same-length cases reach 50%+.

**Diagnosis**: the `ExecutionTime / ClockTime` ratio at the log tail — **below 90% means the node is being squeezed by neighbors** (healthy ≈ 99%).

**Action**: `scancel` → `sbatch --array=<id> --exclude=<slow-node> sbatch_resume_template.sh`. Resubmission does not guarantee a different node — **--exclude is mandatory**. Keep a record of offender nodes (e.g. g03r3n07, g11r3n16, g16r1n06, h07r2n13, f12r2n00, b01r4n16).

## 6. grep -P unavailable

**Symptom**: the cluster grep lacks Perl regex (`grep -P` errors out).

**Fix**: use `grep -E` (extended regex) or `sed -n 's/pattern/\1/p'` (capture groups) instead.

## 7. Pre-resubmission defense

**Iron rule**: before any resubmission (TIMEOUT resume / incomplete-timestep rerun / slow-node migration), **always inspect processor0 first**:

```bash
ls <case>/processor0/ | grep -E '^[0-9]' | sort -g | tail -1
```

- Intermediate times (> 0) present → **resume script** (skip decompose, `>>` log.run, keep progress);
- Only `0` → clean rerun script (-force, from scratch);
- **Unsure → stop and ask the user.**

**Broadened definition of destructive operations**: anything that overwrites or clears existing case data — explicit (`rm -rf`, `rsync --delete`) and **implicit** (`decomposePar -force`, `>` log overwrite, `tar` overwrite, `scp` overwrite) — is destructive; before running one, list what would be cleared and confirm.

**Resubmission defaults to resume**: the sbatch templates skip decomposePar conditionally (`scripts/sbatch_resume_template.sh`); for a deliberate clean rerun use the -force variant (`scripts/sbatch_template.sh`) and `tar`-back-up the processor directories first.
