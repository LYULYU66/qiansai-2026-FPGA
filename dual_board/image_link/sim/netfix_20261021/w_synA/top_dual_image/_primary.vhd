library verilog;
use verilog.vl_types.all;
entity top_dual_image is
    generic(
        MEM_DATA_BITS   : integer := 32;
        ADDR_BITS       : integer := 21;
        BUSRT_BITS      : integer := 10;
        FRAME_PIXELS    : vl_logic_vector;
        BUF0_ADDR       : vl_logic_vector;
        BUF1_ADDR       : vl_logic_vector;
        BUF2_ADDR       : vl_logic_vector;
        BUF3_ADDR       : vl_logic_vector
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        key1            : in     vl_logic;
        key2            : in     vl_logic;
        key_song        : in     vl_logic;
        sw_front        : in     vl_logic;
        sw_left         : in     vl_logic;
        sw_right        : in     vl_logic;
        sw_rear         : in     vl_logic;
        seg_sel         : out    vl_logic_vector(5 downto 0);
        seg_data        : out    vl_logic_vector(7 downto 0);
        HDMI_CLK_P      : out    vl_logic;
        HDMI_D2_P       : out    vl_logic;
        HDMI_D1_P       : out    vl_logic;
        HDMI_D0_P       : out    vl_logic;
        HDMI_DDC_SCL    : out    vl_logic;
        HDMI_DDC_SDA    : inout  vl_logic;
        sd_ncs          : out    vl_logic;
        sd_dclk         : out    vl_logic;
        sd_mosi         : out    vl_logic;
        sd_miso         : in     vl_logic;
        phy1_rgmii_rx_clk: in     vl_logic;
        phy1_rgmii_rx_ctl: in     vl_logic;
        phy1_rgmii_rx_data: in     vl_logic_vector(3 downto 0);
        phy1_rgmii_tx_clk: out    vl_logic;
        phy1_rgmii_tx_ctl: out    vl_logic;
        phy1_rgmii_tx_data: out    vl_logic_vector(3 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of MEM_DATA_BITS : constant is 1;
    attribute mti_svvh_generic_type of ADDR_BITS : constant is 1;
    attribute mti_svvh_generic_type of BUSRT_BITS : constant is 1;
    attribute mti_svvh_generic_type of FRAME_PIXELS : constant is 4;
    attribute mti_svvh_generic_type of BUF0_ADDR : constant is 4;
    attribute mti_svvh_generic_type of BUF1_ADDR : constant is 4;
    attribute mti_svvh_generic_type of BUF2_ADDR : constant is 4;
    attribute mti_svvh_generic_type of BUF3_ADDR : constant is 4;
end top_dual_image;
