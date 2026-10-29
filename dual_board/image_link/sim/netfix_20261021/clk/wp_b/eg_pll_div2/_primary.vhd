library verilog;
use verilog.vl_types.all;
entity eg_pll_div2 is
    generic(
        DIV2_ENABLE     : string  := "DISABLE"
    );
    port(
        \out\           : out    vl_logic;
        clk             : in     vl_logic;
        rst_n           : in     vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of DIV2_ENABLE : constant is 1;
end eg_pll_div2;
