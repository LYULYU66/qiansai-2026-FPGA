onerror {quit -code 1}
set w work_b_third_selection
if {![file exists $w]} {vlib $w}
vlog -sv -work $w ../rtl/b_hdmi_image3_20261006/b_image_capture.v b_hdmi_image3_20261006/tb_preview_selection.v
vsim -voptargs=+acc -onfinish stop -wlf b_hdmi_image3_20261006/selection.wlf $w.tb_preview_selection
log -r /*
run -all
quit -code 0
