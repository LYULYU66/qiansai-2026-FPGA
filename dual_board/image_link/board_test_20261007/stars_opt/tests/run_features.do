onerror {quit -code 1}
if {![file exists work_stars_opt_features]} {vlib work_stars_opt_features}
if {![file exists work_stars_opt_rx]} {vlib work_stars_opt_rx}
vmap song_b work_stars_opt_rx
vlog -sv -work work_stars_opt_features dualsong_20261005/audio_receipt_b_test.v
vlog -work work_stars_opt_features C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_bram32k.v C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_glbl.v
vlog -sv -work work_stars_opt_features ../rtl/dualsong_20261005/sd_card_bmp_remote.v ../rtl/dualsong_20261005/audio_receipt_a.v ../rtl/yilu_replace_20261006/audio_lyric_timeline.v ../rtl/yilu_replace_20261006/dual_lyric_song_data.v dualsong_20261005/tb_dualsong_control.v yilu_replace_20261006/tb_dualsong_timeline.v
vsim -voptargs=+acc -onfinish stop -wlf yilu_replace_20261006/control.wlf work_stars_opt_features.tb_dualsong_control
log -r /*
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf yilu_replace_20261006/timeline.wlf work_stars_opt_features.tb_dualsong_timeline work_stars_opt_features.glbl
log -r /*
run -all
quit -code 0
