`timescale 1ns/1ps

// Run the exact same scoreboard for one complete 640x480 frame.
module tb_image_link_full;
    tb_image_link_loop #(.FRAME_PACKETS(1200)) u_full_frame();
endmodule
