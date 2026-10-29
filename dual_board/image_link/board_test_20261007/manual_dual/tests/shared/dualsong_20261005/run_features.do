onerror {quit -code 1}
if {![file exists work_dualsong_features]} {vlib work_dualsong_features}
if {![file exists work_dualsong_rx]} {vlib work_dualsong_rx}
vmap song_b work_dualsong_rx
vlog -sv -work work_dualsong_features dualsong_20261005/audio_receipt_b_test.v
vlog -work work_dualsong_features C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_bram32k.v C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_glbl.v
vlog -sv -work work_dualsong_features ../rtl/dualsong_20261005/sd_card_bmp_remote.v ../rtl/dualsong_20261005/audio_receipt_a.v ../rtl/dualsong_20261005/audio_lyric_timeline.v ../rtl/dualsong_20261005/dual_lyric_song_data.v dualsong_20261005/tb_dualsong_control.v dualsong_20261005/tb_dualsong_timeline.v
vsim -voptargs=+acc -onfinish stop -wlf dualsong_20261005/control.wlf work_dualsong_features.tb_dualsong_control
log -r /*
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop -wlf dualsong_20261005/timeline.wlf work_dualsong_features.tb_dualsong_timeline work_dualsong_features.glbl
log -r /*
run -all
quit -code 0
