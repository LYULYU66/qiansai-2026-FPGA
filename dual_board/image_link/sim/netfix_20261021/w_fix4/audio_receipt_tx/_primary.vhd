library verilog;
use verilog.vl_types.all;
entity audio_receipt_tx is
    generic(
        EXTENDED        : integer := 0;
        SONG_CONTROL    : integer := 0;
        PERIODIC_CYCLES : integer := 0;
        IDLE_PAGE_SYNC  : integer := 0
    );
    port(
        clk             : in     vl_logic;
        rst             : in     vl_logic;
        event_valid     : in     vl_logic;
        event_session   : in     vl_logic_vector(31 downto 0);
        played_words    : in     vl_logic_vector(31 downto 0);
        event_sequence  : in     vl_logic_vector(15 downto 0);
        volume_level    : in     vl_logic_vector(3 downto 0);
        analysis_enable : in     vl_logic;
        desired_song    : in     vl_logic_vector(2 downto 0);
        display_page    : in     vl_logic_vector(1 downto 0);
        udp_ready       : in     vl_logic;
        udp_ack         : in     vl_logic;
        udp_request     : out    vl_logic;
        udp_valid       : out    vl_logic;
        udp_data        : out    vl_logic_vector(7 downto 0);
        udp_length      : out    vl_logic_vector(15 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of EXTENDED : constant is 1;
    attribute mti_svvh_generic_type of SONG_CONTROL : constant is 1;
    attribute mti_svvh_generic_type of PERIODIC_CYCLES : constant is 2;
    attribute mti_svvh_generic_type of IDLE_PAGE_SYNC : constant is 1;
end audio_receipt_tx;
