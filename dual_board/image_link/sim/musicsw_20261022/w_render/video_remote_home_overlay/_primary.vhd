library verilog;
use verilog.vl_types.all;
entity video_remote_home_overlay is
    port(
        I_clk           : in     vl_logic;
        I_rst           : in     vl_logic;
        I_enable        : in     vl_logic;
        I_de            : in     vl_logic;
        I_index         : in     vl_logic_vector(7 downto 0);
        I_rgb           : in     vl_logic_vector(23 downto 0);
        O_rgb           : out    vl_logic_vector(23 downto 0)
    );
end video_remote_home_overlay;
