# Harvest workflow (bringing finished cases back home)

> Three incidents codified into rules: **run stepwise — confirm the previous step succeeded before starting the next**.

## Overall flow (five steps, strict order)

```
① Detect completion (End marker)
② Reconstruct segment-end times on the cluster (reconstructPar -time "list")
③ Pack + rsync back to local
④ Unpack and verify locally (expected time dirs present)
⑤ Whitelist-delete on the cluster (only cases that passed ④)
```

## ① Detect completion

```bash
ssh <cluster> 'cd ~/cases && for c in $(cat cases.txt); do
  grep -q "^End$" "$c/log.run" && echo "$c"
done'
```

**Caution**: 100% progress ≠ finished (rounded display); the `End` marker is mandatory.

## ② Reconstruct segment-end times on the cluster

For a running case, the time dirs live inside the processor* dirs (decomposed). Before harvesting, reconstruct them to the case root:

```bash
ssh <cluster> 'source $HOME/OpenFOAM/OpenFOAM-9/etc/bashrc
module load compiler/gcc/9.3.0 mpi/openmpi/openmpi-4.1.5-gcc9.3.0
source $HOME/OpenFOAM/OpenFOAM-9/etc/bashrc
cd ~/cases/<case>
reconstructPar -time "0.80,1.12,1.46,1.80,2.14"    # segment-end time list
'
```

**Key**: the OF environment must be sourced, otherwise `command not found`.

## ③ Pack + transfer back

```bash
# Pack on the cluster (to the home directory, not /tmp)
# 🚨 constant/ MUST ride along (iron rule ④), otherwise local can only substitute a
# different mesh — planting a hidden mismatch
ssh <cluster> 'tar czf ~/harvest_<case>.tar.gz -C ~/cases/<case> 0/ 0.80 1.12 ... constant/ system/ log.run'

# rsync back (resumable)
rsync -az <cluster>:harvest_<case>.tar.gz ~/results/
```

## ④ Verify locally

```bash
mkdir -p ~/results/<case>
tar xzf ~/results/harvest_<case>.tar.gz -C ~/results/<case>
# verify: expected time dirs present (e.g. ≥5 segment ends + 0/)
ls ~/results/<case>/ | grep -cE "^[0-9]"
```

## ⑤ Whitelist delete

```bash
# fixed whitelist only (NEVER dynamic grep-End detection!)
for c in caseA caseB caseC; do
  ssh <cluster> "rm -rf ~/cases/$c"
done
```

## Four iron rules (incident-certified)

| Rule | Incident origin | Note |
|---|---|---|
| **Delete only against a fixed whitelist** | a dynamic `grep End` deleted cases that finished inside the harvest window | conditions change inside the operation window |
| **A failed step must block** | after `reconstructPar command not found`, `\|\| tail` swallowed the error and rm proceeded | use `exit 1`, not `\|\| tail` |
| **Transfer and delete are separate steps** | one failing step in a merged script cascaded | confirm each step before the next |
| **constant/ must ride along in the pack** | harvest of a 27-case batch (2026-10-27, details below) | a pack missing constant/ forces a local mesh substitute that mismatches the cluster-side mesh |

## Incident 1: pack missing constant/ → ParaView refuses the whole batch (2026-10-27, 27 cases)

**What happened**: the 27 harvest packs contained only `0/ time-dirs system/ log.run`. The cluster-side sbatch meshes were **generated on the spot by snappyHexMesh** (the bundle carries only STL sources, no polyMesh); after harvest, a local constant/polyMesh was substituted with matching cell/face totals, but the face split between the `nozzle_outnozzle`/`nozzle_tipnozzle` patches differed by 8 faces (312/336 locally vs 316/332 on the cluster) — snappy's face assignment at the STL out/tip junction carries machine-to-machine floating-point differences. The ParaView OpenFOAM reader validates mesh face counts per patch against the field patch segment counts and, on mismatch, reports `Number of cells/points in mesh and field don't match` and refuses all fields — all 27 cases failed to open. By then the cluster side had already been deleted per procedure; the true meshes were gone forever.

**The repair posture** (field data is the only trusted anchor): the `phi` (surfaceScalarField) patch-segment nonuniform counts in a time dir equal the true face counts of each patch at write time — correct the local boundary file's `nFaces` from them and shift `startFace` accordingly (subsequent patches +4/+8, keeping first-to-last contiguous and summing to the faces total). Verify with a startFace-chain check + a pvpython spot check, zero errors. In the boundary file the nFaces line comes **before** the startFace line — mind an awk state machine not clearing the previous rule's flag early (this was botched twice in one session and rolled back from boundary.bak).

**Prevention**: harvest packs always include constant/; if a mesh can only be substituted after the fact, immediately spot-check whether any time dir's phi patch counts match the boundary nFaces.

## Incident 2: local mesh substitution skipped surfaceFeatures → feature edges mis-snapped in the 0-system (closed 2026-10-28)

**What happened**: after the missing-constant/ incident, the local re-mesh command chain ran only `blockMesh + snappyHexMesh` and **skipped `surfaceFeatures`**. The eMesh carried by the deployment bundle from TEMPLATE (`triSurface/nozzle.eMesh` and `extendedFeatureEdgeMesh/`, both places) is a snapshot in the generator's coordinate system (the 0 system), while the STL had been translated by 0.23 — snappy snapped along feature edges systematically offset by 0.23 mm, producing systematically degraded meshes (max non-orthogonality 61.2° vs the correct 52.8°; nozzle patch faces 312/336 vs 316/332, mismatching the fields). The eMesh files "happening to exist" made skipping surfaceFeatures look harmless — **the trap hides in "file present, wrong coordinate system"**.

**Diagnostic fingerprints**: degraded = non-orthogonality ≈61.15° / skewness ≈1.52 / patch **312:336**; correct = ≈52.84° / ≈3.38 / **316:332** (= field phi patch counts). Five control runs (WSL serial/parallel, older STL, older eMesh, cluster environment) all landed on 52.84° — the environment was innocent; the final reproduction matched the degraded version on every metric. snappy is highly deterministic across machines at the same version — when quality looks off, suspect the inputs (especially the feature-edge coordinate system), not the machine.

**Iron rule**: local re-meshing always runs the full generator chain (including surfaceFeatures), never a hand-shortened one; deployment bundles must not carry eMesh (generate on the spot, mandatory); before archiving a mesh, check that the boundary nozzle face counts equal the field phi patch counts.

## Harvest cadence: harvest at End, roll continuously (storage-first, decided 2026-11-11)

While a large batch runs, **harvesting does not wait for batch completion**: the periodic patrol (or `patrol.sh`) finds a case at End → immediately run the five-step pipeline → delete on the cluster once local verification passes, rolling quota free for the next deployment. One nine-case line was harvested in six waves this way — a single case's full-history tar runs 1.2–1.4G, and letting it pile up to batch end would have held 10G+ of quota extra.

Two companions:

- **Incremental insurance for long cases**: for cases expected to run days, the patrol also does `reconstructPar -newTimes` + an rsync incremental of the new times (progress survives NODE_FAIL and slow-node churn); nothing is deleted on the cluster until End, then the full harvest runs.
- **Quota pressure from running cases** is handled by `prune_keepseg.sh` (segment ends + sliding window) capping per-case footprint. Division of labor: prune manages processor build-up of running cases; fast harvest releases finished cases wholesale.

## Automatic harvest loop

See `scripts/auto_cycle.sh` — runs steps ①–⑤ automatically (with safety verification), one round every 10 minutes, logging automatically.
