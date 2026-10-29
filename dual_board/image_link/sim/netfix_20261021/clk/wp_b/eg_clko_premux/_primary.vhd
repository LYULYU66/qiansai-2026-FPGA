library verilog;
use verilog.vl_types.all;
entity eg_clko_premux is
    port(
        clko            : out    vl_logic;
        d               : in     vl_logic_vector(3 downto 0);
        sd              : in     vl_logic_vector(1 downto 0)
    );
end eg_clko_premux;
