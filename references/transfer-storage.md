# Network and storage (transfer · quota · cleanup)

## 1. Extremely slow transfers (~100KB/s)

**Symptom**: scp/rsync to the SCNet cluster manages only ~100–160KB/s. A 250MB file takes ~45 minutes.

**Countermeasures**:
- Use **rsync** (resumable), not scp (an interruption means starting over)
- Pack into a single tar.gz before transferring (faster than per-file)
- Budget transfer time (hours) and run in the background
- Cluster-side temporary files go to the **home directory** (/tmp gets cleaned periodically)

## 2. /tmp cleaned periodically

**Symptom**: a tar ball left in /tmp vanishes after a few hours (`No such file or directory`).

**Fix**: any temporary file that must survive across ssh sessions goes to `~/` (home); delete manually when done.

## 2a. scp from WSL `/mnt/c` transfers an empty file (confirmed 2026-11-12)

**Symptom**: `scp /mnt/c/Users/.../xxx.sh <cluster>:~/` reports success, but the remote file is **0 bytes** (local 725B); the downstream bash runs an empty file and exits instantly, the log is 0 bytes — extremely hard to spot.

**Fix**: `cp` to the WSL ext4 side (e.g. `~/`) first and scp from ext4; after transferring, **verify remotely with `wc -c`** before executing. The `/mnt/c` (Windows drvfs mount) + scp combination carries this trap; cat/execution are unaffected.

## 2b. Running long remote commands (nested quotes and SIGPIPE false deaths)

**Iron rule: long cluster-side commands (environment header + multi-line logic) always go through "script file + sbatch/srun", never inlined on the ssh command line**:

- `pwsh → wsl bash → ssh → remote bash` four-layer quote nesting gets eaten at some layer (`2>&1` hijacked by pwsh as `Out-File`; `>`/`;`/`~` silently truncating arguments) — symptoms are zero output or arguments missing so a different command executes (measured: `ls <path>` became bare `ls` listing the home dir);
- when diagnosing remote output, **never use `| head N`**: the truncated pipe raises SIGPIPE and kills the running script — the "instant death" illusion with `PIPESTATUS=1` (especially nasty under bash -x);
- `ssh 'bash -l <file>'` and `ssh 'bash -l -s' < file` are unreliable under this cluster's login configuration (zero-output exit); `bash -l -c '<single command>'` works; never lean long logic on these channels — the sbatch script file is the only execution environment validated over six field rounds;
- under non-interactive ssh (no `-l`) the `module` function does not exist; `module load` fails silently and the OpenFOAM libraries then report GLIBCXX version errors — the environment header must match the execution channel.

## 3. Storage quota management (100G as the example)

**Core conflict**: full time histories of N cases can far exceed the quota (e.g. 27 cases × 5G = 135G > 100G).

**Retention policy (segment ends + sliding window)**:
- Keep per case: the state-sampling times (e.g. the 5 segment ends V1–V5) + the newest 5 times as a sliding window + the `0/` initial field
- Delete: all other time dirs (both case root and processor*)
- Steady-state footprint ≈ N × 11 time dirs × per-dir size (e.g. 27 × 11 × 65MB ≈ 20G)

**Implementation**: run `prune_keepseg.sh` after the daily patrol (see scripts/).

**Emergency space**: when close to the limit, first delete every non-segment-end time outside the sliding windows (keep the 5 segment ends + newest 1).

**Deleting history times while running is safe**: OpenFOAM writes future times without reading history; `startFrom latestTime` always stays inside the retained set.

## 4. Per-time-dir size estimation

For a ~100k-cell snappy mesh, ASCII format, writePrecision 8:
- Reconstructed case root: ~15–25MB per time dir
- 4-domain processors combined: ~50–80MB per time (incl. decomposition overhead)
- Harvest packing (tar.gz): ~170–360MB per case for 5 time dirs

## 5. OpenFOAM environment on the cluster

Running OpenFOAM tools over ssh (reconstructPar/decomposePar/checkMesh, …) requires:

```bash
ssh <cluster> 'source $HOME/OpenFOAM/OpenFOAM-9/etc/bashrc
module load compiler/gcc/9.3.0 mpi/openmpi/openmpi-4.1.5-gcc9.3.0
source $HOME/OpenFOAM/OpenFOAM-9/etc/bashrc
cd ~/case && reconstructPar -time "0.8,1.2,1.6"'
```

Missing environment = `command not found` (and `\|\| tail` will swallow that error so a later rm proceeds — see harvest-workflow.md).

**Three corrections (confirmed 2026-11-12 during a harvest)**:

1. The example above only holds **inside compute-node sbatch scripts**; under non-interactive ssh (no login shell) the `module` function does not exist, fails silently, and the OF libraries then report GLIBCXX version errors (see §2b).
2. **`set -e` must not cover `source .../bashrc`**: near the end of bashrc, `command -V wmRefresh | head -1 | grep -q function && unalias wmRefresh` makes `unalias` return 1 in a non-interactive shell, and set -e kills the whole script on the spot — the symptom is a **zero-output instant exit with a 0-byte log**, extremely hard to locate. The correct pattern, as in the sbatch templates: run the environment header (module + source + export) first, and put `set -euo pipefail` **after** it.
3. The OF binaries live in `$HOME/OpenFOAM/OpenFOAM-9/platforms/linux64GccDPInt32Opt/bin/` (the platform's shared installation); the PETSc trio of paths stems from the same shared install.

## 6. decomposePar -force restart behavior

`decomposePar -force` re-decomposes from the case root's latestTime. If the case root only has `0/` (nothing reconstructed mid-run), a restart **reruns from 0**. Mid-run resume requires a resume time at the case root (or the newest time kept in the processor dirs).
