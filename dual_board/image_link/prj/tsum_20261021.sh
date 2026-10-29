#!/bin/sh
# Negative-slack clock groups (SDRAM shift-clock groups excluded by user decision).
awk '/^Path Group     :/{g=$0; sub(/^Path Group     : +/,"",g)} /^Max            :/{s=$4; sv=$7} /^Min            :/{h=$4; hv=$7; if ((s+0<0 || h+0<0) && g !~ /mem_shift|ext_mem/) printf "   %-34s S %9s (%s viol)  H %9s (%s viol)\n", g, s, sv, h, hv}' "$1"
