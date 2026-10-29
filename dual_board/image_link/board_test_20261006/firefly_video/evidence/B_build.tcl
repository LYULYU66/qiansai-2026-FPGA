# EXPERIMENTAL SRAM TEST ONLY. Known negative timing; not approved for flash/stable release.
import_device eagle_s20.db -package EG4S20BG256
open_project MEDIA_B_FIREFLY_VIDEO_20261006.al -single_run
set_param gate eram_init on
elaborate -top image_media_board_b
read_adc ../../rtl/dual_stars_20261006/media_b.adc
read_sdc ../../rtl/dual_stars_20261006/media_b.sdc
read_sdc -ip TEMAC_CORE ../../../ethernet_smoke/prj/board_a/al_ip/TEMAC_CORE/TEMAC_CORE.sdc
optimize_rtl
optimize_gate -packarea MEDIA_B_FIREFLY_VIDEO_20261006_gate.area
legalize_phy_inst
insert_debugger
set_param place seed 4
place
update_timing -mode manhattan
report_timing_summary -file MEDIA_B_FIREFLY_VIDEO_20261006_place.timing
route
report_area -io_info -file MEDIA_B_FIREFLY_VIDEO_20261006_phy.area
update_timing -mode final
report_timing_status -file MEDIA_B_FIREFLY_VIDEO_20261006_phy.ts
report_timing_summary -file MEDIA_B_FIREFLY_VIDEO_20261006_pr.timing

puts "WARNING: Engineering test bit only; routed timing is NOT closed. PROGRAM_SRAM only."
bitgen -bit MEDIA_B_FIREFLY_VIDEO_20261006.bit
