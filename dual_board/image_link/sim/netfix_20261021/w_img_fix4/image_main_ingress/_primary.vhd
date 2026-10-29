library verilog;
use verilog.vl_types.all;
entity image_main_ingress is
    generic(
        FRAME_PACKETS   : integer := 1200;
        TIMEOUT_CYCLES  : integer := 250000000;
        UI_TAG          : integer := 0;
        RESOLUTION      : integer := 0;
        SESSION_GUARD   : integer := 0;
        REUSE_CACHE     : integer := 0
    );
    port(
        clk             : in     vl_logic;
        rst             : in     vl_logic;
        rx_valid        : in     vl_logic;
        generation      : in     vl_logic_vector(15 downto 0);
        restart_receive : in     vl_logic;
        rx_data         : in     vl_logic_vector(7 downto 0);
        rx_length       : in     vl_logic_vector(15 downto 0);
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
        cache_valid     : out    vl_logic_vector(3 downto 0);
        source_resolutions: out    vl_logic_vector(127 downto 0);
        commit_toggle   : out    vl_logic;
        fault           : out    vl_logic;
        udp_ready       : in     vl_logic;
        udp_ack         : in     vl_logic;
        udp_request     : out    vl_logic;
        udp_valid       : out    vl_logic;
        udp_data        : out    vl_logic_vector(7 downto 0);
        udp_length      : out    vl_logic_vector(15 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of FRAME_PACKETS : constant is 2;
    attribute mti_svvh_generic_type of TIMEOUT_CYCLES : constant is 2;
    attribute mti_svvh_generic_type of UI_TAG : constant is 2;
    attribute mti_svvh_generic_type of RESOLUTION : constant is 2;
    attribute mti_svvh_generic_type of SESSION_GUARD : constant is 2;
    attribute mti_svvh_generic_type of REUSE_CACHE : constant is 2;
end image_main_ingress;
