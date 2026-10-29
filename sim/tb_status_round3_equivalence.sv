`timescale 1ns/1ps
module tb_status_round3_equivalence;
reg clk=0, rst=1, enable=0, vs=0, de=0;
reg [23:0] rgb=24'h123456;
reg [1:0] brightness=3, contrast=0;
reg [3:0] volume=8;
reg [15:0] width=640, height=480;
wire [23:0] new_plain, old_plain, new_res, old_res;
integer frame_no, row_no, col_no, cycles=0, changes=0;
integer line_i,index_i,brightness_i,contrast_i,volume_i,codes=0;
always #5 clk=~clk;

video_status_overlay #(.ENABLE_RESOLUTION(0)) new0 (
 .I_clk(clk),.I_rst(rst),.I_enable(enable),.I_vs(vs),.I_de(de),.I_rgb(rgb),
 .I_brightness_level(brightness),.I_contrast_level(contrast),.I_volume_level(volume),
 .I_source_width(width),.I_source_height(height),.O_rgb(new_plain));
video_status_overlay_round2_reference #(.ENABLE_RESOLUTION(0)) old0 (
 .I_clk(clk),.I_rst(rst),.I_enable(enable),.I_vs(vs),.I_de(de),.I_rgb(rgb),
 .I_brightness_level(brightness),.I_contrast_level(contrast),.I_volume_level(volume),
 .I_source_width(width),.I_source_height(height),.O_rgb(old_plain));
video_status_overlay #(.ENABLE_RESOLUTION(1)) new1 (
 .I_clk(clk),.I_rst(rst),.I_enable(enable),.I_vs(vs),.I_de(de),.I_rgb(rgb),
 .I_brightness_level(brightness),.I_contrast_level(contrast),.I_volume_level(volume),
 .I_source_width(width),.I_source_height(height),.O_rgb(new_res));
video_status_overlay_round2_reference #(.ENABLE_RESOLUTION(1)) old1 (
 .I_clk(clk),.I_rst(rst),.I_enable(enable),.I_vs(vs),.I_de(de),.I_rgb(rgb),
 .I_brightness_level(brightness),.I_contrast_level(contrast),.I_volume_level(volume),
 .I_source_width(width),.I_source_height(height),.O_rgb(old_res));

always @(posedge clk) begin
 #1;
 if (!rst) begin
  cycles=cycles+1;
  if (new_plain !== old_plain || new_res !== old_res ||
      new0.next_text_rel_x !== old0.next_text_rel_x ||
      new1.next_text_rel_x !== old1.next_text_rel_x ||
      new0.next_char_index !== old0.next_char_index ||
      new1.next_char_index !== old1.next_char_index ||
      new0.next_char_cell_x !== old0.next_char_cell_x ||
      new1.next_char_cell_x !== old1.next_char_cell_x ||
      new1.width_frame_bcd !== old1.width_frame_bcd ||
      new1.height_frame_bcd !== old1.height_frame_bcd)
   $fatal(1,"STATUS mismatch cycle=%0d frame=%0d y=%0d x=%0d RGB %h/%h %h/%h rel %d/%d char %d/%d",
    cycles,frame_no,row_no,col_no,new_plain,old_plain,new_res,old_res,
    new1.next_text_rel_x,old1.next_text_rel_x,new1.next_char_cell_x,old1.next_char_cell_x);
  if (new_res!==rgb) changes=changes+1;
 end
end

initial begin
 repeat(5) @(negedge clk); rst=0;
 for(frame_no=0;frame_no<4;frame_no=frame_no+1) begin
  @(negedge clk);
  de=0; vs=1; enable=(frame_no!=2);
  width=(frame_no==0)?640:(frame_no==1)?1280:(frame_no==2)?65535:800;
  height=(frame_no==0)?480:(frame_no==1)?960:(frame_no==2)?1:600;
  brightness=frame_no[1:0]; contrast=(3-frame_no); volume=frame_no*3;
  repeat(48) @(negedge clk);
  vs=0;
  for(row_no=0;row_no<36;row_no=row_no+1) begin
   for(col_no=0;col_no<640;col_no=col_no+1) begin
    @(negedge clk); de=1;
    rgb={col_no[7:0],row_no[7:0],frame_no[7:0]};
    if(row_no==20 && col_no==280) begin
      brightness=3; contrast=1; volume=8;
    end
   end
   @(negedge clk); de=0;
   repeat(8) @(negedge clk);
  end
 end
 if(cycles<90000 || changes<100)
   $fatal(1,"Insufficient coverage cycles=%0d ink=%0d",cycles,changes);
 for(line_i=0;line_i<4;line_i=line_i+1)
  for(index_i=0;index_i<8;index_i=index_i+1)
   for(brightness_i=0;brightness_i<4;brightness_i=brightness_i+1)
    for(contrast_i=0;contrast_i<4;contrast_i=contrast_i+1)
     for(volume_i=0;volume_i<16;volume_i=volume_i+1) begin
      if(new1.status_code(line_i[1:0],index_i[2:0],brightness_i[1:0],contrast_i[1:0],volume_i[3:0]) !==
         old1.status_code(line_i[1:0],index_i[2:0],brightness_i[1:0],contrast_i[1:0],volume_i[3:0]))
       $fatal(1,"Status code mismatch line=%0d index=%0d bri=%0d con=%0d vol=%0d",
        line_i,index_i,brightness_i,contrast_i,volume_i);
      codes=codes+1;
     end
 $display("PASS STATUS_ROUND3_EQUIVALENCE cycles=%0d ink=%0d codes=%0d four frames two resolution modes",cycles,changes,codes);
 $finish;
end
initial begin #4000000; $fatal(1,"status round3 timeout"); end
endmodule
