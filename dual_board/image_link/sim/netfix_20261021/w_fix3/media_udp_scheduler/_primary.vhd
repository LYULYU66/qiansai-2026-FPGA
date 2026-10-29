library verilog;
use verilog.vl_types.all;
entity media_udp_scheduler is
    generic(
        CHANNELS        : integer := 5;
        MAX_LENGTH      : integer := 1042
    );
    port(
        clk             : in     vl_logic;
        rst             : in     vl_logic;
        net_ready       : in     vl_logic;
        net_ack         : in     vl_logic;
        net_request     : out    vl_logic;
        net_valid       : out    vl_logic;
        net_data        : out    vl_logic_vector(7 downto 0);
        net_length      : out    vl_logic_vector(15 downto 0);
        c_request       : in     vl_logic_vector;
        c_valid         : in     vl_logic_vector;
        c_data          : in     vl_logic_vector;
        c_length        : in     vl_logic_vector;
        c_ready         : out    vl_logic_vector;
        c_ack           : out    vl_logic_vector
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of CHANNELS : constant is 2;
    attribute mti_svvh_generic_type of MAX_LENGTH : constant is 2;
end media_udp_scheduler;
