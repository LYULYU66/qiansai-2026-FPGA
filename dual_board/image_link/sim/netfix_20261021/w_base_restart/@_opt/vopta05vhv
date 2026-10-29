library verilog;
use verilog.vl_types.all;
entity rfifo_32_32_512 is
    generic(
        DATA_WIDTH_W    : integer := 32;
        DATA_WIDTH_R    : integer := 32;
        ADDR_WIDTH_W    : integer := 9;
        ADDR_WIDTH_R    : integer := 9;
        AL_FULL_NUM     : integer := 509;
        AL_EMPTY_NUM    : integer := 2;
        SHOW_AHEAD_EN   : vl_logic := Hi0;
        OUTREG_EN       : string  := "NOREG"
    );
    port(
        rst             : in     vl_logic;
        clkw            : in     vl_logic;
        clkr            : in     vl_logic;
        we              : in     vl_logic;
        di              : in     vl_logic_vector;
        re              : in     vl_logic;
        dout            : out    vl_logic_vector;
        valid           : out    vl_logic;
        full_flag       : out    vl_logic;
        empty_flag      : out    vl_logic;
        afull           : out    vl_logic;
        aempty          : out    vl_logic;
        wrusedw         : out    vl_logic_vector;
        rdusedw         : out    vl_logic_vector
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of DATA_WIDTH_W : constant is 1;
    attribute mti_svvh_generic_type of DATA_WIDTH_R : constant is 1;
    attribute mti_svvh_generic_type of ADDR_WIDTH_W : constant is 1;
    attribute mti_svvh_generic_type of ADDR_WIDTH_R : constant is 1;
    attribute mti_svvh_generic_type of AL_FULL_NUM : constant is 1;
    attribute mti_svvh_generic_type of AL_EMPTY_NUM : constant is 1;
    attribute mti_svvh_generic_type of SHOW_AHEAD_EN : constant is 1;
    attribute mti_svvh_generic_type of OUTREG_EN : constant is 1;
end rfifo_32_32_512;
