library verilog;
use verilog.vl_types.all;
entity audio_packet_rx is
    generic(
        SESSION_GUARD   : integer := 0
    );
    port(
        clk             : in     vl_logic;
        rst             : in     vl_logic;
        rx_valid        : in     vl_logic;
        generation      : in     vl_logic_vector(15 downto 0);
        rx_data         : in     vl_logic_vector(7 downto 0);
        rx_length       : in     vl_logic_vector(15 downto 0);
        pcm_ready       : in     vl_logic;
        pcm_valid       : out    vl_logic;
        pcm_data        : out    vl_logic_vector(31 downto 0);
        stream_enable   : out    vl_logic;
        file_samples    : out    vl_logic_vector(31 downto 0);
        stream_session  : out    vl_logic_vector(31 downto 0);
        fifo_reset      : out    vl_logic;
        receipt_event   : out    vl_logic;
        receipt_session : out    vl_logic_vector(31 downto 0);
        receipt_sequence: out    vl_logic_vector(15 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of SESSION_GUARD : constant is 2;
end audio_packet_rx;
