#!/usr/bin/env bash
# Every path the Quartus project names has to exist. A typo in a qip costs a
# whole fit to find out about otherwise, and a fit is 17 to 35 minutes on a
# runner that somebody else is waiting for.
#
#   tools/check/project.sh
#
# grep, not rg: the CI runner has no ripgrep.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

rc=0
fail() { echo "FAIL: $*" >&2; rc=1; }

n=0

# Resolve one qip: entries name paths relative to the qip's own directory.
check_qip() {
  local qip="$1" dir
  dir="$(dirname "$qip")"
  [[ -f "$qip" ]] || { fail "no such qip: $qip"; return; }

  local line path
  while read -r path; do
    [[ -n "$path" ]] || continue
    if [[ -f "$dir/$path" ]]; then
      n=$((n + 1))
      case "$path" in
        *.qip) check_qip "$dir/$path" ;;
      esac
    else
      fail "$qip names $path, which does not exist"
    fi
  # Source assignments only. A qip also carries MISC_FILE and IP_* metadata
  # naming files the IP generator never wrote, which Quartus ignores.
  done < <(grep -E '(QIP_FILE|SDC_FILE|SIP_FILE|VERILOG_FILE|SYSTEMVERILOG_FILE|VHDL_FILE|MIF_FILE)' "$qip" \
           | grep -oE '\[file join \$::quartus\(qip_path\) "?[^]"]+"?[[:space:]]*\]' \
           | sed -E 's/.*qip_path\)[[:space:]]*"?//; s/"?[[:space:]]*\]$//')
}

QSF=projects/gg_pocket.qsf
[[ -f "$QSF" ]] || { echo "no $QSF" >&2; exit 1; }

# The revision the Makefile and the harness build has to be the one the project
# declares, or `make gg` compiles nothing.
rev=$(sed -n 's/^PROJECT_REVISION = "\(.*\)"/\1/p' projects/gg_pocket.qpf)
[[ "$rev" == "gg_pocket" ]] || fail "gg_pocket.qpf declares revision '$rev'"
grep -q '^REV *?*= *gg_pocket' Makefile || fail "the Makefile's REV does not match the project revision"

# Paths the qsf names directly, relative to projects/.
while read -r path; do
  [[ -n "$path" ]] || continue
  if [[ -f "projects/$path" ]]; then
    n=$((n + 1))
    case "$path" in
      *.qip) check_qip "projects/$path" ;;
    esac
  else
    fail "$QSF names $path, which does not exist"
  fi
done < <(grep -oE '(QIP_FILE|SDC_FILE|VERILOG_FILE|SYSTEMVERILOG_FILE|VHDL_FILE|MIF_FILE) [^ ]+$' "$QSF" | awk '{print $2}')

# pocket.tcl is sourced rather than assigned, and it is what brings in the APF
# framework and this core's own file list.
while read -r path; do
  [[ -n "$path" ]] || continue
  if [[ -f "projects/$path" ]]; then
    n=$((n + 1))
    check_qip "projects/$path"
  else
    fail "pocket.tcl names $path, which does not exist"
  fi
done < <(grep -oE 'QIP_FILE [^ ]+$' platform/pocket/pocket.tcl | awk '{print $2}')

# system.vhd loads the boot ROM from the literal path "rtl/mboot.mif", resolved
# against the project directory. projects/rtl is the symlink that answers it.
[[ -f projects/rtl/mboot.mif ]] || fail "projects/rtl/mboot.mif does not resolve; the symlink to ../rtl/upstream is missing"
[[ -f projects/rtl/nvram_ff.mif ]] || fail "projects/rtl/nvram_ff.mif does not resolve"

# The one file rtl/upstream carries that the project must NOT pick up: SMS.sv
# is MiSTer's top level and rtl/gg/gg_core.sv replaces it.
grep -v '^[[:space:]]*#' rtl/gg.qip | grep -q 'SMS\.sv' \
  && fail "rtl/gg.qip lists SMS.sv; gg_core.sv replaces it"

[[ $rc -eq 0 ]] && echo "project ok: $n source paths resolve from $QSF"
exit $rc
