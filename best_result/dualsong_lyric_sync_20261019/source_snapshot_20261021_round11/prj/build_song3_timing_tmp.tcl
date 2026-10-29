# EXPERIMENTAL SRAM TEST ONLY. Known negative timing; not approved for flash/stable release.
set player_project_dir [pwd]
import_device eagle_s20.db -package EG4S20BG256
open_project MEDIA_SRAM_TEST_A_SONG3_20261011.al -single_run
set_param gate eram_init on
# Preserve original includes/readmemh relative to src/td_project.
cd ../../../../src/td_project
elaborate -top top_dual_image
cd $player_project_dir
read_adc C:/FPGA2026/HX4S20_Contest_2026/7_lab_ex_2026_nosoft/qiansai/lab_ex4_tf/best_result/dualsong_lyric_sync_20261019/source_snapshot_final_20261020/rtl/media_a.adc
read_sdc C:/FPGA2026/HX4S20_Contest_2026/7_lab_ex_2026_nosoft/qiansai/lab_ex4_tf/best_result/dualsong_lyric_sync_20261019/source_snapshot_20261021_round11/rtl/a/media_a.sdc
read_sdc -ip TEMAC_CORE C:/FPGA2026/HX4S20_Contest_2026/7_lab_ex_2026_nosoft/qiansai/lab_ex4_tf/dual_board/ethernet_smoke/prj/board_a/al_ip/TEMAC_CORE/TEMAC_CORE.sdc
optimize_rtl
optimize_gate -packarea MEDIA_SRAM_TEST_A_SONG3_20261011_gate.area
legalize_phy_inst
insert_debugger
# 20261021 round 11 (62.5 MHz udp_clk): seed 3.
set_param place seed 1
place
update_timing -mode manhattan
report_timing_summary -file MEDIA_SRAM_TEST_A_SONG3_20261011_place.timing
set_param route fix_hold off
route
report_area -io_info -file MEDIA_SRAM_TEST_A_SONG3_20261011_phy.area
update_timing -mode final
report_timing_status -file MEDIA_SRAM_TEST_A_SONG3_20261011_phy.ts
report_timing_summary -file MEDIA_SRAM_TEST_A_SONG3_20261011_pr.timing

puts "WARNING: Engineering test bit only; routed timing is NOT closed. PROGRAM_SRAM only."
bitgen -bit MEDIA_SRAM_TEST_A_SONG3_20261011.bit



