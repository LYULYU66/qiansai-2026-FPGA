library verilog;
use verilog.vl_types.all;
entity EG_PHY_CLKDIV is
    generic(
        GSR             : string  := "DISABLE";
        DIV             : integer := 2
    );
    port(
        clki            : in     vl_logic;
        rst             : in     vl_logic;
        rls             : in     vl_logic;
        clkdiv1         : out    vl_logic;
        clkdivx         : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of GSR : constant is 1;
    attribute mti_svvh_generic_type of DIV : constant is 1;
end EG_PHY_CLKDIV;
