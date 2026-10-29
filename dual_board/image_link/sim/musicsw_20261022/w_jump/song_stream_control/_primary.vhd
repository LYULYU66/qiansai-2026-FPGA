library verilog;
use verilog.vl_types.all;
entity song_stream_control is
    port(
        clk             : in     vl_logic;
        rst             : in     vl_logic;
        reader_idle     : in     vl_logic;
        requested_song  : in     vl_logic_vector(2 downto 0);
        songs_found     : in     vl_logic_vector(5 downto 0);
        selected_song   : out    vl_logic_vector(2 downto 0);
        run_enable      : out    vl_logic
    );
end song_stream_control;
