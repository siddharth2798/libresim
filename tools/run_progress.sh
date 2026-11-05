# tools/run_progress.sh: plan, progress and heartbeat for run.sh. Sourced by run.sh (and by
# tools/test_run_sh.sh). Needs from run.sh: LOG, fd 3 (the original stdout), note, dry, RAW_IDS,
# raw_label/raw_active/<id>_done/<id>_files, EST_BYTES/EST_SECS, RAW_STEPS, PIPELINE, NAME, why_run.

HEARTBEAT=${RUN_HEARTBEAT:-15}   # seconds between "still running" lines; 0 = off
MBPS=${RUN_MBPS:-2}              # assumed download speed (MB/s), only for the time estimate
WC_BYTES=145000000               # ESA WorldCover tiles fetched by pipeline step 19 (about 145 MB)

# Typical seconds per step, used when data/run.log has no "(step NN: S s)" line yet.
declare -A TYPICAL=([05]=5 [04]=420 [02]=60 [03]=75 [06]=5 [06a]=5 [09]=5 [10]=1200 [11]=200 [12]=200
  [13]=25 [14]=5 [15]=3350 [16]=5 [17]=190 [19]=120 [20]=600 [21]=120 [27]=90 [import]=120)
declare -A LOGSECS=() SIZE=() ITEM_MODE=() ITEM_BYTES=() ITEM_EXACT=() ITEM_SECS=() ITEM_FILES=()
DONE_S=0 PLAN_TOTAL_S=0 DL_TOTAL=0 DL_DONE=0 FILE_N=0 FILE_I=0 WC_PLANNED=0 NEED_IMPORT=0 HB_PID=""
RP_IDS=() PS_ID=() PS_WHY=()

# ---------------------------------------------------------------- formatting
fmt_dur() {  # 150 -> "2 min 30 s"; 40 -> "40 s"; 1300 -> "22 min"
  local s=$1
  if ((s < 60)); then echo "$s s"
  elif ((s < 600)); then echo "$((s / 60)) min $((s % 60)) s"
  else echo "$(((s + 30) / 60)) min"; fi
}
fmt_size() { awk -v b="$1" 'BEGIN { if (b >= 1e9) printf "%.2f GB", b / 1e9; else if (b >= 1e6) printf "%d MB", b / 1e6 + 0.5; else printf "%d KB", b / 1e3 + 0.5 }'; }
fmt_gb() { awk -v b="$1" 'BEGIN { printf "%.2f", b / 1e9 }'; }
term_line() { echo "$1" >&3; echo "$1" >>"$LOG"; }   # to the terminal and the log, bypassing tee

