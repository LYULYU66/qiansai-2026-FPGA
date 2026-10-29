library verilog;
use verilog.vl_types.all;
entity video_home_logo is
    port(
        I_clk           : in     vl_logic;
        I_rst           : in     vl_logic;
        I_enable        : in     vl_logic;
        I_vs            : in     vl_logic;
        I_de            : in     vl_logic;
        I_rgb           : in     vl_logic_vector(23 downto 0);
        O_rgb           : out    vl_logic_vector(23 downto 0)
    );
end video_home_logo;
