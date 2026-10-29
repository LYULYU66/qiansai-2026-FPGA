# EXPERIMENTAL SRAM TEST ONLY. Known negative timing; not approved for flash/stable release.
import_device eagle_s20.db -package EG4S20BG256
open_project MEDIA_B_HDMI_IMAGE3_20261006.al -single_run
set_param gate eram_init on
elaborate -top image_media_board_b
read_adc C:/FPGA2026/HX4S20_Contest_2026/7_lab_ex_2026_nosoft/qiansai/lab_ex4_tf/best_result/dualsong_lyric_sync_20261019/source_snapshot_20261021_round11/rtl/b/media_b.adc
read_sdc C:/FPGA2026/HX4S20_Contest_2026/7_lab_ex_2026_nosoft/qiansai/lab_ex4_tf/best_result/dualsong_lyric_sync_20261019/source_snapshot_20261021_round11/rtl/b/media_b.sdc
read_sdc -ip TEMAC_CORE C:/FPGA2026/HX4S20_Contest_2026/7_lab_ex_2026_nosoft/qiansai/lab_ex4_tf/dual_board/ethernet_smoke/prj/board_b/al_ip/TEMAC_CORE/TEMAC_CORE.sdc
optimize_rtl
optimize_gate -packarea MEDIA_B_HDMI_IMAGE3_20261006_gate.area
legalize_phy_inst
insert_debugger
# 20261021 round 11 (62.5 MHz udp_clk): seed 3.
# 20261021: split the 2599-fanout TF reset (and other huge nets) during placement.
set_param place max_fanout 600
set_param place seed 1
place
update_timing -mode manhattan
report_timing_summary -file MEDIA_B_HDMI_IMAGE3_20261006_place.timing
# 20261021: B is ~96% placed; use the congestion-avoiding router.
set_param route effort routability
route
report_area -io_info -file MEDIA_B_HDMI_IMAGE3_20261006_phy.area
update_timing -mode final
report_timing_status -file MEDIA_B_HDMI_IMAGE3_20261006_phy.ts
report_timing_summary -file MEDIA_B_HDMI_IMAGE3_20261006_pr.timing

puts "WARNING: Engineering test bit only; routed timing is NOT closed. PROGRAM_SRAM only."
bitgen -bit MEDIA_B_HDMI_IMAGE3_20261006.bit

