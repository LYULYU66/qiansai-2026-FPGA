# Optional native routing ECO, from phy_lyrics_smooth_20261001 after bitgen.
# Keep the original routed DB/bit intact. Do not change HDL or constraints.
import_device eagle_s20.db -package EG4S20BG256
open_project lab_ex5_i2s_v1.0.prj -noanalyze
import_db lab_ex5_i2s_v1.0_pr.db
foreach target_net {{u_video_transition_effects/O_read_idx_b[1]} {u_video_transition_effects/O_read_idx_b[0]} {u_video_transition_effects/transition_pending} {frame_read_write_m0/read_req} {display_valid_frame}} {
    fix_hold -net $target_net -buffer_opt
}
fix_hold
update_timing -mode final
report_area -io_info -file lab_ex5_i2s_v1.0_holdfix.area
report_timing_summary -file lab_ex5_i2s_v1.0_holdfix.timing
report_timing_status -file lab_ex5_i2s_v1.0_holdfix.ts
export_db lab_ex5_i2s_v1.0_holdfix.db
bitgen -bit lab_ex5_i2s_v1.0_holdfix.bit
exit
