library verilog;
use verilog.vl_types.all;
entity EG_LOGIC_BUFIO is
    generic(
        GSR             : string  := "DISABLE";
        DIV             : integer := 2;
        STOPCLK         : string  := "DISABLE"
    );
    port(
        clki            : in     vl_logic;
        rst             : in     vl_logic;
        coe             : in     vl_logic;
        clko            : out    vl_logic;
        clkdiv1         : out    vl_logic;
        clkdivx         : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of GSR : constant is 1;
    attribute mti_svvh_generic_type of DIV : constant is 1;
    attribute mti_svvh_generic_type of STOPCLK : constant is 1;
end EG_LOGIC_BUFIO;
