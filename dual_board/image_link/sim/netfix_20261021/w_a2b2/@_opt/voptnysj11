library verilog;
use verilog.vl_types.all;
entity star_motion_engine is
    generic(
        TICK_BITS       : integer := 13
    );
    port(
        clk             : in     vl_logic;
        rst             : in     vl_logic;
        bundle          : out    vl_logic_vector(75 downto 0);
        bundle_toggle   : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of TICK_BITS : constant is 2;
end star_motion_engine;
