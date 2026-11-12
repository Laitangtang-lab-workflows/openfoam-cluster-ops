#!/bin/bash
# patrol.sh - 快速巡检：状态+进度+容量（只读）
# 本机配置见同目录 _env.sh（从 _env.example 复制改写）
set -euo pipefail
cd "$(dirname "$0")"
[ -f _env.sh ] && . ./_env.sh || { echo "缺 _env.sh（从 _env.example 复制改写）"; exit 1; }
: "${SSH_HOST:?}" "${DEPLOY_DIR:?}" "${CASES_FILE:=_shared/cases.txt}" "${CASE_GLOB:=*/}"

echo "=== ① 队列 ==="
ssh "$SSH_HOST" 'squeue -u $USER -h 2>/dev/null | wc -l' 2>/dev/null

echo "=== ② 案件进度 ==="
ssh "$SSH_HOST" 'cd '"$DEPLOY_DIR"' 2>/dev/null || exit 0
for c in $(cat '"$CASES_FILE"'); do
  [ -d "$c" ] || continue
  t=$(grep "^Time = " "$c/log.run" 2>/dev/null | tail -1 | sed "s/Time = //")
  end=$(grep "^endTime" "$c/system/controlDict" | awk "{print \$2}" | tr -d ";")
  e=$(grep -c "^End$" "$c/log.run" 2>/dev/null || true)
  fat=$(grep -c "FOAM FATAL" "$c/log.run" 2>/dev/null || true)
  pct=$(awk -v a="$t" -v b="$end" "BEGIN{if(b>0) printf \"%.0f\", 100*a/b; else print 0}")
  st=""; [ "$e" != "0" ] && st="★End"
  [ "$fat" != "0" ] && st="$st!!FATAL=$fat"
  echo "$c|$t/$end|${pct}%$st"
done' 2>/dev/null

echo ""
echo "=== ③ 容量 ==="
ssh "$SSH_HOST" 'du -sh '"$DEPLOY_DIR"' 2>/dev/null; echo "案数: $(ls -d '"$DEPLOY_DIR/$CASE_GLOB"' 2>/dev/null | wc -l)"' 2>/dev/null
