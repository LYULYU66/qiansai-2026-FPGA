library verilog;
use verilog.vl_types.all;
entity audio_visual_cdc is
    generic(
        WIDTH           : integer := 264;
        FRAME_BOUNDARY  : integer := 1;
        RESET_STATE     : vl_logic_vector
    );
    port(
        udp_clk         : in     vl_logic;
        video_clk       : in     vl_logic;
        rst             : in     vl_logic;
        frame_vs        : in     vl_logic;
        update_valid    : in     vl_logic;
        publish_enable  : in     vl_logic;
        visual_state    : in     vl_logic_vector;
        frame_state     : out    vl_logic_vector;
        capture_valid   : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of WIDTH : constant is 2;
    attribute mti_svvh_generic_type of FRAME_BOUNDARY : constant is 1;
    attribute mti_svvh_generic_type of RESET_STATE : constant is 4;
end audio_visual_cdc;
