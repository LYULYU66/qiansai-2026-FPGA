library verilog;
use verilog.vl_types.all;
entity fixed_peer_udp is
    generic(
        LOCAL_IP        : vl_logic_vector(31 downto 0) := (Hi1, Hi1, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi0, Hi1, Hi0, Hi1, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi0, Hi1, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi0, Hi1, Hi1);
        PEER_IP         : vl_logic_vector(31 downto 0) := (Hi1, Hi1, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi0, Hi1, Hi0, Hi1, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi0, Hi1, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi1, Hi0, Hi0);
        LOCAL_MAC       : vl_logic_vector(47 downto 0) := (Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi0, Hi1, Hi1);
        PEER_MAC        : vl_logic_vector(47 downto 0) := (Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi1, Hi0, Hi0);
        UDP_PORT        : vl_logic_vector(15 downto 0) := (Hi0, Hi1, Hi0, Hi1, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi0);
        MAX_TX_PAYLOAD  : integer := 1042;
        MAX_RX_PAYLOAD  : integer := 1042;
        FILL_TIMEOUT_CYCLES: integer := 4096
    );
    port(
        clk             : in     vl_logic;
        rst             : in     vl_logic;
        app_tx_ready    : out    vl_logic;
        app_tx_ack      : out    vl_logic;
        app_tx_request  : in     vl_logic;
        app_tx_valid    : in     vl_logic;
        app_tx_data     : in     vl_logic_vector(7 downto 0);
        app_tx_length   : in     vl_logic_vector(15 downto 0);
        app_rx_valid    : out    vl_logic;
        app_rx_data     : out    vl_logic_vector(7 downto 0);
        app_rx_length   : out    vl_logic_vector(15 downto 0);
        app_rx_port     : out    vl_logic_vector(15 downto 0);
        mac_rx_valid    : in     vl_logic;
        mac_rx_data     : in     vl_logic_vector(7 downto 0);
        mac_rx_sof_n    : in     vl_logic;
        mac_rx_eof_n    : in     vl_logic;
        mac_rx_ready_n  : out    vl_logic;
        mac_tx_ready_n  : in     vl_logic;
        mac_tx_valid_n  : out    vl_logic;
        mac_tx_data     : out    vl_logic_vector(7 downto 0);
        mac_tx_sof_n    : out    vl_logic;
        mac_tx_eof_n    : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of LOCAL_IP : constant is 2;
    attribute mti_svvh_generic_type of PEER_IP : constant is 2;
    attribute mti_svvh_generic_type of LOCAL_MAC : constant is 2;
    attribute mti_svvh_generic_type of PEER_MAC : constant is 2;
    attribute mti_svvh_generic_type of UDP_PORT : constant is 2;
    attribute mti_svvh_generic_type of MAX_TX_PAYLOAD : constant is 2;
    attribute mti_svvh_generic_type of MAX_RX_PAYLOAD : constant is 2;
    attribute mti_svvh_generic_type of FILL_TIMEOUT_CYCLES : constant is 2;
end fixed_peer_udp;
