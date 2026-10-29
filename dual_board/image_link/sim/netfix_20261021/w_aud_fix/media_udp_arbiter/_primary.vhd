library verilog;
use verilog.vl_types.all;
entity media_udp_arbiter is
    port(
        clk             : in     vl_logic;
        rst             : in     vl_logic;
        net_ready       : in     vl_logic;
        net_ack         : in     vl_logic;
        net_request     : out    vl_logic;
        net_valid       : out    vl_logic;
        net_data        : out    vl_logic_vector(7 downto 0);
        net_length      : out    vl_logic_vector(15 downto 0);
        c0_request      : in     vl_logic;
        c0_valid        : in     vl_logic;
        c0_data         : in     vl_logic_vector(7 downto 0);
        c0_length       : in     vl_logic_vector(15 downto 0);
        c0_ready        : out    vl_logic;
        c0_ack          : out    vl_logic;
        c1_request      : in     vl_logic;
        c1_valid        : in     vl_logic;
        c1_data         : in     vl_logic_vector(7 downto 0);
        c1_length       : in     vl_logic_vector(15 downto 0);
        c1_ready        : out    vl_logic;
        c1_ack          : out    vl_logic
    );
end media_udp_arbiter;
