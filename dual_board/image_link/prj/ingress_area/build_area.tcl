import_device eagle_s20.db -package EG4S20BG256
open_project ingress_area.al -single_run
elaborate -top image_main_ingress
optimize_rtl
optimize_gate -packarea ingress_area_gate.area
