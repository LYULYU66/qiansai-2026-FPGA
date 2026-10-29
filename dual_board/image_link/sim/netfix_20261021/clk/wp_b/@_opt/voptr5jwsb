library verilog;
use verilog.vl_types.all;
entity prediv_mux is
    generic(
        MUX_SEL         : string  := "VCO"
    );
    port(
        prediv_mux_sram : out    vl_logic_vector(1 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of MUX_SEL : constant is 1;
end prediv_mux;
