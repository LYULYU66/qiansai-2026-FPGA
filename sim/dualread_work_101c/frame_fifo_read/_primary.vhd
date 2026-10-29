library verilog;
use verilog.vl_types.all;
entity frame_fifo_read is
    generic(
        MEM_DATA_BITS   : integer := 32;
        ADDR_BITS       : integer := 21;
        BURST_BITS      : integer := 9;
        FIFO_DEPTH      : integer := 512;
        BURST_SIZE      : integer := 128;
        USE_EXTERNAL_GRANT: integer := 1
    );
    port(
        rst             : in     vl_logic;
        mem_clk         : in     vl_logic;
        Sdr_init_done   : in     vl_logic;
        Sdr_init_ref_vld: in     vl_logic;
        Sdr_busy        : in     vl_logic;
        Sdr_rd_en       : in     vl_logic;
        App_wr_busy     : in     vl_logic;
        O_rd_busy       : out    vl_logic;
        I_rd_grant      : in     vl_logic;
        O_rd_want       : out    vl_logic;
        App_rd_en       : out    vl_logic;
        App_rd_addr     : out    vl_logic_vector;
        read_req        : in     vl_logic;
        read_req_ack    : out    vl_logic;
        read_finish     : out    vl_logic;
        read_addr_0     : in     vl_logic_vector;
        read_addr_1     : in     vl_logic_vector;
        read_addr_2     : in     vl_logic_vector;
        read_addr_3     : in     vl_logic_vector;
        read_addr_index : in     vl_logic_vector(1 downto 0);
        read_len        : in     vl_logic_vector;
        fifo_aclr       : out    vl_logic;
        wrusedw         : in     vl_logic_vector(9 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of MEM_DATA_BITS : constant is 1;
    attribute mti_svvh_generic_type of ADDR_BITS : constant is 1;
    attribute mti_svvh_generic_type of BURST_BITS : constant is 1;
    attribute mti_svvh_generic_type of FIFO_DEPTH : constant is 1;
    attribute mti_svvh_generic_type of BURST_SIZE : constant is 1;
    attribute mti_svvh_generic_type of USE_EXTERNAL_GRANT : constant is 1;
end frame_fifo_read;
