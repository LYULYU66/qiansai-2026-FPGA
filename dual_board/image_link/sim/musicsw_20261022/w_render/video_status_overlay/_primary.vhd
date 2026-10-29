library verilog;
use verilog.vl_types.all;
entity video_status_overlay is
    generic(
        H_ACTIVE        : integer := 640;
        V_ACTIVE        : integer := 480;
        ENABLE_RESOLUTION: integer := 0;
        SELECT_HIGHLIGHT: integer := 0
    );
    port(
        I_clk           : in     vl_logic;
        I_rst           : in     vl_logic;
        I_enable        : in     vl_logic;
        I_vs            : in     vl_logic;
        I_de            : in     vl_logic;
        I_rgb           : in     vl_logic_vector(23 downto 0);
        I_brightness_level: in     vl_logic_vector(1 downto 0);
        I_contrast_level: in     vl_logic_vector(1 downto 0);
        I_volume_level  : in     vl_logic_vector(3 downto 0);
        I_source_width  : in     vl_logic_vector(15 downto 0);
        I_source_height : in     vl_logic_vector(15 downto 0);
        I_selected      : in     vl_logic_vector(1 downto 0);
        O_rgb           : out    vl_logic_vector(23 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of H_ACTIVE : constant is 2;
    attribute mti_svvh_generic_type of V_ACTIVE : constant is 2;
    attribute mti_svvh_generic_type of ENABLE_RESOLUTION : constant is 1;
    attribute mti_svvh_generic_type of SELECT_HIGHLIGHT : constant is 1;
end video_status_overlay;
