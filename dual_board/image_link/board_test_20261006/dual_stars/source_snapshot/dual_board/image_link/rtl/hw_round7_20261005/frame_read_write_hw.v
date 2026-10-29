`timescale 1ns/1ps
module frame_read_write
#
(
	parameter MEM_DATA_BITS          = 32,
	parameter READ_DATA_BITS         = 32,
	parameter WRITE_DATA_BITS        = 32,
	parameter ADDR_BITS              = 21,
	parameter BURST_BITS             = 9,//
	parameter BURST_SIZE             = 256,
	parameter WRITE_V_FLIP           = 1,      // 1: vertical flip when writing TF/BMP frame into SDRAM
	parameter FRAME_WIDTH            = 640,
	parameter FRAME_HEIGHT           = 480
	,parameter DYNAMIC_V_FLIP        = 0
) 
(
	input                            rst,                  
	// Reset for memory-clock state only. Producer-side FIFO credit must not
	// acquire a new combinational dependency on a memory-clock reset flop.
	input                            mem_reset,
	input                            mem_clk,                    // external memory controller user interface clock
	input							 Sdr_init_done,
	input							 Sdr_init_ref_vld,
    input							 Sdr_busy,
	
    /*
    output                           rd_burst_req,               // to external memory controller,send out a burst read request
	output[BURST_BITS - 1:0]         rd_burst_len,               // to external memory controller,data length of the burst read request, not bytes
	output[ADDR_BITS - 1:0]          rd_burst_addr,              // to external memory controller,base address of the burst read request 
	input                            rd_burst_data_valid,        // from external memory controller,read data valid 
	input[MEM_DATA_BITS - 1:0]       rd_burst_data,              // from external memory controller,read request data
	input                            rd_burst_finish,            // from external memory controller,burst read finish
	*/
	output							 App_rd_en,
	output[ADDR_BITS - 1:0]			 App_rd_addr,
	input							 Sdr_rd_en,					 //read_data_valid
	input[MEM_DATA_BITS - 1:0]		 Sdr_rd_dout,
	
	input                            read_clk,                   // data read module clock
	input                            read_req,                   // data read module read request,keep '1' until read_req_ack = '1'
	output                           read_req_ack,               // data read module read request response
	output                           read_finish,                // data read module read request finish
	input                            read_b_enable,              // second frame stream is needed only during a transition
	input[ADDR_BITS - 1:0]           read_addr_0,                // data read module read request base address 0, used when read_addr_index = 0
	input[ADDR_BITS - 1:0]           read_addr_1,                // data read module read request base address 1, used when read_addr_index = 1
	input[ADDR_BITS - 1:0]           read_addr_2,                // data read module read request base address 1, used when read_addr_index = 2
	input[ADDR_BITS - 1:0]           read_addr_3,                // data read module read request base address 1, used when read_addr_index = 3
	input[1:0]                       read_addr_index,            // select valid base address from read_addr_0 read_addr_1 read_addr_2 read_addr_3
	input[1:0]                       read_addr_index_b,          // frame index for the second read stream
	input[ADDR_BITS - 1:0]           read_len,                   // data read module read request data length
	input                            read_en,                    // data read module read request for one data, read_data valid next clock
	output[READ_DATA_BITS  - 1:0]    read_data,                  // read data
	output[READ_DATA_BITS  - 1:0]    read_data_b,                // second stream read data
	/*
	output                           wr_burst_req,               // to external memory controller,send out a burst write request
	output[BURST_BITS - 1:0]         wr_burst_len,               // to external memory controller,data length of the burst write request, not bytes
	output[ADDR_BITS - 1:0]          wr_burst_addr,              // to external memory controller,base address of the burst write request 
	input                            wr_burst_data_req,          // from external memory controller,write data request ,before data 1 clock
	output[MEM_DATA_BITS - 1:0]      wr_burst_data,              // to external memory controller,write data
	input                            wr_burst_finish,            // from external memory controller,burst write finish
	*/
	output							 App_wr_en,
	output[ADDR_BITS - 1:0]			 App_wr_addr,
	output[MEM_DATA_BITS - 1:0]	 App_wr_din,
	output[3:0]						 App_wr_dm,
	
	//
	input                            write_clk,                  // data write module clock
	input                            write_abort,                // reset only the write path after a failed image load
	input                            write_req,                  // data write module write request,keep '1' until read_req_ack = '1'
	output                           write_req_ack,              // data write module write request response
	output                           write_finish,               // data write module write request finish
	input[ADDR_BITS - 1:0]           write_addr_0,               // data write module write request base address 0, used when write_addr_index = 0
	input[ADDR_BITS - 1:0]           write_addr_1,               // data write module write request base address 1, used when write_addr_index = 1
	input[ADDR_BITS - 1:0]           write_addr_2,               // data write module write request base address 1, used when write_addr_index = 2
	input[ADDR_BITS - 1:0]           write_addr_3,               // data write module write request base address 1, used when write_addr_index = 3
	input[1:0]                       write_addr_index,           // select valid base address from write_addr_0 write_addr_1 write_addr_2 write_addr_3
	input[ADDR_BITS - 1:0]           write_len,                  // data write module write request data length
	input                            write_top_down,
	input                            write_en,                   // data write module write request for one data
	input[WRITE_DATA_BITS - 1:0]     write_data,                // write data
    output wire                     read_empty_a,              // read-clock domain probes only
    output wire                     read_empty_b,
    output wire                     read_valid_a,
    output wire                     write_pixel_ready

);
wire[BURST_BITS - 1:0]                           wrusedw;                    // read FIFO A used words
wire[BURST_BITS - 1:0]                           wrusedw_b;                  // read FIFO B used words
wire[BURST_BITS - 1:0]                           rdusedw;                    // read used words
wire [8:0] write_usedw;
// Existing FIFO, unchanged depth. Keep 32 words of safety margin for the
// registered producer and the asynchronous read-pointer synchronization.
// A packet receiver can present pixel 0 immediately after writer ACK.
 // ACK still belongs to the CLEAR window: the memory FSM only releases
 // fifo_aclr AFTER it sees write_req low. Exclude that entire window,
 // including the native FIFO's local write-reset release clocks.
 (* async_reg="true" *) reg [2:0] write_credit_release;
 wire write_fifo_reset;
 always @(posedge write_clk or posedge write_fifo_reset) begin
     if(write_fifo_reset) write_credit_release<=3'b111;
     else write_credit_release<={write_credit_release[1:0],1'b0};
 end
 assign write_pixel_ready=(write_usedw<9'd480) && !write_credit_release[2] &&
                          !write_abort && !rst;

wire 								 App_rd_busy;
wire								 App_wr_busy;

wire                                 read_fifo_aclr;             // fifo Asynchronous clear
wire                                 write_fifo_aclr;            // fifo Asynchronous clear
wire                                 write_abort_async;
wire                                 write_abort_mem;
reg [1:0]                            write_abort_mem_pipe;

wire O_wr_busy;
wire O_rd_busy;
wire O_rd_busy_b;
wire rd_want_a;
wire rd_want_b;
wire rd_grant_a;
wire rd_grant_b;
wire app_rd_en_a;
wire app_rd_en_b;
wire [ADDR_BITS-1:0] app_rd_addr_a;
wire [ADDR_BITS-1:0] app_rd_addr_b;
wire sdr_rd_en_a;
wire sdr_rd_en_b;
wire read_req_ack_a;
wire read_req_ack_b;
wire read_finish_a;
wire read_finish_b;
wire read_fifo_aclr_b;
reg  rd_owner;
reg  rd_round_robin;

assign App_wr_busy = O_wr_busy;//下个时钟写指令拉高
assign App_rd_busy = O_rd_busy | O_rd_busy_b;
assign App_wr_dm = 4'b0000;
assign write_abort_async = rst | write_abort;
assign write_abort_mem   = write_abort_mem_pipe[1];
assign write_fifo_reset  = rst | write_fifo_aclr | write_abort | write_abort_mem;

// 双帧读突发仲裁。两个通道同时需要数据时逐突发轮转；平时 B 通道关闭，
// 带宽和功耗仍与原单帧设计相同。
assign rd_grant_a = ~O_rd_busy && ~O_rd_busy_b && rd_want_a &&
                    (~rd_want_b || ~rd_round_robin);
assign rd_grant_b = ~O_rd_busy && ~O_rd_busy_b && rd_want_b &&
                    (~rd_want_a ||  rd_round_robin);

assign App_rd_en   = rd_owner ? app_rd_en_b   : app_rd_en_a;
assign App_rd_addr = rd_owner ? app_rd_addr_b : app_rd_addr_a;
assign sdr_rd_en_a = Sdr_rd_en && (rd_owner == 1'b0);
assign sdr_rd_en_b = Sdr_rd_en && (rd_owner == 1'b1);

assign read_req_ack = read_req_ack_a && (~read_b_enable || read_req_ack_b);
assign read_finish  = read_finish_a  && (~read_b_enable || read_finish_b);

always @(posedge mem_clk or posedge mem_reset) begin
	if (mem_reset) begin
		rd_owner       <= 1'b0;
		rd_round_robin <= 1'b0;
	end else if (rd_grant_a) begin
		rd_owner       <= 1'b0;
		rd_round_robin <= 1'b1;
	end else if (rd_grant_b) begin
		rd_owner       <= 1'b1;
		rd_round_robin <= 1'b0;
	end
end

// write_abort 来自 write_clk 域：异步拉高、在 mem_clk 域两拍同步释放。
always @(posedge mem_clk or posedge write_abort_async) begin
	if (write_abort_async)
		write_abort_mem_pipe <= 2'b11;
	else
		write_abort_mem_pipe <= {write_abort_mem_pipe[0], 1'b0};
end

//instantiate an asynchronous FIFO 
wfifo_32_32_512 write_buf
	(
	.clkr                      	(mem_clk                  ),          // Read side clock
	.clkw                      	(write_clk                ),          // Write side clock
	.rst                       	(write_fifo_reset), // Asynchronous clear and matching producer credit
	.we                      	(write_en                 ),          // Write Request
	.re                      	(App_wr_en        		  ),          // Read Request
	.di                       	(write_data               ),          // Input Data
	.empty_flag                 (                         ),          // Read side Empty flag
	.full_flag                  (                         ),          // Write side Full flag
	.wrusedw                	(write_usedw),                         // write-clock credit
	.rdusedw                	(rdusedw                  ),          // Write Used Words
	.dout                       (App_wr_din		          )
);

frame_fifo_write
#
(
	.MEM_DATA_BITS              (MEM_DATA_BITS            ),
	.ADDR_BITS                  (ADDR_BITS                ),
	.BURST_BITS                 (BURST_BITS               ),
	.BURST_SIZE                 (BURST_SIZE               ),
	.WRITE_V_FLIP               (WRITE_V_FLIP             ),
    .DYNAMIC_V_FLIP             (DYNAMIC_V_FLIP),
	.FRAME_WIDTH                (FRAME_WIDTH              ),
	.FRAME_HEIGHT               (FRAME_HEIGHT             )
) 
frame_fifo_write_m0              
(  
	.rst                        (mem_reset | write_abort_mem),
	.mem_clk                    (mem_clk                  ),
    .Sdr_init_done				(Sdr_init_done),
	.Sdr_init_ref_vld			(Sdr_init_ref_vld),
    .Sdr_busy					(Sdr_busy),
	.App_rd_busy				(App_rd_busy),
    .O_wr_busy					(O_wr_busy),
	
	.App_wr_en					(App_wr_en),
    .App_wr_addr				(App_wr_addr),
	.write_req                  (write_req                ),
	.write_req_ack              (write_req_ack            ),
	.write_finish               (write_finish             ),
	.write_addr_0               (write_addr_0             ),
	.write_addr_1               (write_addr_1             ),
	.write_addr_2               (write_addr_2             ),
	.write_addr_3               (write_addr_3             ),
	.write_addr_index           (write_addr_index         ),    
	.write_len                  (write_len                ),
    .write_top_down             (write_top_down),
	.fifo_aclr                  (write_fifo_aclr          ),
	.rdusedw                 	({{(10-BURST_BITS){1'b0}},rdusedw})
);

//instantiate an asynchronous FIFO 
rfifo_32_32_512 read_buf_a
	(
    .valid                      (read_valid_a               ),
	.clkr                     	(read_clk                   ),          // Read side clock
	.clkw                     	(mem_clk                    ),          // Write side clock
	.rst                      	(read_fifo_aclr             ),          // Asynchronous clear
	.we                     	(sdr_rd_en_a               ),          // Write Request
	.re                     	(read_en                    ),          // Read Request
	.di                      	(Sdr_rd_dout                ),          // Input Data
	.empty_flag					(read_empty_a               ),          // Read side Empty flag
	.full_flag					(                           ),          // Write side Full flag
	.wrusedw                	(wrusedw         	  	  		 ),          // Read Used Words
	.rdusedw                	(                  			 ),          // Write Used Words
	.dout						(read_data                  )
);

// 第二路帧FIFO仅在转场期间被请求和读取。
rfifo_32_32_512 read_buf_b
	(
	.clkr                     	(read_clk                   ),
	.clkw                     	(mem_clk                    ),
	.rst                      	(read_fifo_aclr_b           ),
	.we                     	(sdr_rd_en_b               ),
	.re                     	(read_en && read_b_enable  ),
	.di                      	(Sdr_rd_dout                ),
	.empty_flag					(read_empty_b               ),
	.full_flag					(                           ),
	.wrusedw                	(wrusedw_b                 ),
	.rdusedw                	(                           ),
	.dout						(read_data_b                )
);

frame_fifo_read
#
(
	.MEM_DATA_BITS              (MEM_DATA_BITS            ),
	.ADDR_BITS                  (ADDR_BITS                ),
	.BURST_BITS                 (BURST_BITS               ),
	.BURST_SIZE                 (BURST_SIZE               )
)
frame_fifo_read_a
(
	.rst                        (mem_reset                ),
	.mem_clk                    (mem_clk                  ),
    .Sdr_init_done				(Sdr_init_done),
	.Sdr_init_ref_vld			(Sdr_init_ref_vld),
    .Sdr_busy					(Sdr_busy),
    .Sdr_rd_en					(sdr_rd_en_a),
	.App_wr_busy				(App_wr_busy),
    .O_rd_busy					(O_rd_busy),
	.I_rd_grant               (rd_grant_a),
	.O_rd_want                (rd_want_a),
	
	.App_rd_en					(app_rd_en_a),
    .App_rd_addr				(app_rd_addr_a),
	.read_req                   (read_req                 ),
	.read_req_ack               (read_req_ack_a           ),
	.read_finish                (read_finish_a            ),
	.read_addr_0                (read_addr_0              ),
	.read_addr_1                (read_addr_1              ),
	.read_addr_2                (read_addr_2              ),
	.read_addr_3                (read_addr_3              ),
	.read_addr_index            (read_addr_index          ),    
	.read_len                   (read_len                 ),
	.fifo_aclr                  (read_fifo_aclr           ),
	.wrusedw                	({{(10-BURST_BITS){1'b0}},wrusedw})
);

frame_fifo_read #(
    .MEM_DATA_BITS      (MEM_DATA_BITS),
    .ADDR_BITS          (ADDR_BITS),
    .BURST_BITS         (BURST_BITS),
    .BURST_SIZE         (BURST_SIZE)
) frame_fifo_read_b (
    .rst                (mem_reset),
    .mem_clk            (mem_clk),
    .Sdr_init_done      (Sdr_init_done),
    .Sdr_init_ref_vld   (Sdr_init_ref_vld),
    .Sdr_busy           (Sdr_busy),
    .Sdr_rd_en          (sdr_rd_en_b),
    .App_wr_busy        (App_wr_busy),
    .O_rd_busy          (O_rd_busy_b),
    .I_rd_grant         (rd_grant_b),
    .O_rd_want          (rd_want_b),
    .App_rd_en          (app_rd_en_b),
    .App_rd_addr        (app_rd_addr_b),
    .read_req           (read_req && read_b_enable),
    .read_req_ack       (read_req_ack_b),
    .read_finish        (read_finish_b),
    .read_addr_0        (read_addr_0),
    .read_addr_1        (read_addr_1),
    .read_addr_2        (read_addr_2),
    .read_addr_3        (read_addr_3),
    .read_addr_index    (read_addr_index_b),
    .read_len           (read_len),
    .fifo_aclr          (read_fifo_aclr_b),
    .wrusedw            ({{(10-BURST_BITS){1'b0}},wrusedw_b})
);

endmodule
