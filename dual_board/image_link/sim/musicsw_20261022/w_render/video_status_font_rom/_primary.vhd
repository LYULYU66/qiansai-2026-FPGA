library verilog;
use verilog.vl_types.all;
entity video_status_font_rom is
    port(
        I_clk           : in     vl_logic;
        I_addr          : in     vl_logic_vector(8 downto 0);
        O_row           : out    vl_logic_vector(29 downto 0)
    );
end video_status_font_rom;
