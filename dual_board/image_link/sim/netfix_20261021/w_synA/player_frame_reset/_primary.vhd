library verilog;
use verilog.vl_types.all;
entity player_frame_reset is
    port(
        clk             : in     vl_logic;
        request         : in     vl_logic;
        rst             : out    vl_logic
    );
end player_frame_reset;
