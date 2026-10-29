import_device eagle_s20.db -package EG4S20BG256
open_project IMAGE_LINK_A.al -single_run
elaborate -top image_link_board_a
read_adc ../../constraints/board_a.adc
read_sdc ../../../ethernet_smoke/source_code/constraints/smoke.sdc
read_sdc -ip TEMAC_CORE ../../../ethernet_smoke/prj/board_a/al_ip/TEMAC_CORE/TEMAC_CORE.sdc
optimize_rtl
optimize_gate -packarea IMAGE_LINK_A_gate.area
