library verilog;
use verilog.vl_types.all;
entity home_logo_palette is
    port(
        index           : in     vl_logic_vector(2 downto 0);
        rgb             : out    vl_logic_vector(23 downto 0)
    );
end home_logo_palette;
