onerror {quit -code 1 -force}
onbreak {quit -code 1 -force}
log /tb_warning_direct_switch/clk
log /tb_warning_direct_switch/mem_clk
log /tb_warning_direct_switch/frame_vs
log /tb_warning_direct_switch/req
log /tb_warning_direct_switch/danger
log /tb_warning_direct_switch/ready
log /tb_warning_direct_switch/requested
log /tb_warning_direct_switch/read_a
log /tb_warning_direct_switch/displayed
log /tb_warning_direct_switch/active
log /tb_warning_direct_switch/read_b_enable
log /tb_warning_direct_switch/addr
log /tb_warning_direct_switch/app_rd
log /tb_warning_direct_switch/dut/direct_armed
log /tb_warning_direct_switch/dut/direct_idx
log /tb_warning_direct_switch/dut/warning_forced
run -all
quit -code 0 -force
