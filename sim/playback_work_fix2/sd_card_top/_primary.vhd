library verilog;
use verilog.vl_types.all;
entity sd_card_top is
    port(
        clk             : in     vl_logic;
        rst             : in     vl_logic;
        io_abort        : in     vl_logic;
        SD_nCS          : out    vl_logic;
        SD_DCLK         : out    vl_logic;
        SD_MOSI         : out    vl_logic;
        SD_MISO         : in     vl_logic;
        sd_init_done    : out    vl_logic;
        sd_sec_read     : in     vl_logic;
        sd_sec_read_addr: in     vl_logic_vector(31 downto 0);
        sd_sec_read_data: out    vl_logic_vector(7 downto 0);
        sd_sec_read_data_valid: out    vl_logic;
        sd_sec_read_end : out    vl_logic;
        sd_sec_write    : in     vl_logic;
        sd_sec_write_addr: in     vl_logic_vector(31 downto 0);
        sd_sec_write_data: in     vl_logic_vector(7 downto 0);
        sd_sec_write_data_req: out    vl_logic;
        sd_sec_write_end: out    vl_logic
    );
end sd_card_top;
