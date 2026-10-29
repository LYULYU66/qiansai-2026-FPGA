# Run from the project's phy_1 directory, after a completed routed build.
import_device eagle_s20.db -package EG4S20BG256
open_project lab_ex5_i2s_v1.0.prj -noanalyze
import_db lab_ex5_i2s_v1.0_pr.db
fix_hold
fix_hold -buffer_opt
fix_hold
update_timing -mode final
report_area -io_info -file lab_ex5_i2s_v1.0_phy.area
report_timing_summary -file lab_ex5_i2s_v1.0_pr.timing
export_db lab_ex5_i2s_v1.0_pr.db
bitgen -bit lab_ex5_i2s_v1.0.bit
