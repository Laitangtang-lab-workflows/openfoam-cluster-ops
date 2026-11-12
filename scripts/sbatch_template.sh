#!/bin/bash
# sbatch_template.sh — 重跑版（decomposePar -force 清 processor，从 0 重跑）
# ⚠ 重投前先查 processor0 档况（见 slurm-pitfalls.md §7）：有中途档 → 用 sbatch_resume_template.sh（续跑保进度），仅 0 → 用本模板。
# 参数化，替换 <> 占位符后使用
#
# 经验要点（2026-10 批次实战认证）：
#   - bundle 预解包（array 并发解包必竞争）
#   - --bind-to core:overload-allowed（--hint=compute 可能不被支持）
#   - 脚本失败必须阻断（|| { tail; exit 1; }，不用 || tail）
#   - -t 给足（运行中作业改不了 TimeLimit）
#SBATCH -J <jobname>
#SBATCH -p <partition>
#SBATCH -N 1
#SBATCH --ntasks-per-node=<cores>
#SBATCH --array=1-<ncases>
#SBATCH -t <max_hours>:00:00
#SBATCH -o logs/<jobname>_%a.out

module purge
module load compiler/gcc/9.3.0
module load mpi/openmpi/openmpi-4.1.5-gcc9.3.0
source $HOME/OpenFOAM/OpenFOAM-9/etc/bashrc
export OMP_NUM_THREADS=1

set -euo pipefail
ROOT=$HOME/<deploy_dir>
mkdir -p "$ROOT" logs

# 预解包兜底（正常应在提交前手动解包）
if [ ! -d "$ROOT/_shared" ]; then
  tar xzf $HOME/<bundle>.tar.gz -C "$ROOT"
fi

CASE=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$ROOT/_shared/cases.txt")
echo "=== array ${SLURM_ARRAY_TASK_ID} → $CASE ==="
cd "$ROOT/$CASE"

# ---- 网格流程（已建则跳过）----
if [ ! -d constant/polyMesh ]; then
  echo "--- 网格 ---"
  blockMesh        > log.blockMesh       2>&1 || { tail -20 log.blockMesh; exit 1; }
  surfaceFeatures  > log.surfaceFeatures 2>&1 || { tail -20 log.surfaceFeatures; exit 1; }
  snappyHexMesh -overwrite > log.snappy  2>&1 || { tail -30 log.snappy; exit 1; }
  checkMesh        > log.checkMesh       2>&1 || true
  setFields        > log.setFields       2>&1 || { tail -20 log.setFields; exit 1; }
fi

# ---- 求解 ----
decomposePar -force > log.decompose 2>&1 || { tail -20 log.decompose; exit 1; }
echo "--- solver -parallel (<cores> cores) ---"
mpirun --bind-to core:overload-allowed -np $SLURM_NTASKS \
  <solver> -parallel > log.run 2>&1 || true
if ! grep -q "^End$" log.run; then
  echo "FAIL run:"; tail -30 log.run; exit 1
fi

# ---- 重构末态 ----
reconstructPar -latestTime > log.reconstruct 2>&1 || true
foamListTimes | tr '\n' ' '; echo
echo "CASE-DONE: $CASE"
