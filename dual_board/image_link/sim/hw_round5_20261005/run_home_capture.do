onerror {quit -code 1}
if {![file exists work_player_round5]} {vlib work_player_round5}
vlog -sv -work work_player_round5 ../rtl/hw_round4_20261005/player_domain_reset.v
onerror {quit -code 1}
if {![file exists home_capture_work]} {vlib home_capture_work}
vmap home_capture_work home_capture_work
vlog -work home_capture_work ../../../src/user_source/hdl_source/video_home_overlay.v ../../../src/user_source/hdl_source/video_album_cover_rom.v ../../../src/user_source/hdl_source/video_app_icons_rom.v tb_home_capture.v
vsim -t 1ps home_capture_work.tb_home_capture
run -all
quit -code 0
