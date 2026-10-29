#!/bin/sh
# Image ingress/sink regressions used for the 20261019 timing fix.
# usage: run_sink_fix_20261019.sh LIB   (fresh ModelSim library name)
L=$1; rm -rf $L; vlib $L >/dev/null
R=../rtl
vlog -sv -work $L $R/image_packet_rx.v $R/image_packet_tx.v $R/image_receipt.v $R/image_sdram_sink.v $R/image_main_ingress.v \
  $R/audio_visual_packet.v tb_image_reliable.v tb_resolution_guard.v tb_resolution_display.v tb_image_sink_guard.v tb_cache_reuse.v 2>&1 | grep -iE "error|warning" 
vlog -sv -work $L $R/media_link_session.v $R/media_udp_arbiter.v $R/audio_packet_rx.v tb_link_session.v tb_media_generation.v 2>&1 | grep -iE "error|warning"
for t in $(grep -ho "^module tb_[a-z_0-9]*" tb_image_reliable.v tb_resolution_guard.v tb_resolution_display.v tb_image_sink_guard.v tb_cache_reuse.v tb_media_generation.v | sed 's/module //'); do
  printf "%-32s " $t
  vsim -c -lib $L -do "run -all; quit -f" $L.$t 2>&1 | grep -E "PASS|FAIL|Fatal|Error:" | head -2 | tr '\n' ' '; echo
done
