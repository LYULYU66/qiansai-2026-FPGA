onerror {quit -code 1}
if {![file exists home_capture_work]} {vlib home_capture_work}
vmap home_capture_work home_capture_work
vlog -work home_capture_work ../../../src/user_source/hdl_source/video_home_overlay.v ../../../src/user_source/hdl_source/video_album_cover_rom.v ../../../src/user_source/hdl_source/video_app_icons_rom.v tb_home_capture.v
vsim -t 1ps home_capture_work.tb_home_capture
run -all
quit -code 0
