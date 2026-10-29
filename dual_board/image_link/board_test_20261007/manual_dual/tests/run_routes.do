onerror {quit -code 1 -f}
set here [file normalize manual_dual_20261007]
set rtl [file normalize "$here/../../rtl/manual_dual_20261007"]
set lib "$here/work_routes"
if {![file exists "$lib/_info"]} {vlib $lib}
vlog -sv -work $lib "$rtl/image_tf_source_hw.v" "$here/tb_source_routes.v"
vsim -c -lib $lib tb_source_routes
run -all
quit -code 0 -f
