library verilog;
use verilog.vl_types.all;
entity image_receipt_rx is
    port(
        clk             : in     vl_logic;
        rst             : in     vl_logic;
        rx_valid        : in     vl_logic;
        rx_data         : in     vl_logic_vector(7 downto 0);
        rx_length       : in     vl_logic_vector(15 downto 0);
        receipt_valid   : out    vl_logic;
        receipt_token   : out    vl_logic_vector(31 downto 0);
        receipt_sequence: out    vl_logic_vector(15 downto 0)
    );
end image_receipt_rx;
