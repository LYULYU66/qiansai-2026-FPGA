import_device eagle_s20.db -package EG4S20BG256
import_db {C:/Users/28492/Desktop/2025FPGAanlu2/FPGA-ANLU-National-First-Prize-master/Main/q3q4/q4_Runs/phy_1/q4_eco_pr.db}
report_area -io_info -file {C:/FPGA2026/HX4S20_Contest_2026/7_lab_ex_2026_nosoft/qiansai/lab_ex4_tf/sim/inspect_2025_main_phy.area}
import_db {C:/Users/28492/Desktop/2025FPGAanlu2/FPGA-ANLU-National-First-Prize-master/Secondary/prj/UDP_EXAMPLE/UDP_EXAMPLE_Runs/phy_1/UDP_EXAMPLE_eco_pr.db}
report_area -io_info -file {C:/FPGA2026/HX4S20_Contest_2026/7_lab_ex_2026_nosoft/qiansai/lab_ex4_tf/sim/inspect_2025_secondary_phy.area}
exit
