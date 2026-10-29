library verilog;
use verilog.vl_types.all;
entity home_logo_rom is
    port(
        clk             : in     vl_logic;
        ce              : in     vl_logic;
        addr            : in     vl_logic_vector(9 downto 0);
        q               : out    vl_logic_vector(8 downto 0)
    );
end home_logo_rom;
