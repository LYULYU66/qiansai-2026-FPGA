library verilog;
use verilog.vl_types.all;
entity image_receipt_tx is
    port(
        clk             : in     vl_logic;
        rst             : in     vl_logic;
        event_valid     : in     vl_logic;
        event_token     : in     vl_logic_vector(31 downto 0);
        event_sequence  : in     vl_logic_vector(15 downto 0);
        udp_ready       : in     vl_logic;
        udp_ack         : in     vl_logic;
        udp_request     : out    vl_logic;
        udp_valid       : out    vl_logic;
        udp_data        : out    vl_logic_vector(7 downto 0);
        udp_length      : out    vl_logic_vector(15 downto 0)
    );
end image_receipt_tx;
