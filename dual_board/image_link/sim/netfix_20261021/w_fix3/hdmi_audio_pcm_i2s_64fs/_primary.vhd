library verilog;
use verilog.vl_types.all;
entity hdmi_audio_pcm_i2s_64fs is
    generic(
        START_LEVEL     : integer := 128
    );
    port(
        I_mclk          : in     vl_logic;
        I_rst           : in     vl_logic;
        I_enable        : in     vl_logic;
        I_pcm_data      : in     vl_logic_vector(31 downto 0);
        I_pcm_empty     : in     vl_logic;
        I_pcm_level     : in     vl_logic_vector(8 downto 0);
        I_volume_level  : in     vl_logic_vector(3 downto 0);
        O_pcm_read      : out    vl_logic;
        O_i2s_BCLK      : out    vl_logic;
        O_i2s_LRCK      : out    vl_logic;
        O_i2s_DOUT      : out    vl_logic;
        O_playing       : out    vl_logic;
        O_underflow     : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of START_LEVEL : constant is 2;
end hdmi_audio_pcm_i2s_64fs;
