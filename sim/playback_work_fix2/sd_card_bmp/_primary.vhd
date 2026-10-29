library verilog;
use verilog.vl_types.all;
entity sd_card_bmp is
    generic(
        CLK_FREQ_HZ     : integer := 100000000;
        SCAN_TARGET_COUNT: vl_logic_vector(2 downto 0) := (Hi1, Hi0, Hi0);
        SCAN_TIMEOUT_CYCLES: integer := 1000000000;
        LOAD_TIMEOUT_CYCLES: integer := 300000000;
        ABORT_HOLD_CYCLES: integer := 32;
        AUTO_PLAY_DEFAULT: vl_logic := Hi0
    );
    port(
        clk             : in     vl_logic;
        rst             : in     vl_logic;
        key_next        : in     vl_logic;
        key_auto        : in     vl_logic;
        bmp_width       : in     vl_logic_vector(15 downto 0);
        bmp_height      : in     vl_logic_vector(15 downto 0);
        display_valid   : out    vl_logic;
        state_code      : out    vl_logic_vector(3 downto 0);
        image_number    : out    vl_logic_vector(3 downto 0);
        write_finish_toggle: in     vl_logic;
        write_buf_idx   : out    vl_logic_vector(1 downto 0);
        disp_buf_idx    : out    vl_logic_vector(1 downto 0);
        load_abort      : out    vl_logic;
        write_req       : out    vl_logic;
        write_req_ack   : in     vl_logic;
        write_en        : out    vl_logic;
        write_data      : out    vl_logic_vector(31 downto 0);
        audio_fifo_ready: in     vl_logic;
        audio_pcm_wr_en : out    vl_logic;
        audio_pcm_data  : out    vl_logic_vector(31 downto 0);
        audio_stream_enable: out    vl_logic;
        SD_nCS          : out    vl_logic;
        SD_DCLK         : out    vl_logic;
        SD_MOSI         : out    vl_logic;
        SD_MISO         : in     vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of CLK_FREQ_HZ : constant is 2;
    attribute mti_svvh_generic_type of SCAN_TARGET_COUNT : constant is 2;
    attribute mti_svvh_generic_type of SCAN_TIMEOUT_CYCLES : constant is 2;
    attribute mti_svvh_generic_type of LOAD_TIMEOUT_CYCLES : constant is 2;
    attribute mti_svvh_generic_type of ABORT_HOLD_CYCLES : constant is 2;
    attribute mti_svvh_generic_type of AUTO_PLAY_DEFAULT : constant is 1;
end sd_card_bmp;
