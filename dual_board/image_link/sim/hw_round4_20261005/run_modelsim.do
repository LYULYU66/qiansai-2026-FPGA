onerror {quit -code 1}
if {![file exists work_player_round4]} {vlib work_player_round4}
vlog -sv -work work_player_round4 ../rtl/hw_round4_20261005/player_domain_reset.v
onerror {quit -code 1}
if {![file exists work_player_round4]} {vlib work_player_round4}
vlog -sv -work work_player_round4 ../rtl/image_packet_rx.v ../rtl/image_packet_tx.v ../rtl/image_receipt.v ../rtl/image_sdram_sink.v ../rtl/image_main_ingress.v ../rtl/image_pixel_cdc.v ../rtl/hw_round4_20261005/image_tf_source_hw.v tb_image_packet_rx.v tb_image_link_loop.v tb_image_link_full.v tb_image_reliable.v tb_image_pixel_cdc.v
vlog -sv -work work_player_round4 tb_image_sink_guard.v
vlog -sv -work work_player_round4 ../rtl/image_remote_display_control.v tb_remote_display.v
vlog -sv -work work_player_round4 ../rtl/audio_packet_tx.v ../rtl/audio_packet_rx.v ../rtl/hw_20261005/audio_receipt_hw.v ../rtl/media_udp_arbiter.v ../../../src/user_source/hdl_source/IP/afifo_32_16_256.v ../../../src/user_source/hdl_source/hdmi_audio_pcm_i2s_64fs.v tb_audio_media.v tb_audio_guard.v
set sd_path ../../../src/user_source/hdl_source/SD
vlog -work work_player_round4 C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_bram32k.v C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_glbl.v
vlog -work work_player_round4 ../rtl/hw_round2_20261005/home_index_stream_hw.v ../rtl/home_assets/home_atlas_rom.v
vlog -sv -work work_player_round4 ../rtl/sd_card_bmp_remote.v $sd_path/bmp_read.v $sd_path/bmp_bilinear_stream.v $sd_path/sd_card_top.v $sd_path/sd_card_sec_read_write.v $sd_path/sd_card_cmd.v $sd_path/spi_master.v $sd_path/ax_debounce.v
vsim -onfinish stop work_player_round4.image_tf_source work_player_round4.glbl
run 0 ns
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf hw_round4_20261005/packet_rx.wlf work_player_round4.tb_image_packet_rx
log -r /*
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf hw_round4_20261005/image_link_full.wlf work_player_round4.tb_image_link_full
log /tb_image_link_full/u_full_frame/source_count
log /tb_image_link_full/u_full_frame/received_count
log /tb_image_link_full/u_full_frame/frame_start
log /tb_image_link_full/u_full_frame/frame_complete
log /tb_image_link_full/u_full_frame/frame_abort
log /tb_image_link_full/u_full_frame/good_packets
log /tb_image_link_full/u_full_frame/bad_packets
log /tb_image_link_full/u_full_frame/tx/sequence_no
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf hw_round4_20261005/image_pixel_cdc.wlf work_player_round4.tb_image_pixel_cdc
log -r /*
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf hw_round4_20261005/image_reliable.wlf work_player_round4.tb_image_reliable_full
log /tb_image_reliable_full/u_full/main/u_sink/state
log /tb_image_reliable_full/u_full/main/cache_valid
log /tb_image_reliable_full/u_full/main/write_abort
log /tb_image_reliable_full/u_full/main/commit_toggle
log /tb_image_reliable_full/u_full/received
log /tb_image_reliable_full/u_full/transmissions
log /tb_image_reliable_full/u_full/tx_sequence
log /tb_image_reliable_full/u_full/receipt_valid
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf hw_round4_20261005/image_sink_guard.wlf work_player_round4.tb_image_sink_guard
log -r /*
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf hw_round4_20261005/remote_display.wlf work_player_round4.tb_remote_display
log -r /*
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf hw_round4_20261005/audio_guard.wlf work_player_round4.tb_audio_guard
log -r /*
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf hw_round4_20261005/media_abort.wlf work_player_round4.tb_media_abort
log -r /*
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf hw_round4_20261005/audio_media.wlf work_player_round4.tb_audio_media
log /tb_audio_media/played_words
log /tb_audio_media/fifo_used
log /tb_audio_media/fifo_rdused
log /tb_audio_media/pcm_read
log /tb_audio_media/playing
log /tb_audio_media/underflow
log /tb_audio_media/blackout
log /tb_audio_media/rx/state
log /tb_audio_media/a_sequence
log /tb_audio_media/reported_progress
run -all
quit -sim
do hw_round4_20261005/run_offload_modelsim.do
do hw_round4_20261005/run_home_modelsim.do
do hw_round4_20261005/run_control_modelsim.do
do hw_round4_20261005/run_link_modelsim.do
do hw_round4_20261005/run_reuse_modelsim.do
do hw_round4_20261005/run_netopt_modelsim.do
do hw_round4_20261005/run_fixed_udp_modelsim.do
quit -code 0
