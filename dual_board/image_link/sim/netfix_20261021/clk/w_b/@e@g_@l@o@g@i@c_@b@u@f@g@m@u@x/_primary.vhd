library verilog;
use verilog.vl_types.all;
entity EG_LOGIC_BUFGMUX is
    generic(
        INIT_OUT        : string  := "0";
        PRESELECT_I0    : string  := "TRUE";
        PRESELECT_I1    : string  := "FALSE"
    );
    port(
        o               : out    vl_logic;
        i0              : in     vl_logic;
        i1              : in     vl_logic;
        s               : in     vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of INIT_OUT : constant is 1;
    attribute mti_svvh_generic_type of PRESELECT_I0 : constant is 1;
    attribute mti_svvh_generic_type of PRESELECT_I1 : constant is 1;
end EG_LOGIC_BUFGMUX;
