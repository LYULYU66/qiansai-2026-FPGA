library verilog;
use verilog.vl_types.all;
entity eg_pll_div128 is
    generic(
        DIV             : vl_logic_vector(0 to 6) := (Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0);
        DIP             : vl_logic_vector(0 to 6) := (Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0)
    );
    port(
        \out\           : out    vl_logic;
        shot            : in     vl_logic;
        clk             : in     vl_logic;
        clk_delay       : in     vl_logic;
        rst_n           : in     vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of DIV : constant is 1;
    attribute mti_svvh_generic_type of DIP : constant is 1;
end eg_pll_div128;
