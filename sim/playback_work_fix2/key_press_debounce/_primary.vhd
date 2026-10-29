library verilog;
use verilog.vl_types.all;
entity key_press_debounce is
    generic(
        CLK_FREQ_HZ     : integer := 100000000;
        DEBOUNCE_MS     : integer := 20
    );
    port(
        clk             : in     vl_logic;
        rst             : in     vl_logic;
        button_in       : in     vl_logic;
        press_pulse     : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of CLK_FREQ_HZ : constant is 2;
    attribute mti_svvh_generic_type of DEBOUNCE_MS : constant is 2;
end key_press_debounce;
