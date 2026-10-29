import_device eagle_s20.db -package EG4S20BG256
read_verilog -file {top.v ../../../rtl/star_sky_20261020/star_motion_engine.v} -top probe_top
optimize_rtl
optimize_gate
read_sdc p.sdc
report_timing_exception -file exc.txt
exit
