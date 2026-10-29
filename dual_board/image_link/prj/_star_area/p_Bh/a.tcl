import_device eagle_s20.db -package EG4S20BG256
read_verilog -file {top.v ../../../rtl/star_sky_20261020/star_motion_engine.v ../../../rtl/star_sky_20261020/media_control_star.v sky.v} -top star_area_top
optimize_rtl
optimize_gate
report_area -file g.area
exit
