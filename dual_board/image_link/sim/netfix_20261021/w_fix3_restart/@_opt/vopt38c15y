library verilog;
use verilog.vl_types.all;
entity image_packet_tx is
    generic(
        FRAME_PACKETS   : integer := 1200;
        INTER_PACKET_CYCLES: integer := 700;
        RELIABLE        : integer := 0;
        RETRY_CYCLES    : integer := 12500000;
        EXTERNAL_TOKEN  : integer := 0;
        UI_TAG          : integer := 0;
        RESOLUTION      : integer := 0
    );
    port(
        clk             : in     vl_logic;
        rst             : in     vl_logic;
        source_valid    : in     vl_logic;
        source_ready    : out    vl_logic;
        source_rgb      : in     vl_logic_vector(23 downto 0);
        source_tag      : in     vl_logic_vector(7 downto 0);
        source_frame_start: in     vl_logic;
        source_frame_index: in     vl_logic_vector(1 downto 0);
        source_top_down : in     vl_logic;
        source_resolution: in     vl_logic_vector(31 downto 0);
        udp_ready       : in     vl_logic;
        udp_ack         : in     vl_logic;
        udp_request     : out    vl_logic;
        udp_valid       : out    vl_logic;
        udp_data        : out    vl_logic_vector(7 downto 0);
        udp_length      : out    vl_logic_vector(15 downto 0);
        frame_sent      : out    vl_logic;
        packets_sent    : out    vl_logic_vector(15 downto 0);
        receipt_valid   : in     vl_logic;
        receipt_token   : in     vl_logic_vector(31 downto 0);
        receipt_sequence: in     vl_logic_vector(15 downto 0);
        transfer_token  : out    vl_logic_vector(31 downto 0);
        packet_sequence : out    vl_logic_vector(15 downto 0);
        frame_token     : in     vl_logic_vector(31 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of FRAME_PACKETS : constant is 2;
    attribute mti_svvh_generic_type of INTER_PACKET_CYCLES : constant is 2;
    attribute mti_svvh_generic_type of RELIABLE : constant is 2;
    attribute mti_svvh_generic_type of RETRY_CYCLES : constant is 2;
    attribute mti_svvh_generic_type of EXTERNAL_TOKEN : constant is 2;
    attribute mti_svvh_generic_type of UI_TAG : constant is 2;
    attribute mti_svvh_generic_type of RESOLUTION : constant is 2;
end image_packet_tx;
