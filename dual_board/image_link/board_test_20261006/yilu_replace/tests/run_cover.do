onerror {quit -code 1}
if {![file exists work_yilu_cover]} {vlib work_yilu_cover}
vlog -work work_yilu_cover C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_bram32k.v C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_glbl.v
vlog -sv -work work_yilu_cover ../rtl/yilu_replace_20261006/song2_cover_rom.v ../rtl/yilu_replace_20261006/video_song_cover_overlay.v yilu_replace_20261006/tb_cover_rgb565.v
vsim -voptargs=+acc -onfinish stop -wlf yilu_replace_20261006/cover.wlf work_yilu_cover.tb_cover_rgb565 work_yilu_cover.glbl
log /tb_cover_rgb565/dut/hit_d
log /tb_cover_rgb565/dut/rom/bank
run -all
quit -code 0
