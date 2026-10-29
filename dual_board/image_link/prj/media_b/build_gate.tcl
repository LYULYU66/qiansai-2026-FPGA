import_device eagle_s20.db -package EG4S20BG256
open_project MEDIA_SOURCE_B.al -single_run
set_param gate eram_init on
elaborate -top image_media_board_b
optimize_rtl
optimize_gate -packarea MEDIA_SOURCE_B_gate.area
