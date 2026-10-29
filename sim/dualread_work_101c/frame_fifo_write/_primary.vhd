library verilog;
use verilog.vl_types.all;
entity frame_fifo_write is
    generic(
        MEM_DATA_BITS   : integer := 32;
        ADDR_BITS       : integer := 21;
        BURST_BITS      : integer := 9;
        BURST_SIZE      : integer := 128;
        WRITE_V_FLIP    : integer := 1;
        FRAME_WIDTH     : integer := 640;
        FRAME_HEIGHT    : integer := 480
    );
    port(
        rst             : in     vl_logic;
        mem_clk         : in     vl_logic;
        Sdr_init_done   : in     vl_logic;
        Sdr_init_ref_vld: in     vl_logic;
        Sdr_busy        : in     vl_logic;
        App_rd_busy     : in     vl_logic;
        O_wr_busy       : out    vl_logic;
        App_wr_en       : out    vl_logic;
        App_wr_addr     : out    vl_logic_vector;
        write_req       : in     vl_logic;
        write_req_ack   : out    vl_logic;
        write_finish    : out    vl_logic;
        write_addr_0    : in     vl_logic_vector;
        write_addr_1    : in     vl_logic_vector;
        write_addr_2    : in     vl_logic_vector;
        write_addr_3    : in     vl_logic_vector;
        write_addr_index: in     vl_logic_vector(1 downto 0);
        write_len       : in     vl_logic_vector;
        fifo_aclr       : out    vl_logic;
        rdusedw         : in     vl_logic_vector(9 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of MEM_DATA_BITS : constant is 1;
    attribute mti_svvh_generic_type of ADDR_BITS : constant is 1;
    attribute mti_svvh_generic_type of BURST_BITS : constant is 1;
    attribute mti_svvh_generic_type of BURST_SIZE : constant is 1;
    attribute mti_svvh_generic_type of WRITE_V_FLIP : constant is 1;
    attribute mti_svvh_generic_type of FRAME_WIDTH : constant is 1;
    attribute mti_svvh_generic_type of FRAME_HEIGHT : constant is 1;
end frame_fifo_write;
