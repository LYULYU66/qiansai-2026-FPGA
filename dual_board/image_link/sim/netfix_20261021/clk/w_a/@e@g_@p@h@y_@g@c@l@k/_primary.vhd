library verilog;
use verilog.vl_types.all;
entity EG_PHY_GCLK is
    port(
        clki            : in     vl_logic;
        clko            : out    vl_logic
    );
end EG_PHY_GCLK;
