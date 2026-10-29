library verilog;
use verilog.vl_types.all;
entity eg_dphase_sel is
    generic(
        PH_INIT_PARA    : integer := 0
    );
    port(
        clko            : out    vl_logic;
        phdone          : out    vl_logic;
        rotate          : in     vl_logic;
        direct          : in     vl_logic;
        phase           : in     vl_logic_vector(7 downto 0);
        psclk           : in     vl_logic;
        rst_n           : in     vl_logic;
        fphactive       : in     vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of PH_INIT_PARA : constant is 1;
end eg_dphase_sel;
