library verilog;
use verilog.vl_types.all;
entity image_sdram_sink is
    generic(
        FRAME_PACKETS   : integer := 1200;
        TIMEOUT_CYCLES  : integer := 250000000;
        UI_TAG          : integer := 0;
        RESOLUTION      : integer := 0;
        RECOVERY        : integer := 0;
        REUSE_CACHE     : integer := 0
    );
    port(
        clk             : in     vl_logic;
        rst             : in     vl_logic;
        restart_transfer: in     vl_logic;
        frame_start     : in     vl_logic;
        frame_complete  : in     vl_logic;
        frame_abort     : in     vl_logic;
        frame_index     : in     vl_logic_vector(1 downto 0);
        frame_top_down  : in     vl_logic;
        frame_resolution: in     vl_logic_vector(31 downto 0);
        pixel_valid     : in     vl_logic;
        pixel_rgb       : in     vl_logic_vector(23 downto 0);
        pixel_tag       : in     vl_logic_vector(7 downto 0);
        pixel_ready     : out    vl_logic;
        packet_done     : in     vl_logic;
        packet_token    : in     vl_logic_vector(31 downto 0);
        packet_sequence : in     vl_logic_vector(15 downto 0);
        writer_ready    : in     vl_logic;
        writer_ack      : in     vl_logic;
        writer_finish_toggle: in     vl_logic;
        protected_buffers: in     vl_logic_vector(3 downto 0);
        write_req       : out    vl_logic;
        write_abort     : out    vl_logic;
        write_en        : out    vl_logic;
        write_data      : out    vl_logic_vector(31 downto 0);
        write_index     : out    vl_logic_vector(1 downto 0);
        write_top_down  : out    vl_logic;
        receipt_event   : out    vl_logic;
        receipt_token   : out    vl_logic_vector(31 downto 0);
        receipt_sequence: out    vl_logic_vector(15 downto 0);
        cache_valid     : out    vl_logic_vector(3 downto 0);
        source_resolutions: out    vl_logic_vector(127 downto 0);
        commit_toggle   : out    vl_logic;
        receive_reset   : out    vl_logic;
        fault           : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of FRAME_PACKETS : constant is 2;
    attribute mti_svvh_generic_type of TIMEOUT_CYCLES : constant is 2;
    attribute mti_svvh_generic_type of UI_TAG : constant is 2;
    attribute mti_svvh_generic_type of RESOLUTION : constant is 2;
    attribute mti_svvh_generic_type of RECOVERY : constant is 2;
    attribute mti_svvh_generic_type of REUSE_CACHE : constant is 2;
end image_sdram_sink;
