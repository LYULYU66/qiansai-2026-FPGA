


`define   DATA_WIDTH                        32
`define   ADDR_WIDTH                        21
`define   DM_WIDTH                          4

`define   ROW_WIDTH                        11
`define   BA_WIDTH                        2

// Keep the expression parenthesized: Verilog macros are expanded as text.
// Without these parentheses the refresh expression becomes a left-to-right
// division chain and evaluates to -1, so the refresh counter never matches.
`define   SDR_CLK_PERIOD                 (1000000000/100000000)

// EM638325 requires 4096 AUTO REFRESH commands in every 64 ms window.
// sdr_init_ref resets init_cnt when it is equal to SELF_REFRESH_INTERVAL,
// therefore the counter terminal value must be (required clock gap - 1).
// At 100 MHz: floor(64 ms / 10 ns / 4096) - 1 = 1561, i.e. one refresh
// command every 1562 clocks (15.620 us).  The old ROW_WIDTH based formula
// issued only 2048 commands per 64 ms and could corrupt an inactive frame.
`define   SDR_REFRESH_WINDOW_NS           64000000
`define   SDR_REFRESH_COMMANDS            4096
`define   SELF_REFRESH_INTERVAL           (`SDR_REFRESH_WINDOW_NS/`SDR_CLK_PERIOD/`SDR_REFRESH_COMMANDS-1)

