#!/bin/bash
# sbatch_resume_template.sh — 续跑模板（保 processor 进度，错题集案例六引出）
#
# 与 sbatch_template.sh（重跑版）差异：
#   - decomposePar 条件跳过（processor0 已存在即不分解，保中途档）
#   - log.run 用 >> 追加（保留首跑记录，Time 序列连续）
#
# 重投前必查 processor0 档况（见 skill references/slurm-pitfalls.md §7）：
#   ls <案>/processor0/ | grep -E '^[0-9]' | sort -g | tail -1
# 有中途档(>0) → 用本模板（续跑）；仅 0 → 用 sbatch_template.sh（重跑）。
#
# 替换 <占位符> 后使用。经验要点同 sbatch_template.sh（bundle 预解包、
# --bind-to core:overload-allowed、脚本失败阻断、-t 给足）。
#SBATCH -J <jobname>r
#SBATCH -p <partition>
#SBATCH -N 1
#SBATCH --ntasks-per-node=<cores>
#SBATCH --array=1-<ncases>
#SBATCH -t <max_hours>:00:00
#SBATCH -o logs/<jobname>r_%a.out

module purge
module load compiler/gcc/9.3.0
module load mpi/openmpi/openmpi-4.1.5-gcc9.3.0
source $HOME/OpenFOAM/OpenFOAM-9/etc/bashrc
export OMP_NUM_THREADS=1

set -euo pipefail
ROOT=$HOME/<deploy_dir>
mkdir -p "$ROOT" logs

CASE=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$ROOT/_shared/cases.txt")
echo "=== resume array ${SLURM_ARRAY_TASK_ID} → $CASE ==="
cd "$ROOT/$CASE"

# ---- 续跑关键：processor0 已存在则跳过分解，保留中途档 ----
if [ ! -d processor0 ]; then
  echo "--- 首次分解（无 processor0）---"
  decomposePar -force > log.decompose 2>&1 || { tail -20 log.decompose; exit 1; }
else
  latest=$(ls processor0/ | grep -E '^[0-9]' | sort -g | tail -1)
  echo "--- processor0 已存在，跳过分解（续跑保档），最新档: $latest ---"
fi

# ---- 网格流程（已建则跳过；续跑案通常已建）----
if [ ! -d constant/polyMesh ]; then
  echo "--- 网格 ---"
  blockMesh        > log.blockMesh       2>&1 || { tail -20 log.blockMesh; exit 1; }
  surfaceFeatures  > log.surfaceFeatures 2>&1 || { tail -20 log.surfaceFeatures; exit 1; }
  snappyHexMesh -overwrite > log.snappy  2>&1 || { tail -30 log.snappy; exit 1; }
  checkMesh        > log.checkMesh       2>&1 || true
  setFields        > log.setFields       2>&1 || { tail -20 log.setFields; exit 1; }
fi

# ---- 续跑求解（startFrom latestTime 从 processor 最新档续，>> 追加保记录）----
echo "--- resume solver -parallel (<cores> cores) ---" >> log.run
mpirun --bind-to core:overload-allowed -np $SLURM_NTASKS \
  <solver> -parallel >> log.run 2>&1 || true
if ! grep -q "^End$" log.run; then
  echo "FAIL run:"; tail -30 log.run; exit 1
fi

# ---- 重构末态 ----
reconstructPar -latestTime > log.reconstruct 2>&1 || true
foamListTimes | tr '\n' ' '; echo
echo "CASE-RESUME-DONE: $CASE"
