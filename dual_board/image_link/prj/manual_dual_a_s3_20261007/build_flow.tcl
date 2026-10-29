# EXPERIMENTAL SRAM TEST ONLY. Known negative timing; not approved for flash/stable release.
set player_project_dir [pwd]
import_device eagle_s20.db -package EG4S20BG256
open_project MEDIA_A_MANUAL_DUAL_S3_20261007.al -single_run
set_param gate eram_init on
# Preserve original includes/readmemh relative to src/td_project.
cd ../../../../src/td_project
elaborate -top top_dual_image
cd $player_project_dir
read_adc ../../rtl/dualsong_20261005/media_a.adc
read_sdc ../../constraints/media_a.sdc
read_sdc -ip TEMAC_CORE ../../../ethernet_smoke/prj/board_a/al_ip/TEMAC_CORE/TEMAC_CORE.sdc
optimize_rtl
optimize_gate -packarea MEDIA_A_MANUAL_DUAL_S3_20261007_gate.area
legalize_phy_inst
insert_debugger
set_param place seed 3
place
update_timing -mode manhattan
report_timing_summary -file MEDIA_A_MANUAL_DUAL_S3_20261007_place.timing
route
report_area -io_info -file MEDIA_A_MANUAL_DUAL_S3_20261007_phy.area
update_timing -mode final
report_timing_status -file MEDIA_A_MANUAL_DUAL_S3_20261007_phy.ts
report_timing_summary -file MEDIA_A_MANUAL_DUAL_S3_20261007_pr.timing

puts "WARNING: Engineering test bit only; routed timing is NOT closed. PROGRAM_SRAM only."
bitgen -bit MEDIA_A_MANUAL_DUAL_S3_20261007.bit
