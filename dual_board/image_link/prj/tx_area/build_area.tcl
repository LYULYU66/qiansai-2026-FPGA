import_device eagle_s20.db -package EG4S20BG256
open_project image_tx_area.al -single_run
elaborate -top image_packet_tx
optimize_rtl
optimize_gate -packarea image_tx_gate.area
