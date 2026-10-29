library verilog;
use verilog.vl_types.all;
entity video_clock_overlay is
    generic(
        LOW_POWER       : integer := 0
    );
    port(
        I_clk           : in     vl_logic;
        I_rst           : in     vl_logic;
        I_enable        : in     vl_logic;
        I_vs            : in     vl_logic;
        I_de            : in     vl_logic;
        I_picture_idx   : in     vl_logic_vector(1 downto 0);
        I_frame_hhmm    : in     vl_logic_vector(15 downto 0);
        I_rgb           : in     vl_logic_vector(23 downto 0);
        O_rgb           : out    vl_logic_vector(23 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of LOW_POWER : constant is 1;
end video_clock_overlay;
