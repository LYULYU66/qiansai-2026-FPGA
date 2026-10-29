library verilog;
use verilog.vl_types.all;
entity audio_receipt_rx is
    generic(
        EXTENDED        : integer := 0
    );
    port(
        clk             : in     vl_logic;
        rst             : in     vl_logic;
        rx_valid        : in     vl_logic;
        rx_data         : in     vl_logic_vector(7 downto 0);
        rx_length       : in     vl_logic_vector(15 downto 0);
        receipt_valid   : out    vl_logic;
        receipt_session : out    vl_logic_vector(31 downto 0);
        played_words    : out    vl_logic_vector(31 downto 0);
        receipt_sequence: out    vl_logic_vector(15 downto 0);
        volume_level    : out    vl_logic_vector(3 downto 0);
        analysis_enable : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of EXTENDED : constant is 1;
end audio_receipt_rx;
