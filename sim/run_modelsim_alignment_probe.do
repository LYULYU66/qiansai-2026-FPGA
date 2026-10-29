onerror {quit -f -code 1}
file mkdir sim/alignment_probe_20260926
set lib sim/alignment_probe_20260926/work
if {![file exists $lib]} {vlib $lib}
set hdl src/user_source/hdl_source
transcript file sim/alignment_probe_20260926/unit_modelsim.log
vlog -sv -work $lib sim/tb_video_alignment_monitor.v sim/tb_uart_audio_control.v $hdl/video_pixel_diagnostics.v $hdl/uart_audio_control.v $hdl/uart_rx.v $hdl/uart_tx.v $hdl/uart_baud_tick.v
foreach tb {tb_video_alignment_monitor tb_uart_audio_control} {
    vsim -onfinish stop -wlf sim/alignment_probe_20260926/$tb.wlf -lib $lib $tb
    log -r /*
    run -all
    if {[examine -radix unsigned /$tb/test_passed] != 1} {quit -f -code 1}
    quit -sim
}
echo "PASS MODELSIM ALIGNMENT PROBE AND UART"
quit -f -code 0
