library verilog;
use verilog.vl_types.all;
entity media_control_star_rx is
    port(
        clk             : in     vl_logic;
        rst             : in     vl_logic;
        rx_valid        : in     vl_logic;
        rx_data         : in     vl_logic_vector(7 downto 0);
        rx_length       : in     vl_logic_vector(15 downto 0);
        star_bundle     : out    vl_logic_vector(75 downto 0);
        bundle_toggle   : out    vl_logic;
        hazard          : out    vl_logic
    );
end media_control_star_rx;
