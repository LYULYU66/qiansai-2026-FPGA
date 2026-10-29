# EXPERIMENTAL SRAM TEST ONLY. Known negative timing; not approved for flash/stable release.
set player_project_dir [pwd]
import_device eagle_s20.db -package EG4S20BG256
open_project MEDIA_SRAM_TEST_A_IMAGEFIX_R7_20261005.al -single_run
set_param gate eram_init on
# Preserve original includes/readmemh relative to src/td_project.
cd ../../../../src/td_project
elaborate -top top_dual_image
cd $player_project_dir
read_adc ../../constraints/media_a.adc
read_sdc ../../constraints/media_a.sdc
read_sdc -ip TEMAC_CORE ../../../ethernet_smoke/prj/board_a/al_ip/TEMAC_CORE/TEMAC_CORE.sdc
optimize_rtl
optimize_gate -packarea MEDIA_SRAM_TEST_A_IMAGEFIX_R7_20261005_gate.area
legalize_phy_inst
insert_debugger
set_param place seed 3
place
update_timing -mode manhattan
report_timing_summary -file MEDIA_SRAM_TEST_A_IMAGEFIX_R7_20261005_place.timing
route
report_area -io_info -file MEDIA_SRAM_TEST_A_IMAGEFIX_R7_20261005_phy.area
update_timing -mode final
report_timing_status -file MEDIA_SRAM_TEST_A_IMAGEFIX_R7_20261005_phy.ts
report_timing_summary -file MEDIA_SRAM_TEST_A_IMAGEFIX_R7_20261005_pr.timing

puts "WARNING: Engineering test bit only; routed timing is NOT closed. PROGRAM_SRAM only."
bitgen -bit MEDIA_SRAM_TEST_A_IMAGEFIX_R7_20261005.bit
