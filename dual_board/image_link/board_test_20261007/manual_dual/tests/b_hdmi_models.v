`timescale 1ns/1ps
// Test-only interface models; the Anlogic FIFO, frame FSM and video alignment
// remain production RTL. Electrical SDRAM timing, HDMI packet internals and
// TMDS serialization are not verified by this test.
module sdram (
 input Clk,Clk_sft,Rst,
 output reg Sdr_init_done=0,output Sdr_init_ref_vld,Sdr_busy,
 input App_wr_en,input [20:0] App_wr_addr,input [3:0] App_wr_dm,
 input [31:0] App_wr_din,input App_rd_en,input [20:0] App_rd_addr,
 output reg Sdr_rd_en=0,output reg [31:0] Sdr_rd_dout=0
);
reg [31:0] memory[0:1228799];
reg [5:0] rd_pipe=0;
reg [31:0] data_pipe[0:5];
integer clocks=0,i,writes=0,reads=0;
assign Sdr_init_ref_vld=Sdr_init_done && clocks%1562>=1554;
assign Sdr_busy=(|rd_pipe) || App_rd_en || App_wr_en;
always @(posedge Clk) begin
 if(Rst)begin clocks<=0;Sdr_init_done<=0;rd_pipe<=0;Sdr_rd_en<=0;end
 else begin
  clocks<=clocks+1;
  if(clocks>=1200)Sdr_init_done<=1;
  rd_pipe<={rd_pipe[4:0],App_rd_en};
  if(App_rd_en)begin
   if(App_rd_addr>=1228800)$fatal(1,"read out of four B preview SDRAM slots");
   data_pipe[0]<=memory[App_rd_addr];reads=reads+1;
  end
  for(i=1;i<6;i=i+1)data_pipe[i]<=data_pipe[i-1];
  Sdr_rd_en<=rd_pipe[5];Sdr_rd_dout<=data_pipe[5];
  if(App_wr_en)begin
   if(App_wr_addr>=1228800 || App_wr_dm!==0)$fatal(1,"bad preview write address/mask");
   memory[App_wr_addr]<=App_wr_din;writes=writes+1;
  end
 end
end
endmodule

module hdmi_1_4b_transmitter_core_wrapper #(
 parameter DEVICE="EG",HTOTAL=800,HSA=96,HFP=16,HBP=48,HACTIVE=640,
 VTOTAL=525,VSA=2,VFP=10,VBP=33,VACTIVE=480,VIDEO_VIC=1,
 VIDEO_TPG="Disable",VIDEO_FORMAT="RGB",AUDIO_SAMPLE_RATE="48K",IIC_SCL_DIV=250
) (
 input I_pixel_clk,I_rst,I_edid_read_trig,
 output O_edid_read_valid,output [7:0] O_edid_read_data,
 input I_axis_s_user,I_axis_s_valid,I_axis_s_last,input [23:0] I_axis_s_data,
 output O_axis_s_ready,
 input I_audio_valid,input [23:0] I_audio_left_data,I_audio_right_data,
 input I_acr_valid,input [19:0] I_acr_cts,I_acr_n,
 output O_video_locked,O_ddc_scl,inout IO_ddc_sda,
 output [9:0] O_ch0_tmds_data,O_ch1_tmds_data,O_ch2_tmds_data,O_clk_tmds_data
);
assign O_edid_read_valid=0;assign O_edid_read_data=0;
assign O_axis_s_ready=1;assign O_video_locked=!I_rst;
assign O_ddc_scl=1;assign IO_ddc_sda=1'bz;
assign O_ch0_tmds_data=0;assign O_ch1_tmds_data=0;
assign O_ch2_tmds_data=0;assign O_clk_tmds_data=10'b1111100000;
always @(posedge I_pixel_clk)if(!I_rst && (I_audio_valid || I_acr_valid))
 $fatal(1,"B HDMI must never accept local audio or ACR samples");
endmodule

module hdmi_phy_wrapper #(parameter DEVICE="EG")(
 input I_pixel_clk,I_serial_clk,I_rst,
 input [9:0] I_tmds_channel_0,I_tmds_channel_1,I_tmds_channel_2,I_tmds_channel_clk,
 output O_tmds_ch0_p,O_tmds_ch1_p,O_tmds_ch2_p,O_tmds_clk_p
);
assign O_tmds_clk_p=I_pixel_clk;
assign O_tmds_ch0_p=0;assign O_tmds_ch1_p=0;assign O_tmds_ch2_p=0;
endmodule
