#!/bin/bash
# prune_keepseg.sh - 段末档 + 滑动窗清理器
# 保留：0/ + 段末表（segs_for_case 或 SEGS）+ 最新 KEEP_LAST 档；删其余（案根与 processor* 双处）
# 本机配置见同目录 _env.sh（从 _env.example 复制改写）；段末表按案名可定制
set -euo pipefail
cd "$(dirname "$0")"
[ -f _env.sh ] && . ./_env.sh || { echo "缺 _env.sh（从 _env.example 复制改写）"; exit 1; }
: "${SSH_HOST:?}" "${DEPLOY_DIR:?}" "${CASES_FILE:=_shared/cases.txt}" "${KEEP_LAST:=5}" "${SEGS:=}"
if ! declare -f segs_for_case >/dev/null; then
  segs_for_case() { echo "$SEGS"; }   # 默认：全案共用 SEGS；_env.sh 可按案名覆盖
fi

echo "=== 逐案清理（保留段末 + 最新 $KEEP_LAST 档）==="
for c in $(ssh "$SSH_HOST" 'cd '"$DEPLOY_DIR"' 2>/dev/null && cat '"$CASES_FILE"); do
  segs=$(segs_for_case "$c")
  [ -z "$segs" ] && { echo "$c: 无段末表，跳过"; continue; }
  n=$(ssh "$SSH_HOST" 'cd '"$DEPLOY_DIR/$c"'/processor0 2>/dev/null || exit 0
times=$(ls | grep -E "^[0-9]+([.][0-9]+)?$" | sort -g)
[ -z "$times" ] && exit 0
latest=$(echo "$times" | tail -'"$KEEP_LAST"')
n=0
for tt in $times; do
  sk=0
  for kk in '"$segs"'; do [ "$tt" = "$kk" ] && sk=1; done
  echo "$latest" | grep -qx "$tt" && sk=1
  [ "$sk" = "0" ] && rm -rf "../processor*/$tt" "../$tt" && n=$((n+1))
done
echo $n' 2>/dev/null) || n=0
  [ "${n:-0}" -gt 0 ] 2>/dev/null && echo "$c: 删 $n 档（留: $segs + 窗$KEEP_LAST）"
done
echo "=== 清理后: $(ssh "$SSH_HOST" 'du -sh '"$DEPLOY_DIR"' 2>/dev/null | cut -f1') ==="
