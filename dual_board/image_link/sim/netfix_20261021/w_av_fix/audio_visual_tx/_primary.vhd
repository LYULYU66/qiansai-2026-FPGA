library verilog;
use verilog.vl_types.all;
entity audio_visual_tx is
    generic(
        UPDATE_CYCLES   : integer := 2083333
    );
    port(
        clk             : in     vl_logic;
        rst             : in     vl_logic;
        source_settled  : in     vl_logic;
        session_id      : in     vl_logic_vector(31 downto 0);
        analysed_words  : in     vl_logic_vector(31 downto 0);
        visual_state    : in     vl_logic_vector(263 downto 0);
        udp_ready       : in     vl_logic;
        udp_ack         : in     vl_logic;
        udp_request     : out    vl_logic;
        udp_valid       : out    vl_logic;
        udp_data        : out    vl_logic_vector(7 downto 0);
        udp_length      : out    vl_logic_vector(15 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of UPDATE_CYCLES : constant is 2;
end audio_visual_tx;
