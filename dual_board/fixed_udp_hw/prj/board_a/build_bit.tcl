import_device eagle_s20.db -package EG4S20BG256
open_project FIXED_UDP_HW_A.al -single_run
set_param gate eram_init on
elaborate -top fixed_udp_hw_a
read_adc ../../constraints/board_a.adc
read_sdc ../../../ethernet_smoke/source_code/constraints/smoke.sdc
read_sdc -ip TEMAC_CORE ../../../ethernet_smoke/prj/board_a/al_ip/TEMAC_CORE/TEMAC_CORE.sdc
optimize_rtl
optimize_gate -packarea FIXED_UDP_HW_A_gate.area
legalize_phy_inst
insert_debugger
set_param place seed 7
place
update_timing -mode manhattan
report_timing_summary -file FIXED_UDP_HW_A_place.timing
route
report_area -io_info -file FIXED_UDP_HW_A_phy.area
update_timing -mode final
report_timing_status -file FIXED_UDP_HW_A_phy.ts
report_timing_summary -file FIXED_UDP_HW_A_pr.timing
bitgen -bit FIXED_UDP_HW_A_20261005.bit
