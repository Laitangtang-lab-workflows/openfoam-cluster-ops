#!/bin/bash
# auto_cycle.sh - 自动收割循环（20轮×10min，含分步安全纪律）
# 不用 set -u：已两次因未初始化变量崩溃，各步自有 || continue 兜底
# 本机配置见同目录 _env.sh（从 _env.example 复制改写）
cd "$(dirname "$0")"
[ -f _env.sh ] && . ./_env.sh || { echo "缺 _env.sh"; exit 1; }
: "${SSH_HOST:=cluster}" "${DEPLOY_DIR:?}" "${CASES_FILE:=_shared/cases.txt}" "${CASE_GLOB:=*/}"
: "${RESULTS:?}" "${KEEP_LAST:=5}" "${SEGS:=}"
if ! declare -f segs_for_case >/dev/null; then
  segs_for_case() { echo "$SEGS"; }
fi
DELETED_LOG=$RESULTS/harvest_log.txt
mkdir -p "$RESULTS"
log(){ echo "[$(date '+%m-%d %H:%M:%S')] $*" | tee -a "$DELETED_LOG"; }

for ROUND in $(seq 1 20); do
  log "===== 轮次 $ROUND ====="

  # ---- ① 巡检 ----
  NEW_DONE=$(ssh "$SSH_HOST" 'cd '"$DEPLOY_DIR"' 2>/dev/null
  for c in $(cat '"$CASES_FILE"'); do
    [ -d "$c" ] || continue
    grep -q "^End$" "$c/log.run" 2>/dev/null && echo "$c"
  done
true' 2>/dev/null) || NEW_DONE=""

  if [ -z "$NEW_DONE" ]; then
    log "无新完成案"
  else
    log "新完成案: $(echo $NEW_DONE | tr "\n" " ")"
  fi

  # ---- ② 收割（重构→打包→传输→验证）----
  HARVESTED=""
  for c in $NEW_DONE; do
    SEGS_C=$(segs_for_case "$c")
    [ -z "$SEGS_C" ] && { log "$c: 无段末表，跳过"; continue; }
    EXPECT=$(( $(echo $SEGS_C | wc -w) + 1 ))   # 0/ + 段末档数 = 解包后应至少有的数字档数
    if [ -d "$RESULTS/$c" ] && [ "$(ls "$RESULTS/$c" 2>/dev/null | grep -cE "^[0-9]" || true)" -ge "$EXPECT" ]; then
      log "$c: 已在本地"
      HARVESTED="$HARVESTED $c"
      continue
    fi
    log "收割: $c"
    ssh "$SSH_HOST" "source \$HOME/OpenFOAM/OpenFOAM-9/etc/bashrc 2>/dev/null || true
cd $DEPLOY_DIR/$c || exit 1
if [ -d processor0 ]; then
  need=\"\"
  for s in $SEGS_C; do [ -d \"\$s\" ] || need=\"\$need \$s\"; done
  [ -n \"\$need\" ] && reconstructPar -time \"\$(echo \$need | tr \" \" \",\")\" > log.recon_seg 2>&1 || true
fi
allsegs=\$(ls | grep -E \"^[0-9]\" | grep -v \"^0\$\" | tr \"\n\" \" \")
tar czf ~/harvest_$c.tar.gz 0/ \$allsegs system/ log.run constant/" 2>/dev/null || { log "$c: 打包失败"; continue; }

    cd "$RESULTS"
    rsync -az "$SSH_HOST:harvest_$c.tar.gz" . 2>/dev/null || { cd - >/dev/null; log "$c: 传输失败"; continue; }
    mkdir -p "$c"
    tar xzf "harvest_$c.tar.gz" -C "$c" 2>/dev/null
    n=$(ls "$c" 2>/dev/null | grep -cE "^[0-9]" || true)
    if [ "$n" -ge "$EXPECT" ]; then
      log "$c: ✓ 收割成功（$n 档）"
      HARVESTED="$HARVESTED $c"
    else
      log "$c: ✗ 解包异常（$n 档 < 期望 $EXPECT），不删"
    fi
    cd - >/dev/null
  done

  # ---- ③ 白名单删除 ----
  for c in $HARVESTED; do
    ssh "$SSH_HOST" "rm -rf $DEPLOY_DIR/$c" 2>/dev/null && log "已删: $c"
  done
  [ -n "$HARVESTED" ] && ssh "$SSH_HOST" 'rm -f ~/harvest_*.tar.gz' 2>/dev/null

  # ---- ④ prune（运行中案：段末 + 滑动窗）----
  TOTAL=0
  for c in $(ssh "$SSH_HOST" 'cd '"$DEPLOY_DIR"' 2>/dev/null
for c in $(cat '"$CASES_FILE"'); do
  [ -d "$c" ] || continue
  grep -q "^End$" "$c/log.run" 2>/dev/null && continue
  [ -d "$c/processor0" ] || continue
  echo "$c"
done' 2>/dev/null); do
    SEGS_C=$(segs_for_case "$c")
    [ -z "$SEGS_C" ] && continue
    n=$(ssh "$SSH_HOST" 'cd '"$DEPLOY_DIR/$c"'/processor0 2>/dev/null || exit 0
times=$(ls | grep -E "^[0-9]+([.][0-9]+)?$" | sort -g)
[ -z "$times" ] && exit 0
latest=$(echo "$times" | tail -'"$KEEP_LAST"')
n=0
for tt in $times; do
  sk=0
  for kk in '"$SEGS_C"'; do [ "$tt" = "$kk" ] && sk=1; done
  echo "$latest" | grep -qx "$tt" && sk=1
  [ "$sk" = "0" ] && rm -rf "../processor*/$tt" "../$tt" && n=$((n+1))
done
echo $n' 2>/dev/null) || n=0
    TOTAL=$((TOTAL + ${n:-0}))
  done
  log "prune: $TOTAL 档"

  # ---- ⑤ 容量+状态 ----
  CAP=$(ssh "$SSH_HOST" 'du -sh '"$DEPLOY_DIR"' 2>/dev/null | cut -f1; echo "案数: $(ls -d '"$DEPLOY_DIR/$CASE_GLOB"' 2>/dev/null | wc -l)"; squeue -u $USER -h 2>/dev/null | wc -l' 2>/dev/null)
  log "状态: $CAP"

  # ---- ⑥ 进度速览（每5轮）----
  if [ $((ROUND % 5)) = 1 ]; then
    PROG=$(ssh "$SSH_HOST" 'cd '"$DEPLOY_DIR"' 2>/dev/null
for c in $(cat '"$CASES_FILE"'); do
  [ -d "$c" ] || continue
  t=$(grep "^Time = " "$c/log.run" 2>/dev/null | tail -1 | sed "s/Time = //")
  end=$(grep "^endTime" "$c/system/controlDict" | awk "{print \$2}" | tr -d ";")
  awk -v a="$t" -v b="$end" "BEGIN{printf "%s %.0f%%\n", "'$c'", 100*a/b}"
done' 2>/dev/null)
    log "--- 进度 ---"
    echo "$PROG" | tee -a "$DELETED_LOG"
  fi

  sleep 600
done
log "===== 20 轮完成 ====="
