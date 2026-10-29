library verilog;
use verilog.vl_types.all;
entity star_bundle_cdc is
    generic(
        WIDTH           : integer := 76
    );
    port(
        dst_clk         : in     vl_logic;
        dst_rst         : in     vl_logic;
        src_toggle      : in     vl_logic;
        src_data        : in     vl_logic_vector;
        dst_data        : out    vl_logic_vector
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of WIDTH : constant is 2;
end star_bundle_cdc;
