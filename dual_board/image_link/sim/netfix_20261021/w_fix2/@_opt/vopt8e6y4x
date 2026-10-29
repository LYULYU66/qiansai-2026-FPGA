library verilog;
use verilog.vl_types.all;
entity media_control_star_tx is
    generic(
        UPDATE_CYCLES   : integer := 31250
    );
    port(
        clk             : in     vl_logic;
        rst             : in     vl_logic;
        star_bundle     : in     vl_logic_vector(75 downto 0);
        hazard          : in     vl_logic;
        udp_ready       : in     vl_logic;
        udp_ack         : in     vl_logic;
        udp_request     : out    vl_logic;
        udp_valid       : out    vl_logic;
        udp_data        : out    vl_logic_vector(7 downto 0);
        udp_length      : out    vl_logic_vector(15 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of UPDATE_CYCLES : constant is 2;
end media_control_star_tx;
