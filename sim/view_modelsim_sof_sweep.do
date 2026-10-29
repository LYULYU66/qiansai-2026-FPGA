# Run from project root in ModelSim. Shows the coincident-VS failure and
# the simulation-only candidate on the same waveform, not a new board build.
vsim -view sim/alignment_20260926/sof_sweep.wlf
view wave
foreach signal {clk vs de rgb expect_user user candidate_user valid last data} {
    add wave -radix hexadecimal /tb_sof_phase_sweep/$signal
}
configure wave -timelineunits ns
wave zoom range 1092300ns 1092800ns
