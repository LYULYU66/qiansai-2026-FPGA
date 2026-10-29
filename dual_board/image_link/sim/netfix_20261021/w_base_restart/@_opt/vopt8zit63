library verilog;
use verilog.vl_types.all;
entity fifo_cross_domain_addr_process_al_rfifo_32_32_512 is
    generic(
        ADDR_WIDTH      : integer := 9
    );
    port(
        primary_asreset_i: in     vl_logic;
        secondary_asreset_i: in     vl_logic;
        primary_clk_i   : in     vl_logic;
        secondary_clk_i : in     vl_logic;
        primary_addr_i  : in     vl_logic_vector;
        secondary_addr_o: out    vl_logic_vector
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of ADDR_WIDTH : constant is 1;
end fifo_cross_domain_addr_process_al_rfifo_32_32_512;
