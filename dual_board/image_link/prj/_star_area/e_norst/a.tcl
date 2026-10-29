import_device eagle_s20.db -package EG4S20BG256
read_verilog -file {star_area_top.v eng.v ctl.v sky.v} -top star_area_top
optimize_rtl
optimize_gate
report_area -file g.area
exit
