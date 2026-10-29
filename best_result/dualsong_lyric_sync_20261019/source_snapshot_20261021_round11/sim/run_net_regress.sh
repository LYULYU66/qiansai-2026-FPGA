#!/bin/bash
# Network-stack regression on the production RTL used by both boards.
# usage: run_net_regress.sh <work-lib-name>
cd "$(dirname "$0")"
R=../../rtl; S=..; H=../../../../src/user_source/hdl_source
W=${1:-w_net}
rm -rf $W; vlib $W >/dev/null
ok=1
v(){ vlog -sv -work $W "$@" 2>&1 | grep -E "Error|error" && ok=0; }
v $R/fixed_peer_udp.v $R/media_udp_arbiter.v $R/media_link_session.v $R/image_receipt.v \
  $R/image_packet_rx.v $R/image_sdram_sink.v $R/image_main_ingress.v $R/audio_packet_rx.v \
  $R/audio_packet_tx.v $R/hw_round5_20261005/image_packet_tx_hw.v \
  $R/dualsong_20261005/audio_receipt_a.v $R/media_audio_enable_cdc.v \
  $R/star_sky_20261020/media_control_star.v
v $H/IP/afifo_32_16_256.v $H/hdmi_audio_pcm_i2s_64fs.v
v $S/fixed_udp_test_link.v
for t in $S/tb_fixed_peer_udp.v $S/tb_media_scheduler.v $S/startup_fix_20261008/tb_scheduler_lock.v \
         $S/tb_link_session.v $S/tb_image_sink_guard.v \
         ../subtitle_20261021/tb_ctl4_receipt_20261021.v; do
    v $t
done
# Restart test: two complete fixed-peer stacks over the test link, with the
# older audio receipt interface it was written for.
W2=${W}_restart; rm -rf $W2; vlib $W2 >/dev/null
vlog -sv -work $W2 $R/fixed_peer_udp.v $R/media_udp_arbiter.v $R/media_link_session.v $R/image_receipt.v   $R/image_packet_rx.v $R/image_sdram_sink.v $R/image_main_ingress.v $R/audio_packet_rx.v $R/audio_packet_tx.v   $R/hw_round5_20261005/image_packet_tx_hw.v $R/audio_receipt.v $R/media_audio_enable_cdc.v   $H/IP/afifo_32_16_256.v $H/hdmi_audio_pcm_i2s_64fs.v $S/fixed_udp_test_link.v $S/tb_media_restart.v 2>&1 | grep -E "Error" && ok=0
run(){ L=${2:-$W}; printf "%-32s " $1; vsim -c -lib $L -do "run -all; quit -f" $L.$1 2>&1 | grep -E "PASS|FAIL|Fatal|Error:|ERR" | head -3 | tr '\n' ' '; echo; }
for top in tb_fixed_peer_udp tb_fixed_peer_udp_pair tb_media_scheduler tb_scheduler_lock tb_link_session \
           tb_image_sink_guard tb_ctl4_receipt_20261021; do run $top; done
run tb_media_restart_fixed $W2
