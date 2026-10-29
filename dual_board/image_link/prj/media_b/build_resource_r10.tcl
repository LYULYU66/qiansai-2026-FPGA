# EXPERIMENTAL SRAM TEST ONLY. Known negative timing; not approved for flash/stable release.
import_device eagle_s20.db -package EG4S20BG256
open_project MEDIA_SRAM_TEST_B_RESOPT_R10_20261005.al -single_run
set_param gate eram_init on
elaborate -top image_media_board_b
read_adc ../../constraints/media_b.adc
read_sdc ../../constraints/media_b.sdc
read_sdc -ip TEMAC_CORE ../../../ethernet_smoke/prj/board_a/al_ip/TEMAC_CORE/TEMAC_CORE.sdc
optimize_rtl
optimize_gate -packarea MEDIA_SRAM_TEST_B_RESOPT_R10_20261005_gate.area
legalize_phy_inst
insert_debugger
set_param place seed 3
place
update_timing -mode manhattan
report_timing_summary -file MEDIA_SRAM_TEST_B_RESOPT_R10_20261005_place.timing
route
report_area -io_info -file MEDIA_SRAM_TEST_B_RESOPT_R10_20261005_phy.area
update_timing -mode final
report_timing_status -file MEDIA_SRAM_TEST_B_RESOPT_R10_20261005_phy.ts
report_timing_summary -file MEDIA_SRAM_TEST_B_RESOPT_R10_20261005_pr.timing

puts "WARNING: Engineering test bit only; routed timing is NOT closed. PROGRAM_SRAM only."
bitgen -bit MEDIA_SRAM_TEST_B_RESOPT_R10_20261005.bit
