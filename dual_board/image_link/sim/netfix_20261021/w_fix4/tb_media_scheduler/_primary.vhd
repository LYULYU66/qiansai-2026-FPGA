library verilog;
use verilog.vl_types.all;
entity tb_media_scheduler is
    generic(
        CHANNELS        : integer := 5;
        MAX_LENGTH      : integer := 1042
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of CHANNELS : constant is 2;
    attribute mti_svvh_generic_type of MAX_LENGTH : constant is 2;
end tb_media_scheduler;
