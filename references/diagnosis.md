# Slow-case diagnosis (three steps) + failure troubleshooting

## The three-step slow-case diagnosis (field-tested)

| Step | Action | Command / method | Criterion |
|---|---|---|---|
| ① | **Same-family comparison** | compare progress of same-column (same λ / same material family), same-length cases | rate gap > 3× → abnormal |
| ② | **CPU occupancy** | `grep ExecutionTime` at the log tail | **ratio < 90% = the node is being squeezed** (healthy ≈ 99%) |
| ③ | **Iteration health** | No Iterations at the log tail | p_rgh a few-to-tens, U a few, θ 1 → the case itself is fine |

**Action flow**:
- ② says node trouble → `scancel` + `sbatch --array=<id> --exclude=<slow-node>` resubmit
- ③ says genuine numerical difficulty of the case → check maxDeltaT/Courant/residuals; consider tuning or accept the slower pace

## Common-failure troubleshooting table

| Symptom | Likely cause | Diagnostic command | Fix |
|---|---|---|---|
| Job FAILED (within seconds) | mesh / initial field / material-field errors | `tail -30 logs/<job>_<id>.out` | fix and resubmit |
| Job FAILED (minutes in) | missing environment for setFields/reconstructPar | look for `command not found` in the log | add the environment source to sbatch |
| Job RUNNING but barely progressing | slow node / genuine numerical difficulty | three-step diagnosis | switch node or tune |
| dt far below maxDeltaT | shock/development phase Courant-limited | `grep "^deltaT" log.run \| tail -1` | normal; recovers later |
| alpha shows NaN | numerical divergence | `grep -ci "nan" log.run` | check maxDeltaT/Courant/material parameters |
| Contact-angle patchField error | BC patch names don't match the mesh | `grep "patchField" log.run` | unify patch naming (STL solid name = BC key) |
| Time going backwards (t < resume point) | decomposePar -force rebuilt from 0 | compare case-root time dirs vs log head | ensure the case root holds the resume time |
| Job re-scheduled | node failure / SLURM policy | `sacct -j <id> -o Start,End,State` | data intact; auto-resumes |
| Solver exits 127 at startup (not command-not-found) | missing shared libraries (e.g. RheoTool linking PETSc/Hypre) | `ldd $(which <solver>) \| grep 'not found'` | add `export PETSC_DIR/PETSC_ARCH + LD_LIBRARY_PATH` to sbatch (2026-10-31 confirmed: stock rheoInterFoam links libpetsc/libHYPRE; only the interp variant had been run before, hiding it) |
| Solver segfault (signal 11) with the stack parked in a harmless library function (e.g. dimensionSet==/nearInterface) | **ABI mismatch**: one source tree re-built a user library (e.g. the interp fork rebuilt libconstitutiveEquations over libbin), mismatching solver binaries built against another tree | `ls -la $FOAM_USER_LIBBIN/*.so` — check whether the libraries are of "mixed generations"; run another solver on the same case (that one working confirms it) | re-build the solver with header-binary pairing per library: headers of forked libraries point at the fork tree, the rest at the tree their binaries came from (confirmed and fixed 2026-10-31 after three reproductions) |
| Rebuild fails: fatal error: petscconf.h | in options, `-isystem$(EIGEN_RHEO)` with EIGEN_RHEO unexported — the empty argument eats the next `-isystem$PETSC_DIR/$(PETSC_ARCH)/include` | `echo $EIGEN_RHEO` | export EIGEN_RHEO/PETSC_DIR/PETSC_ARCH before building |
| Rebuild fails: dynamicFvMesh.H / interfaceProperties.H not found | in-tree Make/options uses the old OF layout (e.g. the fe40 branch `dynamicMesh/dynamicFvMesh`), while OF9 actually uses `src/dynamicFvMesh` and `twoPhaseModels/interfaceProperties` | compare options with a working branch (e.g. the of90 branch) | use the same-repo of90 branch options paths; or cp the stock solver into a proven tree and pair-build as above |
| Per-step time 10×+ worse after raising domains/cores (e.g. 4→8) | **hierarchical x-slicing load imbalance**: in a long narrow print domain the nozzle/interface/deposition front concentrate in a thin x band; a (4 2 1) cut leaves 1–2 ranks working while the rest wait at the barrier | measured step-rate comparison (ΔTime ÷ seconds) + ExecutionTime/ClockTime | switch to `method scotch`, re-decompose, resubmit (2026-11-08 in the field: (4 2 1) 0.2 steps/s → scotch 8 domains 3.6 steps/s); for long narrow domains always scotch, never geometric x-cuts |
| Newer node types (ThreadsPerCore=1) at ~50% CPU efficiency | node half-occupancy / contention (confirmed 2026-11-08 on d01r4n08; same period b07/b14/b11 died wholesale — turbulent hardware phase) | ExecutionTime/ClockTime < 90% | scancel + `--exclude=<node>` resubmit |

## Quick progress commands

```bash
# per-case progress
ssh <cluster> 'cd ~/cases
for c in $(cat cases.txt); do
  [ -d "$c" ] || continue
  t=$(grep "^Time = " "$c/log.run" 2>/dev/null | tail -1)
  e=$(grep -c "^End$" "$c/log.run" 2>/dev/null)
  echo "$c: $t End=$e"
done'

# capacity
ssh <cluster> 'du -sh ~/cases'

# queue
ssh <cluster> 'squeue -u $USER -h | wc -l'
```
