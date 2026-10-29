import_device eagle_s20.db -package EG4S20BG256
open_project MEDIA_IMAGE_A.al -single_run
set_param gate eram_init on
cd ../../../../src/td_project
elaborate -top top_dual_image
optimize_rtl
optimize_gate -packarea ../../dual_board/image_link/prj/media_a/MEDIA_IMAGE_A_gate.area
