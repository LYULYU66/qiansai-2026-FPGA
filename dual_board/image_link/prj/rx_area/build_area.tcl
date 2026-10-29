import_device eagle_s20.db -package EG4S20BG256
open_project image_rx_area.al -single_run
elaborate -top image_packet_rx
optimize_rtl
optimize_gate -packarea image_rx_gate.area
