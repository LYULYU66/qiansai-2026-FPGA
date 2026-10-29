library verilog;
use verilog.vl_types.all;
entity media_link_session is
    generic(
        ROLE            : integer := 0;
        HEARTBEAT_CYCLES: integer := 12500000;
        TIMEOUT_CYCLES  : integer := 62500000;
        RESET_GUARD_CYCLES: integer := 64;
        PIPELINE_RX     : integer := 0
    );
    port(
        clk             : in     vl_logic;
        rst             : in     vl_logic;
        renew           : in     vl_logic;
        rx_valid        : in     vl_logic;
        rx_data         : in     vl_logic_vector(7 downto 0);
        rx_length       : in     vl_logic_vector(15 downto 0);
        udp_ready       : in     vl_logic;
        udp_ack         : in     vl_logic;
        udp_request     : out    vl_logic;
        udp_valid       : out    vl_logic;
        udp_data        : out    vl_logic_vector(7 downto 0);
        udp_length      : out    vl_logic_vector(15 downto 0);
        ready           : out    vl_logic;
        generation      : out    vl_logic_vector(15 downto 0);
        restart         : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of ROLE : constant is 2;
    attribute mti_svvh_generic_type of HEARTBEAT_CYCLES : constant is 2;
    attribute mti_svvh_generic_type of TIMEOUT_CYCLES : constant is 2;
    attribute mti_svvh_generic_type of RESET_GUARD_CYCLES : constant is 2;
    attribute mti_svvh_generic_type of PIPELINE_RX : constant is 2;
end media_link_session;
