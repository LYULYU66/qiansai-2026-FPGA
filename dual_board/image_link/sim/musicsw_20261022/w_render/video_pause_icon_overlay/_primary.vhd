library verilog;
use verilog.vl_types.all;
entity video_pause_icon_overlay is
    port(
        I_clk           : in     vl_logic;
        I_rst           : in     vl_logic;
        I_vs            : in     vl_logic;
        I_de            : in     vl_logic;
        I_home          : in     vl_logic;
        I_music         : in     vl_logic;
        I_paused        : in     vl_logic;
        I_rgb           : in     vl_logic_vector(23 downto 0);
        O_rgb           : out    vl_logic_vector(23 downto 0)
    );
end video_pause_icon_overlay;
