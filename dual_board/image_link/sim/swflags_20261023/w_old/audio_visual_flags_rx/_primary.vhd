library verilog;
use verilog.vl_types.all;
entity audio_visual_flags_rx is
    port(
        clk             : in     vl_logic;
        rst             : in     vl_logic;
        rx_valid        : in     vl_logic;
        rx_data         : in     vl_logic_vector(7 downto 0);
        rx_length       : in     vl_logic_vector(15 downto 0);
        flags_valid     : out    vl_logic;
        music_state     : out    vl_logic;
        photo_state     : out    vl_logic
    );
end audio_visual_flags_rx;
