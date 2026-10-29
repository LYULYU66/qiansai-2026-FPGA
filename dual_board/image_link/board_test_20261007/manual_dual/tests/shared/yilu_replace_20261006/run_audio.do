onerror {quit -code 1}
if {![file exists work_yilu_audio]} {vlib work_yilu_audio}
vlog -work work_yilu_audio C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_bram32k.v C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_glbl.v
vlog -sv -work work_yilu_audio ../rtl/hw_round4_20261005/player_domain_reset.v ../rtl/image_packet_rx.v ../rtl/hw_round5_20261005/image_packet_tx_hw.v ../rtl/image_receipt.v ../rtl/audio_packet_tx.v ../rtl/audio_packet_rx.v ../rtl/dualsong_20261005/audio_receipt_b.v ../rtl/media_udp_arbiter.v ../rtl/hw_round4_20261005/audio_visual_packet_hw.v ../rtl/yilu_replace_20261006/remote_audio_compute_hw.v ../rtl/media_control_packet.v
set source_path ../../../src/user_source/hdl_source
vlog -sv -work work_yilu_audio $source_path/IP/afifo_32_16_256.v $source_path/hdmi_audio_pcm_i2s_64fs.v ../rtl/resource_round10_20261005/audio_waveform_analyzer.v $source_path/audio_spectrum_analyzer.v ../rtl/yilu_replace_20261006/audio_lyric_timeline.v ../rtl/yilu_replace_20261006/dual_lyric_song_data.v tb_audio_offload.v tb_remote_compute.v tb_audio_visual_guard.v tb_audio_status_guard.v
foreach test {tb_audio_status_guard tb_audio_visual_guard tb_remote_compute tb_audio_offload} {
    vsim -voptargs=+acc -onfinish stop -wlf yilu_replace_20261006/${test}.wlf work_yilu_audio.$test work_yilu_audio.glbl
    log /$test/rst
    run -all
    quit -sim
}
quit -code 0
