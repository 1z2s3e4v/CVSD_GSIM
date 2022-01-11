`include "run_gsim.v"

module GSIM (                       //Don't modify interface
	input          i_clk,
	input          i_reset,
	input          i_module_en,
	input  [  4:0] i_matrix_num,
	output         o_proc_done,

	// matrix memory
	output         o_mem_rreq,
	output [  9:0] o_mem_addr,
	input          i_mem_rrdy,
	input  [255:0] i_mem_dout,
	input          i_mem_dout_vld,
	
	// output result
	output         o_x_wen,
	output [  8:0] o_x_addr,
	output [ 31:0] o_x_data  
);

`define idle 3'b000
`define ready 3'b001
`define load 3'b010
`define execute 3'b011
`define complete 3'b100

// ---------------------------------------------------------------------------
// Wires and Registers
// ---------------------------------------------------------------------------
reg o_proc_done_r, o_proc_done_w;
reg o_mem_rreq_r, o_mem_rreq_w;
reg [9:0] o_mem_addr_r, o_mem_addr_w;
reg o_x_wen_r, o_x_wen_w;
reg [8:0] o_x_addr_r, o_x_addr_w;
reg [31:0] o_x_data_r, o_x_data_w;


reg [255:0] i_a [0:15];
wire [4095:0] i_a_run;
reg [255:0] i_b; 
wire [255:0] i_b_run;
reg i_in_r, i_in_w;
wire i_in_run;
wire o_out_run;
wire [511:0] o_x_run;


reg [4:0] current_round, next_round, total_round;
reg [9:0] current_address, next_address;
reg [4:0] current_cycle, next_cycle;
reg [2:0] current_state, next_state;


reg [3:0] current_index, next_index;
reg [8:0] current_destination, next_destination;
// ---------------------------------------------------------------------------
// Continuous Assignment
// ---------------------------------------------------------------------------
assign o_proc_done = o_proc_done_r;
assign o_mem_rreq = o_mem_rreq_r;
assign o_mem_addr = o_mem_addr_r;
assign o_x_wen = o_x_wen_r;
assign o_x_addr = o_x_addr_r;
assign o_x_data = o_x_data_r;

assign i_a_run = {i_a[15], i_a[14], i_a[13], i_a[12], i_a[11], i_a[10], i_a[9], i_a[8], i_a[7], i_a[6], i_a[5], i_a[4], i_a[3], i_a[2], i_a[1], i_a[0]};
assign i_b_run = i_b;
assign i_in_run = i_in_r;
run_gsim u_run_gsim (.i_clk(i_clk), .i_reset(i_reset), .i_module_en(i_in_run), .o_done(o_out_run), .i_a(i_a_run), .i_b(i_b_run), .o_x(o_x_run)); 

// ---------------------------------------------------------------------------
// Combinational Blocks
// ---------------------------------------------------------------------------
always @(*) begin
	o_proc_done_w = o_proc_done_r;
	o_mem_rreq_w = o_mem_rreq_r;
	o_mem_addr_w = o_mem_addr_r;
	o_x_wen_w = o_x_wen_r;
	o_x_addr_w = o_x_addr_r;
	o_x_data_w = o_x_data_r;
	i_in_w = i_in_r;
	next_round = current_round;
	next_address = current_address;
	next_cycle = current_cycle;
	next_state = current_state;
	next_index = current_index;
	next_destination = current_destination;


	case (current_state)
		`idle: begin
			if (i_module_en) begin
				total_round = i_matrix_num;
				o_mem_rreq_w = 1;
				o_mem_addr_w = current_address;
				next_state = `ready;
			end
			else begin
				next_state = `idle;
			end
		end
		`ready: begin
			o_mem_rreq_w = 1;
			if (i_mem_rrdy && o_mem_rreq) begin
				next_address = current_address + 1;
				o_mem_addr_w = next_address;
				next_state = `load;
			end
			else begin
				next_state = `ready;
			end
		end		
		`load: begin
			o_mem_rreq_w = 1;
			if (i_mem_dout_vld) begin
				if (current_cycle != 5'd16) begin
					i_a[current_cycle] = i_mem_dout;
					next_cycle = current_cycle + 1;
					if (i_mem_rrdy && o_mem_rreq) begin
						next_address = current_address + 1;
						o_mem_addr_w = next_address;
						next_state = `load;
					end
					else begin
						next_state = `ready;
					end
				end
				else begin
					i_b = i_mem_dout;
					if (i_in_r == 0) begin
						i_in_w = 1;
						next_cycle = 0;
						next_state = `execute;
					end
					else begin
						next_state = `load;
					end
				end
			end 
			else begin
				next_state = `load;
			end
			/// output in load state
			if (o_out_run) begin
				if (current_index == 4'd15) begin
					if (current_round == total_round) begin
						o_proc_done_w = 1;
						next_state = `complete;
					end
					else begin
						o_proc_done_w = 0;
					end
					i_in_w = 0;
				end
				else begin
					i_in_w = 1;
				end
				o_x_wen_w = 1;
				o_x_data_w = o_x_run[32*current_index+31-:32];
				o_x_addr_w = current_destination;
				next_index = current_index + 1;
				next_destination = current_destination + 1;
			end
			else begin
				o_x_wen_w = 0;
				o_x_data_w = 0;
				o_x_addr_w = 0;
				next_index = 0;
			end
		end
		`execute: begin
			next_round = current_round + 1;
			if (i_mem_rrdy && o_mem_rreq) begin
				next_address = current_address + 1;
				o_mem_addr_w = next_address;
				next_state = `load;
			end
			else begin
				next_state = `ready;
			end		
		end
		`complete: begin
			if (!i_module_en) begin
				o_proc_done_w = 0;
			end
		end
	endcase
	

	/***
	if (o_out_run) begin
		o_out = 1;
		o_x = o_x_run;
		i_in = 0;
	end
	else begin
		o_out = 0;
	end
	if (o_out && i < 5'd16) begin
		o_x_wen_w = 1;
		o_x_data_w = o_x[32*i+31 -: 32];
		o_x_addr_w = j;
		n_i = i + 1;
		n_j = j + 1;
	end
	else begin
		n_i = 0;
		n_j = j;
		o_out = 0;
		o_x_wen_w = 0;
		o_x_data_w = 0;
		o_x_addr_w = 0;
	end
	***/
end


// ---------------------------------------------------------------------------
// Sequential Block
// ---------------------------------------------------------------------------
always @(posedge i_clk or posedge i_reset) begin
	if (i_reset) begin
		o_proc_done_r <= 0;
		o_mem_rreq_r <= 0;
		o_mem_addr_r <= 0;
		o_x_wen_r <= 0;
		o_x_addr_r <= 0;
		o_x_data_r <= 0;
		i_in_r <= 0;
		current_round <= 0;
		current_address <= 0;
		current_cycle <= 0;
		current_state <= `idle;
		current_index <= 0;
		current_destination <= 0;
	end
	else begin
		o_proc_done_r <= o_proc_done_w;
		o_mem_rreq_r <= o_mem_rreq_w;
		o_mem_addr_r <= o_mem_addr_w;
		o_x_wen_r <= o_x_wen_w;
		o_x_addr_r <= o_x_addr_w;
		o_x_data_r <= o_x_data_w;
		i_in_r <= i_in_w;
		current_round <= next_round;
		current_address <= next_address;
		current_cycle <= next_cycle;
		current_state <= next_state;
		current_index <= next_index;
		current_destination <= next_destination;
	end
end
endmodule


// line testbench 182 1000->100000 ?
// cycle 10.0 -> 500

