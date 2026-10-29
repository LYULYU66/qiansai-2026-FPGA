library verilog;
use verilog.vl_types.all;
entity image_packet_rx is
    generic(
        FRAME_PACKETS   : integer := 1200;
        RELIABLE        : integer := 0;
        UI_TAG          : integer := 0;
        RESOLUTION      : integer := 0;
        SESSION_GUARD   : integer := 0
    );
    port(
        clk             : in     vl_logic;
        rst             : in     vl_logic;
        generation      : in     vl_logic_vector(15 downto 0);
        rx_valid        : in     vl_logic;
        rx_data         : in     vl_logic_vector(7 downto 0);
        rx_length       : in     vl_logic_vector(15 downto 0);
        pixel_ready     : in     vl_logic;
        pixel_valid     : out    vl_logic;
        pixel_rgb       : out    vl_logic_vector(23 downto 0);
        pixel_tag       : out    vl_logic_vector(7 downto 0);
        frame_index     : out    vl_logic_vector(1 downto 0);
        frame_top_down  : out    vl_logic;
        frame_resolution: out    vl_logic_vector(31 downto 0);
        frame_start     : out    vl_logic;
        frame_complete  : out    vl_logic;
        frame_abort     : out    vl_logic;
        good_packets    : out    vl_logic_vector(15 downto 0);
        bad_packets     : out    vl_logic_vector(15 downto 0);
        packet_done     : out    vl_logic;
        packet_duplicate: out    vl_logic;
        packet_token    : out    vl_logic_vector(31 downto 0);
        packet_sequence : out    vl_logic_vector(15 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of FRAME_PACKETS : constant is 2;
    attribute mti_svvh_generic_type of RELIABLE : constant is 2;
    attribute mti_svvh_generic_type of UI_TAG : constant is 2;
    attribute mti_svvh_generic_type of RESOLUTION : constant is 2;
    attribute mti_svvh_generic_type of SESSION_GUARD : constant is 2;
end image_packet_rx;