# ---------------------------------------------------------------- expected times
load_log_secs() {  # latest "(step NN: S s)" per step from the log of earlier runs
  [[ -f $LOG ]] || return 0
  local s n
  while read -r s n; do LOGSECS[$s]=$n; done < <(awk '
    match($0, /\(step [0-9a-z]+: [0-9]+ s\)/) { split(substr($0, RSTART + 1, RLENGTH - 2), a, " "); sub(":", "", a[2]); last[a[2]] = a[3] }
    END { for (k in last) print k, last[k] }' "$LOG")
}
exp_secs() {  # expected seconds of step $1 (empty = unknown)
  local s=$1 v=${LOGSECS[$1]:-${TYPICAL[$1]:-}}
  [[ -n $v && $s == 19 && $WC_PLANNED == 1 ]] && v=$((v + WC_BYTES / (MBPS * 1000000)))
  echo "$v"
}
usual_text() {  # "about 20 min" / "under 1 min" / "unknown" for $1 seconds (may be empty)
  if [[ -z $1 ]]; then echo "unknown"; elif (($1 < 60)); then echo "under 1 min"; else echo "about $((($1 + 30) / 60)) min"; fi
}
overall_pct() {  # overall_pct [running_secs expected_secs]: finished work / expected total of the plan
  local run=${1:-0} e=${2:-0} p
  ((run > e)) && run=$e
  ((PLAN_TOTAL_S > 0)) || { echo 0; return; }
  p=$(((DONE_S + run) * 100 / PLAN_TOTAL_S)); ((p > 100)) && p=100
  echo "$p"
}
step_line() {  # header line for a step / item about to run: "step 10: buildings, usually about 20 min, overall 35 %"
  note "$1: ${2:+$2, }usually $(usual_text "$3"), overall $(overall_pct) %"
}

# ---------------------------------------------------------------- heartbeat
hb_start() {  # hb_start label expected_secs [logfile]: a line to the terminal and the log every $HEARTBEAT s
  ((HEARTBEAT > 0)) || return 0
  local label=$1 exp=${2:-0} logf=${3:-} start=$SECONDS
  (
    trap - ERR EXIT; set +e; sp=""
    trap '[[ -n $sp ]] && kill $sp 2>/dev/null; exit 0' TERM
    while :; do
      sleep "$HEARTBEAT" & sp=$!; wait $sp
      el=$((SECONDS - start)); line="    ... $label running $(fmt_dur $el)"
      [[ $exp -gt 0 ]] && line+=" (usually $(usual_text "$exp"))"
      line+=", overall $(overall_pct "$el" "$exp") %"
      if [[ -n $logf && -s $logf ]]; then   # last progress line of the script's own log
        last=$(tail -c 300 "$logf" | tr '\r' '\n' | grep -v '^[[:space:]]*$' | tail -n 1 | cut -c1-90)
        [[ -z $last ]] || line+=" | $last"
      fi
      term_line "$line"
    done
  ) &
  HB_PID=$!
}
hb_stop() {  # always safe to call (also from the ERR / EXIT traps)
  [[ -n ${HB_PID:-} ]] || return 0
  kill "$HB_PID" 2>/dev/null || true; wait "$HB_PID" 2>/dev/null || true; HB_PID=""
}
with_heartbeat() {  # with_heartbeat label expected_secs logfile cmd...  (no || here: set -e must stay active in cmd)
  local label=$1 exp=$2 logf=$3; shift 3
  hb_start "$label" "$exp" "$logf"; "$@"; hb_stop
}

# ---------------------------------------------------------------- download sizes
head_one() { curl -sIL --max-time 20 "$1" 2>/dev/null | tr -d '\r' | awk 'tolower($1) == "content-length:" { v = $2 } END { print v + 0 }' || true; }
head_sizes() {  # head_sizes url...: exact byte sizes into SIZE[url] by HTTP HEAD (8 at a time); none when offline
  [[ ${RUN_OFFLINE:-0} != 1 ]] && command -v curl >/dev/null || return 0
  local tmp i=0 u n; tmp=$(mktemp -d)
  for u in "$@"; do
    i=$((i + 1)); ( head_one "$u" >"$tmp/$i" ) &
    if ((i % 8 == 0)); then wait; fi
  done
  wait; i=0
  for u in "$@"; do i=$((i + 1)); n=$(cat "$tmp/$i" 2>/dev/null || true); n=${n:-0}; if ((n > 0)); then SIZE[$u]=$n; fi; done
  rm -rf "$tmp"; return 0
}
est_file_bytes() {  # built-in size guess when HEAD gives nothing (from the sizes on the author's machine)
  case $1 in
    *copernicus-dem-30m*) echo 31000000 ;; *copernicus-dem-90m*) echo 7500000 ;; *western-zone*) echo 221000000 ;;
    */airports.csv) echo 12700000 ;; */runways.csv) echo 4000000 ;; */navaids.csv) echo 1500000 ;;
    */airport-frequencies.csv) echo 1300000 ;; *) echo 1000000 ;;
  esac
}
fetch_begin() {  # fetch_begin url dest: "[3/17] name (84 MB)" header for one file of the plan
  ((FILE_N > 0)) || return 0
  local url=$1 dest=$2 sz=${SIZE[$1]:-} t
  FILE_I=$((FILE_I + 1))
  if [[ -n $sz ]]; then t="($(fmt_size "$sz"))"; else t="(about $(fmt_size "$(est_file_bytes "$url")"))"; fi
  note "[$FILE_I/$FILE_N] $(basename "$dest") $t"
}
dl_credit() {  # a download finished: add bytes, print "downloaded 0.62 of 1.22 GB (51 %)"
  DL_DONE=$((DL_DONE + $1))
  ((DL_TOTAL > 0)) || return 0
  local p=$((DL_DONE * 100 / DL_TOTAL)); ((p > 100)) && p=100
  if ((DL_TOTAL < 1000000000)); then note "downloaded $((DL_DONE / 1000000)) of $((DL_TOTAL / 1000000)) MB ($p %)"
  else note "downloaded $(fmt_gb "$DL_DONE") of $(fmt_gb "$DL_TOTAL") GB ($p %)"; fi
}

