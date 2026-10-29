library verilog;
use verilog.vl_types.all;
entity fixed_udp_test_link is
    generic(
        SOURCE_IP       : vl_logic_vector(31 downto 0) := (Hi1, Hi1, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi0, Hi1, Hi0, Hi1, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi0, Hi1, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi1, Hi0, Hi0);
        DEST_IP         : vl_logic_vector(31 downto 0) := (Hi1, Hi1, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi0, Hi1, Hi0, Hi1, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi0, Hi1, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi0, Hi1, Hi1);
        SOURCE_MAC      : vl_logic_vector(47 downto 0) := (Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi1, Hi0, Hi0);
        DEST_MAC        : vl_logic_vector(47 downto 0) := (Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi0, Hi1, Hi1);
        MAX_PAYLOAD     : integer := 1042
    );
    port(
        clk             : in     vl_logic;
        tx_rst          : in     vl_logic;
        rx_rst          : in     vl_logic;
        tx_data         : in     vl_logic_vector(7 downto 0);
        tx_length       : in     vl_logic_vector(15 downto 0);
        tx_request      : in     vl_logic;
        tx_valid        : in     vl_logic;
        tx_ready        : out    vl_logic;
        tx_ack          : out    vl_logic;
        rx_valid        : out    vl_logic;
        rx_data         : out    vl_logic_vector(7 downto 0);
        rx_length       : out    vl_logic_vector(15 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of SOURCE_IP : constant is 2;
    attribute mti_svvh_generic_type of DEST_IP : constant is 2;
    attribute mti_svvh_generic_type of SOURCE_MAC : constant is 2;
    attribute mti_svvh_generic_type of DEST_MAC : constant is 2;
    attribute mti_svvh_generic_type of MAX_PAYLOAD : constant is 2;
end fixed_udp_test_link;
