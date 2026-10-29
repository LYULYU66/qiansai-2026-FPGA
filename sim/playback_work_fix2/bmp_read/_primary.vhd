library verilog;
use verilog.vl_types.all;
entity bmp_read is
    port(
        clk             : in     vl_logic;
        rst             : in     vl_logic;
        ready           : out    vl_logic;
        scan_start      : in     vl_logic;
        scan_target_count: in     vl_logic_vector(2 downto 0);
        scan_done       : out    vl_logic;
        scan_found_valid: out    vl_logic;
        scan_found_sector: out    vl_logic_vector(31 downto 0);
        scan_found_cluster: out    vl_logic_vector(31 downto 0);
        scan_found_total: out    vl_logic_vector(2 downto 0);
        load_start      : in     vl_logic;
        load_abort      : in     vl_logic;
        load_sector     : in     vl_logic_vector(31 downto 0);
        load_cluster    : in     vl_logic_vector(31 downto 0);
        audio_enable    : in     vl_logic;
        audio_fifo_ready: in     vl_logic;
        audio_file_found: out    vl_logic;
        audio_data_valid: out    vl_logic;
        audio_data      : out    vl_logic_vector(7 downto 0);
        sd_init_done    : in     vl_logic;
        state_code      : out    vl_logic_vector(3 downto 0);
        bmp_width       : in     vl_logic_vector(15 downto 0);
        bmp_height      : in     vl_logic_vector(15 downto 0);
        write_req       : out    vl_logic;
        write_req_ack   : in     vl_logic;
        sd_sec_read     : out    vl_logic;
        sd_sec_read_addr: out    vl_logic_vector(31 downto 0);
        sd_sec_read_data: in     vl_logic_vector(7 downto 0);
        sd_sec_read_data_valid: in     vl_logic;
        sd_sec_read_end : in     vl_logic;
        bmp_data_wr_en  : out    vl_logic;
        bmp_data        : out    vl_logic_vector(23 downto 0)
    );
end bmp_read;
