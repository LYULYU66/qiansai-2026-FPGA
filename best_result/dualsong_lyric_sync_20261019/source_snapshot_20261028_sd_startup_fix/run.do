onerror {quit -code 1}
onbreak {quit -code 1}
vlib work
vlog -sv -work work ../../../../src/user_source/hdl_source/SD/sd_card_top.v ../../../../src/user_source/hdl_source/SD/sd_card_cmd.v ../../../../src/user_source/hdl_source/SD/sd_card_sec_read_write.v ../../../../src/user_source/hdl_source/SD/spi_master.v tb_sd_startup.sv
foreach c {0 1 2 3 4 5} {
    vsim -novopt work.tb_sd_startup +CASE=$c
    run -all
    quit -sim
}
quit -code 0
