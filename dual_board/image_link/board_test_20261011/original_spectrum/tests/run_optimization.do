onerror {quit -code 1}
set w work_stars_opt_equiv
if {![file exists $w]} {vlib $w}
set src ../../../src/user_source/hdl_source
vlog -work $w C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_bram32k.v C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_glbl.v
vlog -sv -work $w ../rtl/stars_opt_20261007/audio_visual_packet_hw.v ../rtl/stars_opt_20261007/remote_audio_compute_hw.v stars_opt_20261007/remote_compute_reference.v ../rtl/resource_round10_20261005/audio_waveform_analyzer.v $src/audio_spectrum_analyzer.v ../rtl/yilu_replace_20261006/audio_lyric_timeline.v ../rtl/yilu_replace_20261006/dual_lyric_song_data.v stars_opt_20261007/tb_compute_equivalence.v stars_opt_20261007/tb_shared_snapshot.v
vsim -onfinish stop $w.tb_shared_snapshot
run -all
quit -sim
vsim -onfinish stop -wlf stars_opt_20261007/equivalence.wlf $w.tb_compute_equivalence $w.glbl
log /tb_compute_equivalence/analysed_new
log /tb_compute_equivalence/ready_new
run -all
quit -code 0
