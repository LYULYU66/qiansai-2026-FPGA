import_device eagle_s20.db -package EG4S20BG256
open_project FIXED_UDP_HW_B.al -single_run
set_param gate eram_init on
elaborate -top fixed_udp_hw_b
read_adc ../../constraints/board_b.adc
read_sdc ../../../ethernet_smoke/source_code/constraints/smoke.sdc
read_sdc -ip TEMAC_CORE ../../../ethernet_smoke/prj/board_a/al_ip/TEMAC_CORE/TEMAC_CORE.sdc
optimize_rtl
optimize_gate -packarea FIXED_UDP_HW_B_gate.area
legalize_phy_inst
insert_debugger
set_param place seed 1
place
update_timing -mode manhattan
report_timing_summary -file FIXED_UDP_HW_B_place.timing
route
report_area -io_info -file FIXED_UDP_HW_B_phy.area
update_timing -mode final
report_timing_status -file FIXED_UDP_HW_B_phy.ts
report_timing_summary -file FIXED_UDP_HW_B_pr.timing
bitgen -bit FIXED_UDP_HW_B_20261005.bit
