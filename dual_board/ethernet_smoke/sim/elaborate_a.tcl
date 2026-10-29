import_device eagle_s20.db -package EG4S20BG256
open_project ../prj/board_a/DUAL_SMOKE_A.al -single_run
elaborate -top dual_board_smoke_a
report_area -file smoke_a_elaborate.area
