// Emit a patch, preserving every released source/project/bit.
const fs=require('fs'),p=require('path'),base=__dirname,jobs=[];
const rd=f=>fs.readFileSync(p.join(base,f),'utf8').replaceAll('\r\n','\n');
function rep(s,a,b){if(!s.includes(a))throw Error('Missing '+a);return s.replace(a,b);}
const branch='rtl/sonic_topography_20261009';
let s=rd('rtl/manual_dual_20261007/top_dual_image_hw.v');
s=rep(s,'reg [7:0] home_index_transition;',`reg [7:0] home_index_transition;
// Atlas indices share the terrain's three registered pixel stages, even off-page.
reg [7:0] home_index_delay0,home_index_delay1,home_index_sonic;
always @(posedge video_clk or posedge rst_all)begin
 if(rst_all)begin home_index_delay0<=0;home_index_delay1<=0;home_index_sonic<=0;end
 else begin home_index_delay0<=home_index_transition;home_index_delay1<=home_index_delay0;home_index_sonic<=home_index_delay1;end
end
wire adjusted_base_hs,adjusted_base_vs,adjusted_base_de;
wire [23:0] vout_data_adjusted_base;`);
s=rep(s,`.O_hs                (adjusted_hs),
    .O_vs                (adjusted_vs),
    .O_de                (adjusted_de),
    .O_rgb               (vout_data_adjusted)`,`.O_hs                (adjusted_base_hs),
    .O_vs                (adjusted_base_vs),
    .O_de                (adjusted_base_de),
    .O_rgb               (vout_data_adjusted_base)`);
s=rep(s,'// 底部动态 OSD：',`// Fixed-view terrain replaces page2 spectrum bars; B still supplies TF image2
// and its existing sixteen-band VIZ2 values. No changes to SDRAM/PLL/network.
video_sonic_topography u_sonic_topography (
 .I_clk(video_clk),.I_rst(rst_all),.I_enable(second_image_music),
 .I_hs(adjusted_base_hs),.I_vs(adjusted_base_vs),.I_de(adjusted_base_de),
 .I_rgb(vout_data_adjusted_base),.I_bands(audio_spectrum_levels),
 .I_volume(uart_volume_level),.O_rgb(vout_data_adjusted),
 .O_hs(adjusted_hs),.O_vs(adjusted_vs),.O_de(adjusted_de)
);

// 底部动态 OSD：`);
s=rep(s,'audio_visualizer_overlay u_audio_visualizer_overlay (','audio_visualizer_overlay #(.TOPOGRAPHY_LAYOUT(1)) u_audio_visualizer_overlay (\n    .I_topography       (second_image_music),');
s=rep(s,'.I_index(home_index_transition),.I_de(adjusted_de)', '.I_index(home_index_sonic),.I_de(adjusted_de)');
jobs.push([branch+'/top_dual_image_hw.v',s]);
s=rd('rtl/resource_round10_20261005/audio_visualizer_overlay.v');
s=rep(s,'parameter integer V_ACTIVE = 480','parameter integer V_ACTIVE = 480,\n    parameter integer TOPOGRAPHY_LAYOUT = 0');
s=rep(s,'input  wire         I_enable,','input  wire         I_enable,\n    input  wire         I_topography,');
s=rep(s,"localparam [9:0] ROW_TOP", "wire sonic_layout = TOPOGRAPHY_LAYOUT && I_topography;\nlocalparam [9:0] ROW_TOP");
s=rep(s,'wire spectrum_fill = I_enable && I_de && spectrum_x_hit &&','wire spectrum_fill = I_enable && !sonic_layout && I_de && spectrum_x_hit &&');
s=rep(s,"wire [10:0] wave_x_offset = pixel_x - 11'd333;\nwire wave_x_span = (pixel_x >= 11'd333) && (pixel_x < 11'd589);\nwire wave_x_glow_hit = wave_x_span && (wave_x_offset[3:0] < 4'd12);\nwire wave_x_hit = wave_x_span &&\n                  (wave_x_offset[3:0] >= 4'd1) &&\n                  (wave_x_offset[3:0] <= 4'd10);\nwire [3:0] wave_index = wave_x_offset[7:4];",`// A slim waveform below the terrain; original layout on other pages.
wire [10:0] wave_x_offset = pixel_x - (sonic_layout ? 11'd80 : 11'd333);
wire wave_x_span = sonic_layout ? ((pixel_x>=80)&&(pixel_x<592)) :
                                  ((pixel_x>=333)&&(pixel_x<589));
wire wave_x_glow_hit = wave_x_span && (sonic_layout ?
    (wave_x_offset[4:0]<24) : (wave_x_offset[3:0]<12));
wire wave_x_hit = wave_x_span && (sonic_layout ?
    ((wave_x_offset[4:0]>=2)&&(wave_x_offset[4:0]<=21)) :
    ((wave_x_offset[3:0]>=1)&&(wave_x_offset[3:0]<=10)));
wire [3:0] wave_index = sonic_layout ? wave_x_offset[8:5] : wave_x_offset[7:4];`);
s=rep(s,'{{1{selected_wave_sample[6]}}, selected_wave_sample};','sonic_layout ? ($signed(selected_wave_sample) >>> 2) :\n    $signed({selected_wave_sample[6], selected_wave_sample});');
s=rep(s,'{{1{previous_wave_sample[6]}}, previous_wave_sample};','sonic_layout ? ($signed(previous_wave_sample) >>> 2) :\n    $signed({previous_wave_sample[6], previous_wave_sample});');
s=s.replaceAll("11'sd354 -", "(sonic_layout ? 11'sd414 : 11'sd354) -");
s=rep(s,"(pixel_x >= 11'd330) && (pixel_x < 11'd586) &&\n                      (pixel_y == WAVE_CENTER);",`(sonic_layout ? ((pixel_x>=80)&&(pixel_x<591)) :
                                      ((pixel_x>=330)&&(pixel_x<586))) &&
                      (pixel_y == (sonic_layout ? 10'd414 : WAVE_CENTER));`);
s=rep(s,'wire center_separator = I_enable && I_de &&','wire center_separator = I_enable && !sonic_layout && I_de &&');
jobs.push([branch+'/audio_visualizer_overlay.v',s]);
const olddir='prj/stars_opt_a_s4_20261007',dir='prj/sonic_topography_a_20261009',oldstem='MEDIA_A_STARS_OPT_S4_20261007',stem='MEDIA_A_SONIC_TOPOGRAPHY_20261009';
s=rd(olddir+'/'+oldstem+'.al').replaceAll(olddir,dir).replaceAll(oldstem,stem)
 .replaceAll('/rtl/manual_dual_20261007/top_dual_image_hw.v','/'+branch+'/top_dual_image_hw.v')
 .replaceAll('/rtl/resource_round10_20261005/audio_visualizer_overlay.v','/'+branch+'/audio_visualizer_overlay.v');
const root=p.resolve(base,'../..').replaceAll('\\','/');
s=rep(s,'</Verilog>',`<File Path="${root}/dual_board/image_link/${branch}/video_sonic_topography.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="503"/></FileInfo></File>\n</Verilog>`);
jobs.push([dir+'/'+stem+'.al',s]);jobs.push([dir+'/build_flow.tcl',rd(olddir+'/build_flow.tcl').replaceAll(oldstem,stem)]);
console.log('*** Begin Patch');
for(const[f,t]of jobs){if(fs.existsSync(p.join(base,f)))throw Error('Exists '+f);console.log('*** Add File: dual_board/image_link/'+f);for(const l of t.split('\n'))console.log('+'+l);}
console.log('*** End Patch');
