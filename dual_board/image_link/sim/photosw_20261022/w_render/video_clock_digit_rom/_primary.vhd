library verilog;
use verilog.vl_types.all;
entity video_clock_digit_rom is
    generic(
        LOW_POWER       : integer := 0
    );
    port(
        I_clk           : in     vl_logic;
        I_address       : in     vl_logic_vector(8 downto 0);
        O_row           : out    vl_logic_vector(15 downto 0);
        I_read_enable   : in     vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of LOW_POWER : constant is 1;
end video_clock_digit_rom;
