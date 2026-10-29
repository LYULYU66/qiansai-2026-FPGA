library verilog;
use verilog.vl_types.all;
entity dual_board_eth_transport is
    generic(
        ROLE            : integer := 0;
        UDP_PORT        : vl_logic_vector(15 downto 0) := (Hi0, Hi1, Hi0, Hi1, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi0);
        FIXED_PEER      : integer := 0;
        APP_CLK_HZ      : integer := 125000000;
        SEPARATE_5X     : integer := 0
    );
    port(
        clk_50          : in     vl_logic;
        sys_rst_n       : in     vl_logic;
        phy1_rgmii_rx_clk: in     vl_logic;
        phy1_rgmii_rx_ctl: in     vl_logic;
        phy1_rgmii_rx_data: in     vl_logic_vector(3 downto 0);
        phy1_rgmii_tx_clk: out    vl_logic;
        phy1_rgmii_tx_ctl: out    vl_logic;
        phy1_rgmii_tx_data: out    vl_logic_vector(3 downto 0);
        udp_clk         : out    vl_logic;
        reset           : out    vl_logic;
        tx_ready_app    : out    vl_logic;
        tx_ack_app      : out    vl_logic;
        tx_request_app  : in     vl_logic;
        tx_valid_app    : in     vl_logic;
        tx_data_app     : in     vl_logic_vector(7 downto 0);
        tx_length_app   : in     vl_logic_vector(15 downto 0);
        rx_valid_app    : out    vl_logic;
        rx_data_app     : out    vl_logic_vector(7 downto 0);
        rx_length_app   : out    vl_logic_vector(15 downto 0);
        rx_port_app     : out    vl_logic_vector(15 downto 0);
        media_video_clk : out    vl_logic;
        media_5x_clk    : out    vl_logic;
        media_clock_ready: out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of ROLE : constant is 2;
    attribute mti_svvh_generic_type of UDP_PORT : constant is 2;
    attribute mti_svvh_generic_type of FIXED_PEER : constant is 2;
    attribute mti_svvh_generic_type of APP_CLK_HZ : constant is 2;
    attribute mti_svvh_generic_type of SEPARATE_5X : constant is 2;
end dual_board_eth_transport;
