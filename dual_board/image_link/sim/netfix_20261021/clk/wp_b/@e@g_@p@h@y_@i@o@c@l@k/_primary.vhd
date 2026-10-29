library verilog;
use verilog.vl_types.all;
entity EG_PHY_IOCLK is
    generic(
        STOPCLK         : string  := "DISABLE"
    );
    port(
        clki            : in     vl_logic;
        stop            : in     vl_logic;
        clko            : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of STOPCLK : constant is 1;
end EG_PHY_IOCLK;
