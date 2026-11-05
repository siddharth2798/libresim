# tools/run_stale.sh: decides which pipeline steps are stale. Sourced by run.sh (and by
# tools/test_run_sh.sh). Needs from the caller: STAMPS, HASHPY, OUT/IN/DEP/FORCE, note, dry.
#
# A step is stale when an output is missing, an upstream step ran, or an input changed.
# Inputs that are Python scripts are compared by code hash (tools/code_hash.py), stored in
# $STAMPS/<step>.hashes when the step completes, so comments and formatting never rebuild.
# All other inputs (raw data, json) are compared by file mtime against the step's stamp.
declare -A RAN=() NEWRAW=()   # RAN: steps that ran or will run this session; NEWRAW: step -> raw item about to be downloaded

mtime_newer() { [[ $1 -nt $2 ]]; }
expand() { local p; for p in $1; do compgen -G "$p" || true; done; }

newest_file() {  # newest regular file below dir $1 (empty if none); no GNU-only find options
  if [[ $(uname -s) == Darwin ]]; then find "$1" -type f -exec stat -f '%m %N' {} + 2>/dev/null
  else find "$1" -type f -exec stat -c '%Y %n' {} + 2>/dev/null; fi | sort -rn | sed -n 1p | cut -d' ' -f2-
}
ref_of() {  # file whose mtime stands for "when step $1 last completed"
  local s=$1 f best="" o
  [[ -f $STAMPS/$s.done ]] && { echo "$STAMPS/$s.done"; return; }
  for o in ${OUT[$s]}; do   # the newest output file marks when the step last finished
    if [[ -d $o ]]; then f=$(newest_file "$o"); else f=$o; fi
    if [[ -e $f ]] && { [[ -z $best ]] || [[ $f -nt $best ]]; }; then best=$f; fi
  done
  echo "$best"
}

# ---- script hashes
PYTAG=""
py_tag() { [[ -n $PYTAG ]] || PYTAG=$($HASHPY -I tools/code_hash.py --tag); echo "$PYTAG"; }
script_inputs() {  # the .py files among the inputs of step $1
  local f; for f in $(expand "${IN[$1]:-}"); do [[ $f == *.py ]] && echo "$f"; done; return 0
}
hash_lines() {  # "<hash>  <path>" for every script input of step $1
  local files; files=$(script_inputs "$1")
  [[ -z $files ]] || $HASHPY -I tools/code_hash.py $files
}
record_hashes() {  # remember the scripts a step was built from (call when the step completes)
  mkdir -p "$STAMPS"; { py_tag; hash_lines "$1"; } >"$STAMPS/$1.hashes"
}
script_changed() {  # prints the first script of step $1 whose code differs from the record
  local f=$STAMPS/$1.hashes h p
  [[ -f $f ]] || return 0
  while read -r h p; do grep -qxF "$h  $p" "$f" || { echo "$p"; return 0; }; done < <(hash_lines "$1")
  return 0
}
migrate_hashes() {  # a step with a stamp but no usable record: record the current scripts, never rebuild
  local s=$1 f=$STAMPS/$1.hashes
  [[ -f $STAMPS/$s.done ]] || return 0
  [[ -f $f && $(sed -n 1p "$f") == "$(py_tag)" ]] && return 0   # another Python writes other hashes: record again
  [[ -n $(script_inputs "$s") ]] || return 0
  dry && return 0
  record_hashes "$s"; note "recorded script hashes for step $s"
}

# ---- staleness
why_run() {  # prints a reason if step $1 must run, nothing if up to date
  local s=$1 o f d ref
  [[ -n ${FORCE[$s]:-} ]] && { echo "forced (--force-step)"; return; }
  for o in ${OUT[$s]}; do
    if [[ -d $o ]]; then [[ -n $(ls -A "$o" 2>/dev/null) ]] || { echo "output $o empty"; return; }
    else [[ -e $o ]] || { echo "output $o missing"; return; }; fi
  done
  [[ $s == 06 ]] && return     # committed outputs: only rebuilt when missing
  ref=$(ref_of "$s"); [[ -n $ref ]] || { echo "no output files"; return; }
  [[ -n ${NEWRAW[$s]:-} ]] && { echo "new raw data (${NEWRAW[$s]}) will be downloaded"; return; }
  for d in ${DEP[$s]:-}; do
    [[ -n ${RAN[$d]:-} ]] && { echo "upstream $d ran"; return; }
    [[ -f $STAMPS/$d.done && -f $STAMPS/$s.done ]] && mtime_newer "$STAMPS/$d.done" "$STAMPS/$s.done" && { echo "upstream $d is newer"; return; }
  done
  while IFS= read -r f; do
    [[ -n $f ]] || continue
    [[ $f == *.py && -f $STAMPS/$s.done ]] && continue   # scripts of a stamped step: code hash below
    mtime_newer "$f" "$ref" && { echo "$f is newer than last build"; return; }
  done < <(expand "${IN[$s]:-}")
  f=$(script_changed "$s")
  [[ -z $f ]] || echo "$f changed (code, not only comments)"
  return 0
}
