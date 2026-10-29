onerror {quit -code 1}
if {![file exists work_player_hw]} {vlib work_player_hw}
vlog -work work_player_hw C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_bram32k.v C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_glbl.v
vlog -sv -work work_player_hw ../rtl/image_packet_rx.v ../rtl/image_packet_tx.v ../rtl/image_receipt.v ../rtl/image_sdram_sink.v ../rtl/image_main_ingress.v tb_image_reliable.v
vlog -sv -work work_player_hw ../rtl/home_index_stream.v ../rtl/home_assets/home_atlas_rom.v ../rtl/home_assets/home_palette_rom.v ../rtl/video_remote_home_overlay.v ../../../src/user_source/hdl_source/video_home_overlay.v ../../../src/user_source/hdl_source/video_album_cover_rom.v ../../../src/user_source/hdl_source/video_app_icons_rom.v tb_home_atlas.v tb_home_pixels.v
vlog -sv -work work_player_hw ../../../src/user_source/hdl_source/SD/video_delay.v ../../../src/user_source/hdl_source/video_transition_effects.v ../../../src/user_source/hdl_source/video_image_adjust.v tb_home_pipeline.v
set sd_path ../../../src/user_source/hdl_source/SD
vlog -sv -work work_player_hw ../rtl/image_pixel_cdc.v ../rtl/image_tf_source.v ../rtl/sd_card_bmp_remote.v $sd_path/bmp_read.v $sd_path/bmp_bilinear_stream.v $sd_path/sd_card_top.v $sd_path/sd_card_sec_read_write.v $sd_path/sd_card_cmd.v $sd_path/spi_master.v $sd_path/ax_debounce.v tb_home_source.v
vsim -onfinish stop -wlf hw_20261005/home_atlas.wlf work_player_hw.tb_home_atlas work_player_hw.glbl
log /tb_home_atlas/dut/state
log /tb_home_atlas/dut/run_address
log /tb_home_atlas/dut/x
log /tb_home_atlas/dut/y
run -all
quit -sim
vsim -onfinish stop -wlf hw_20261005/home_pixels.wlf work_player_hw.tb_home_pixels
run -all
quit -sim
vsim -onfinish stop -wlf hw_20261005/image_tagged.wlf work_player_hw.tb_image_tagged_full
log /tb_image_tagged_full/u_full/received
log /tb_image_tagged_full/u_full/tx/byte_index
log /tb_image_tagged_full/u_full/tx_sequence
run -all
quit -sim
vsim -onfinish stop -wlf hw_20261005/home_pipeline.wlf work_player_hw.tb_home_pipeline work_player_hw.glbl
log /tb_home_pipeline/transition_index
log /tb_home_pipeline/adjusted_de
log /tb_home_pipeline/raw_word
log /tb_home_pipeline/output_rgb
run -all
quit -sim
vsim -onfinish stop -wlf hw_20261005/home_source.wlf work_player_hw.tb_home_source work_player_hw.glbl
log /tb_home_source/dut/source_count
log /tb_home_source/dut/u_home_indices/x
log /tb_home_source/dut/u_home_indices/y
log /tb_home_source/dut/pixel_ready
log /tb_home_source/received
run -all
quit -sim
