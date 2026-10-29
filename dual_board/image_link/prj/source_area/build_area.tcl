import_device eagle_s20.db -package EG4S20BG256
open_project source_area.al -single_run
elaborate -top image_tf_source
optimize_rtl
optimize_gate -packarea source_area_gate.area