# ---------------------------------------------------------------- the plan
build_raw_plan() {  # which raw items are missing, with size and expected time
  local id u d s b ex n urls=()
  RP_IDS=(); FILE_N=0; FILE_I=0; DL_TOTAL=0; DL_DONE=0
  for id in "${RAW_IDS[@]}"; do
    raw_active "$id" || continue
    if "${id}_done"; then continue; fi
    RP_IDS+=("$id")
    if declare -F "${id}_files" >/dev/null; then
      while read -r u d; do urls+=("$u"); done < <("${id}_files")
    fi
  done
  ((${#urls[@]} == 0)) || head_sizes "${urls[@]}"
  for id in "${RP_IDS[@]}"; do
    if declare -F "${id}_files" >/dev/null; then   # plain downloads: sum of the files
      ITEM_MODE[$id]=fetch; b=0; ex=1; n=0
      while read -r u d; do
        n=$((n + 1)); s=${SIZE[$u]:-}
        if [[ -z $s ]]; then s=$(est_file_bytes "$u"); ex=0; fi
        b=$((b + s))
      done < <("${id}_files")
      ITEM_BYTES[$id]=$b; ITEM_EXACT[$id]=$ex; ITEM_FILES[$id]=$n
      ITEM_SECS[$id]=$((b / (MBPS * 1000000) + 1)); FILE_N=$((FILE_N + n))
    else                                            # gdal / git / corridor script: size unknown until done
      ITEM_MODE[$id]=est; ITEM_BYTES[$id]=${EST_BYTES[$id]}; ITEM_EXACT[$id]=0
      ITEM_FILES[$id]=1; ITEM_SECS[$id]=${EST_SECS[$id]}; FILE_N=$((FILE_N + 1))
    fi
    DL_TOTAL=$((DL_TOTAL + ITEM_BYTES[$id])); PLAN_TOTAL_S=$((PLAN_TOTAL_S + ITEM_SECS[$id]))
    for s in ${RAW_STEPS[$id]:-}; do NEWRAW[$s]=$id; done   # steps that read this data re-run after it arrives
  done
}
build_step_plan() {  # which pipeline steps will run and why (simulates the run: a step that runs makes its dependants stale)
  local s i k secs; local -A saved=()
  for k in "${!FORCE[@]}"; do saved[$k]=1; done
  PS_ID=(); PS_WHY=(); RAN=()
  for s in "${PIPELINE[@]}" $( ((A320)) && echo 06a ); do
    k=$(why_run "$s")
    if [[ -n $k ]]; then PS_ID+=("$s"); PS_WHY+=("$k"); RAN[$s]=1; fi
    unset "FORCE[$s]"
  done
  RAN=(); FORCE=(); for k in "${!saved[@]}"; do FORCE[$k]=1; done
  if [[ ${#PS_ID[@]} -gt 0 && " ${PS_ID[*]} " == *" 19 "* && -z $(ls -A data/raw/worldcover 2>/dev/null) ]]; then
    WC_PLANNED=1; DL_TOTAL=$((DL_TOTAL + WC_BYTES))
  fi
  for i in "${!PS_ID[@]}"; do secs=$(exp_secs "${PS_ID[$i]}"); PLAN_TOTAL_S=$((PLAN_TOTAL_S + ${secs:-0})); done
  if [[ -n $GODOT && ! -d game/.godot/imported ]]; then NEED_IMPORT=1; PLAN_TOTAL_S=$((PLAN_TOTAL_S + ${TYPICAL[import]})); fi
  return 0
}
item_text() {  # "187 MB, 6 files" / "about 150 MB, about 30 min"
  local id=$1 pre=""
  [[ ${ITEM_EXACT[$id]} == 1 ]] || pre="about "
  if [[ ${ITEM_MODE[$id]} == fetch ]]; then echo "$pre$(fmt_size "${ITEM_BYTES[$id]}"), ${ITEM_FILES[$id]} file(s)"
  else echo "$pre$(fmt_size "${ITEM_BYTES[$id]}"), $(usual_text "${ITEM_SECS[$id]}")"; fi
}
print_plan() {
  local id i s exact=0 est=0 mins
  note "PLAN (nothing has been changed yet)"
  if ((${#RP_IDS[@]} > 0 || WC_PLANNED)); then
    note "Raw data to download:"
    for id in "${RP_IDS[@]}"; do
      printf '      %-54s %s\n' "$(raw_label "$id")" "$(item_text "$id")"
      if [[ ${ITEM_EXACT[$id]} == 1 ]]; then exact=$((exact + ITEM_BYTES[$id])); else est=$((est + ITEM_BYTES[$id])); fi
    done
    if ((WC_PLANNED)); then
      printf '      %-54s %s\n' "ESA WorldCover tiles (fetched by step 19)" "about $(fmt_size $WC_BYTES)"; est=$((est + WC_BYTES))
    fi
    note "Total to download: about $(fmt_size "$DL_TOTAL")$( ((exact > 0)) && echo "   (exact $(fmt_size "$exact"), the rest estimated)")"
    [[ ${RUN_OFFLINE:-0} != 1 ]] || note "(RUN_OFFLINE=1: sizes are built-in estimates, no HTTP HEAD requests were made)"
  else note "Raw data: all present, nothing to download."; fi
  if ((${#PS_ID[@]} > 0 || NEED_IMPORT)); then
    note "Steps that will run (expected time from the log of earlier runs, else typical):"
    for i in "${!PS_ID[@]}"; do
      s=${PS_ID[$i]}
      printf '      %-4s %-26s %-14s %s\n' "$s" "${NAME[$s]:-}" "$(usual_text "$(exp_secs "$s")")" "${PS_WHY[$i]}"
    done
    if ((NEED_IMPORT)); then printf '      %-4s %-26s %-14s %s\n' "-" "Godot first-run import" "about 2 min" "game/.godot missing"; fi
    mins=$(((PLAN_TOTAL_S + 30) / 60))
    note "Expected total: about $mins min$( ((mins >= 120)) && echo " ($((mins / 60)) h $((mins % 60)) min)") (downloads depend on your connection)"
  else note "Pipeline: up to date."; fi
  return 0
}
plan_has_work() { ((${#RP_IDS[@]} > 0 || WC_PLANNED || ${#PS_ID[@]} > 0 || NEED_IMPORT)); }
