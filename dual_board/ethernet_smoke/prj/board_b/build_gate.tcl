import_device eagle_s20.db -package EG4S20BG256
open_project DUAL_SMOKE_B.al -single_run
elaborate -top dual_board_smoke_b
read_adc ../../source_code/constraints/smoke.adc
read_sdc ../../source_code/constraints/smoke.sdc
read_sdc -ip TEMAC_CORE al_ip/TEMAC_CORE/TEMAC_CORE.sdc
optimize_rtl
optimize_gate -packarea DUAL_SMOKE_B_gate.area
legalize_phy_inst
update_timing
report_timing_summary -file DUAL_SMOKE_B_gate.timing
