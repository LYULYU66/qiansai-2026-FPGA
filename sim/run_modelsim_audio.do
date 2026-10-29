onerror {quit -code 1 -force}
vcd file hdmi_audio_chain.vcd
vcd add -r sim:/tb_hdmi_audio_chain/*
run -all
vcd flush
quit -code 0 -force
