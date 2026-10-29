library verilog;
use verilog.vl_types.all;
entity media_audio_enable_cdc is
    port(
        clk             : in     vl_logic;
        fifo_reset      : in     vl_logic;
        stream_enable   : in     vl_logic;
        enable_sync     : out    vl_logic_vector(1 downto 0)
    );
end media_audio_enable_cdc;
