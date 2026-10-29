library verilog;
use verilog.vl_types.all;
entity image_media_board_b is
    port(
        clk_50          : in     vl_logic;
        sys_rst_n       : in     vl_logic;
        key_send_n      : in     vl_logic;
        key_song_n      : in     vl_logic;
        phy1_rgmii_rx_clk: in     vl_logic;
        phy1_rgmii_rx_ctl: in     vl_logic;
        phy1_rgmii_rx_data: in     vl_logic_vector(3 downto 0);
        phy1_rgmii_tx_clk: out    vl_logic;
        phy1_rgmii_tx_ctl: out    vl_logic;
        phy1_rgmii_tx_data: out    vl_logic_vector(3 downto 0);
        SD_nCS          : out    vl_logic;
        SD_DCLK         : out    vl_logic;
        SD_MOSI         : out    vl_logic;
        SD_MISO         : in     vl_logic;
        led             : out    vl_logic_vector(3 downto 0);
        HDMI_DDC_SCL    : out    vl_logic;
        HDMI_DDC_SDA    : inout  vl_logic;
        HDMI_CLK_P      : out    vl_logic;
        HDMI_D0_P       : out    vl_logic;
        HDMI_D1_P       : out    vl_logic;
        HDMI_D2_P       : out    vl_logic
    );
end image_media_board_b;
