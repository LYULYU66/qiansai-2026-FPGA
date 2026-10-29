onerror {quit -code 1}
set w work_car_rotate_intro
if {![file exists $w]} {vlib $w}
vlog -work $w C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_bram32k.v C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_glbl.v
vlog -sv -work $w +incdir+car_intro_20261007 ../rtl/car_intro_20261007/car_intro_rom.v ../rtl/car_rotate_20261009/video_car_intro.v car_intro_20261007/tb_car_intro.v
vsim -voptargs=+acc -onfinish stop -wlf car_rotate_20261009/intro.wlf $w.tb_car_intro $w.glbl
log /tb_car_intro/dut/age
log /tb_car_intro/dut/opacity
log /tb_car_intro/dut/idle_phase
run -all
quit -code 0

