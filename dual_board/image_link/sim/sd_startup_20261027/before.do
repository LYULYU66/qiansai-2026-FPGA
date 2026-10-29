onerror {quit -code 1}
onbreak {quit -code 1}
vlib old_work
vlog -sv +define+LEGACY -work old_work before/sd_card_top.v before/sd_card_cmd.v before/sd_card_sec_read_write.v ../../../../src/user_source/hdl_source/SD/spi_master.v tb_sd_startup.sv
vsim -novopt old_work.tb_sd_startup +CASE=0
run -all
quit -code 0
