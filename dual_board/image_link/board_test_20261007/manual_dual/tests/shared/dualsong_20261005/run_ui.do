onerror {quit -code 1}
if {![file exists work_dualsong_ui]} {vlib work_dualsong_ui}
vlog -work work_dualsong_ui C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_bram32k.v C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_glbl.v
vlog -sv -work work_dualsong_ui ../rtl/dualsong_20261005/dual_lyric_song_data.v ../rtl/dualsong_20261005/video_lyric_overlay.v ../rtl/dualsong_20261005/video_song_cover_overlay.v ../rtl/dualsong_20261005/song2_cover_rom.v dualsong_20261005/tb_dualsong_ui.v
vsim -voptargs=+acc -onfinish stop -wlf dualsong_20261005/ui.wlf work_dualsong_ui.tb_dualsong_ui work_dualsong_ui.glbl
log /tb_dualsong_ui/out_rgb
log /tb_dualsong_ui/cover_rgb
log /tb_dualsong_ui/lyric/cache_song
run -all
quit -code 0
