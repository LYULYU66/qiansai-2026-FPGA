onerror {quit -code 1 -force}
vcd file osd_alpha_overlay.vcd
vcd add sim:/tb_osd_alpha_overlay/clk
vcd add sim:/tb_osd_alpha_overlay/vs
vcd add sim:/tb_osd_alpha_overlay/de
vcd add sim:/tb_osd_alpha_overlay/rgb_in
vcd add sim:/tb_osd_alpha_overlay/rgb_out
vcd add sim:/tb_osd_alpha_overlay/dut/pixel_x
vcd add sim:/tb_osd_alpha_overlay/dut/pixel_y
vcd add sim:/tb_osd_alpha_overlay/dut/scroll_phase
vcd add sim:/tb_osd_alpha_overlay/dut/panel_hit
vcd add sim:/tb_osd_alpha_overlay/dut/glyph_on
run -all
vcd flush
quit -code 0 -force
