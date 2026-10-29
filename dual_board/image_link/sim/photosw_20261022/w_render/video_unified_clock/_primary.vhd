library verilog;
use verilog.vl_types.all;
entity video_unified_clock is
    generic(
        CLK_FREQ_HZ     : integer := 25000000;
        START_BCD       : vl_logic_vector(23 downto 0) := (Hi0, Hi0, Hi0, Hi0, Hi1, Hi0, Hi0, Hi1, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0)
    );
    port(
        I_clk           : in     vl_logic;
        I_rst           : in     vl_logic;
        I_vs            : in     vl_logic;
        O_time_bcd      : out    vl_logic_vector(23 downto 0);
        O_frame_hhmm    : out    vl_logic_vector(15 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of CLK_FREQ_HZ : constant is 2;
    attribute mti_svvh_generic_type of START_BCD : constant is 2;
end video_unified_clock;
