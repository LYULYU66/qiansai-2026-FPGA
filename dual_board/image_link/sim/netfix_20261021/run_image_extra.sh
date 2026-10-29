#!/bin/bash
# Extra image-path tests. usage: run_image_extra.sh <lib> <rtl-dir-or-backup>
cd "$(dirname "$0")"
W=$1; R=${2:-../../rtl}; S=..
rm -rf $W; vlib $W >/dev/null
TX=$R/image_packet_tx_hw.v; [ -f $TX ] || TX=$R/hw_round5_20261005/image_packet_tx_hw.v
vlog -sv -work $W $R/image_receipt.v ../../rtl/image_packet_rx.v $R/image_sdram_sink.v ../../rtl/image_main_ingress.v \
   $TX $S/tb_cache_reuse.v $S/tb_image_reliable.v 2>&1 | grep -E "Error"
for top in tb_cache_reuse tb_cache_reuse_full tb_image_reliable tb_image_reliable_full tb_image_tagged_full tb_image_resolution; do
  printf "%-26s " $top; vsim -c -lib $W -do "run -all; quit -f" $W.$top 2>&1 | grep -E "PASS|FAIL|Fatal|Error:" | head -2 | tr '\n' ' '; echo
done
