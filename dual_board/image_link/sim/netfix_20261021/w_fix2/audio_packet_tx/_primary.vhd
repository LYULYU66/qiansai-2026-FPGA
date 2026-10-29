library verilog;
use verilog.vl_types.all;
entity audio_packet_tx is
    generic(
        RETRY_CYCLES    : integer := 125000
    );
    port(
        clk             : in     vl_logic;
        rst             : in     vl_logic;
        session_id      : in     vl_logic_vector(31 downto 0);
        file_samples    : in     vl_logic_vector(31 downto 0);
        source_valid    : in     vl_logic;
        source_pcm      : in     vl_logic_vector(31 downto 0);
        source_ready    : out    vl_logic;
        udp_ready       : in     vl_logic;
        udp_ack         : in     vl_logic;
        udp_request     : out    vl_logic;
        udp_valid       : out    vl_logic;
        udp_data        : out    vl_logic_vector(7 downto 0);
        udp_length      : out    vl_logic_vector(15 downto 0);
        receipt_valid   : in     vl_logic;
        receipt_session : in     vl_logic_vector(31 downto 0);
        receipt_sequence: in     vl_logic_vector(15 downto 0);
        sequence_no     : out    vl_logic_vector(15 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of RETRY_CYCLES : constant is 2;
end audio_packet_tx;
