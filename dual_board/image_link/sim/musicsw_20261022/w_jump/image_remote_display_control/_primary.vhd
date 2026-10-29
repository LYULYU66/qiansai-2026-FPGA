library verilog;
use verilog.vl_types.all;
entity image_remote_display_control is
    generic(
        CLK_FREQ        : integer := 25000000
    );
    port(
        clk             : in     vl_logic;
        rst             : in     vl_logic;
        key_next        : in     vl_logic;
        key_auto        : in     vl_logic;
        warning_hold    : in     vl_logic;
        music_on        : in     vl_logic;
        cache_valid_async: in     vl_logic_vector(3 downto 0);
        display_valid   : out    vl_logic;
        warning_ready   : out    vl_logic;
        requested_index : out    vl_logic_vector(1 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of CLK_FREQ : constant is 2;
end image_remote_display_control;
