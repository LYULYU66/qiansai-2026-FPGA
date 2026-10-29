onerror {quit -code 1 -force}
vcd file refresh_timer.vcd
vcd add -r sim:/tb_sdram_refresh_timer/*
run -all
vcd flush
quit -code 0 -force
