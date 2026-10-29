library verilog;
use verilog.vl_types.all;
entity tb_cache_reuse is
    generic(
        PACKETS         : integer := 4;
        FULL            : integer := 0
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of PACKETS : constant is 2;
    attribute mti_svvh_generic_type of FULL : constant is 2;
end tb_cache_reuse;
