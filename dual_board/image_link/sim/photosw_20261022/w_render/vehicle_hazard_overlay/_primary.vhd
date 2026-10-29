library verilog;
use verilog.vl_types.all;
entity vehicle_hazard_overlay is
    generic(
        H_ACTIVE        : integer := 640;
        V_ACTIVE        : integer := 480;
        BORDER_WIDTH    : integer := 12;
        FRONT_FLASH_BIT : integer := 3;
        SIDE_FLASH_BIT  : integer := 4;
        FRONT_BRIGHT    : vl_logic_vector(23 downto 0) := (Hi1, Hi1, Hi1, Hi1, Hi1, Hi1, Hi1, Hi1, Hi0, Hi0, Hi0, Hi1, Hi1, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi1, Hi1, Hi0, Hi0, Hi0);
        FRONT_DIM       : vl_logic_vector(23 downto 0) := (Hi0, Hi1, Hi1, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi0, Hi0, Hi0);
        LEFT_BRIGHT     : vl_logic_vector(23 downto 0) := (Hi1, Hi1, Hi1, Hi1, Hi1, Hi1, Hi1, Hi1, Hi0, Hi1, Hi1, Hi0, Hi1, Hi0, Hi1, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0);
        LEFT_DIM        : vl_logic_vector(23 downto 0) := (Hi0, Hi1, Hi1, Hi0, Hi1, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0);
        RIGHT_BRIGHT    : vl_logic_vector(23 downto 0) := (Hi1, Hi1, Hi1, Hi1, Hi1, Hi1, Hi1, Hi1, Hi1, Hi1, Hi0, Hi1, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0);
        RIGHT_DIM       : vl_logic_vector(23 downto 0) := (Hi0, Hi1, Hi1, Hi0, Hi1, Hi0, Hi0, Hi0, Hi0, Hi1, Hi0, Hi1, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0)
    );
    port(
        I_clk           : in     vl_logic;
        I_rst           : in     vl_logic;
        I_vs            : in     vl_logic;
        I_de            : in     vl_logic;
        I_rgb           : in     vl_logic_vector(23 downto 0);
        I_warning_page  : in     vl_logic;
        I_hazard_front  : in     vl_logic;
        I_hazard_left   : in     vl_logic;
        I_hazard_right  : in     vl_logic;
        I_hazard_rear   : in     vl_logic;
        O_rgb           : out    vl_logic_vector(23 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of H_ACTIVE : constant is 2;
    attribute mti_svvh_generic_type of V_ACTIVE : constant is 2;
    attribute mti_svvh_generic_type of BORDER_WIDTH : constant is 2;
    attribute mti_svvh_generic_type of FRONT_FLASH_BIT : constant is 2;
    attribute mti_svvh_generic_type of SIDE_FLASH_BIT : constant is 2;
    attribute mti_svvh_generic_type of FRONT_BRIGHT : constant is 2;
    attribute mti_svvh_generic_type of FRONT_DIM : constant is 2;
    attribute mti_svvh_generic_type of LEFT_BRIGHT : constant is 2;
    attribute mti_svvh_generic_type of LEFT_DIM : constant is 2;
    attribute mti_svvh_generic_type of RIGHT_BRIGHT : constant is 2;
    attribute mti_svvh_generic_type of RIGHT_DIM : constant is 2;
end vehicle_hazard_overlay;
