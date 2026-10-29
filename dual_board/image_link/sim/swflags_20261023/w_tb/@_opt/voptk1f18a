library verilog;
use verilog.vl_types.all;
entity audio_visual_rx_a is
    port(
        clk             : in     vl_logic;
        rst             : in     vl_logic;
        rx_valid        : in     vl_logic;
        rx_data         : in     vl_logic_vector(7 downto 0);
        rx_length       : in     vl_logic_vector(15 downto 0);
        session_id      : in     vl_logic_vector(31 downto 0);
        played_words    : in     vl_logic_vector(31 downto 0);
        update_valid    : out    vl_logic;
        visual_state    : out    vl_logic_vector(263 downto 0);
        music_state     : out    vl_logic;
        photo_state     : out    vl_logic
    );
end audio_visual_rx_a;
