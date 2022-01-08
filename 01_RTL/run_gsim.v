module run_gsim ( i_clk, i_reset, i_module_en, o_done, i_a, i_b, o_x );
input          i_clk;
input          i_reset;
input          i_module_en;
output         o_done;
// matrix memory
input	[4095:0] i_a; // 16 * 256-bit
input	[ 255:0] i_b; // 1 * 256-bit
output	[ 511:0] o_x; // 16 * 32-bit
// ---------------------------------------------------------------------------
// Wires and Registers
// ---------------------------------------------------------------------------
reg	[ 31:0]	o_x_w[0:15], o_x_r[0:15];
reg			o_done_w, o_done_r;
reg	[255:0]	A[0:15], A_next[0:15];
reg	[ 15:0] B[0:15], B_next[0:15];
reg	[ 31:0] X[0:15], X_next[0:15];
reg	[ 47:0] AX[0:15], AX_next[0:15]; // (ax) in each round, S31.16 --> S15.16
reg	[ 36:0] SUM[0:15], SUM_next[0:15]; // (b - 15*ax), S20.16 --> S15.16
reg	[ 47:0] newX[0:15], newX_next[0:15]; // 1/a * (b - 15*ax), S17.30 --> S15.16


// vars
reg	[ 1:0]	cur_state, next_state; // 00~11

integer		i,j; // 
reg	[ 3:0]	iter, iter_next; // 0~15
reg	[ 4:0]	round, round_next; // count the round in the single iteration

// paras
parameter S_IDLE		= 2'b00; // Idle
parameter S_WAIT		= 2'b01; // wait for i_module_en, if(i_module_en 0->1) set input to matrix A and B
parameter S_EX			= 2'b10; // Compute Gauss-Seidel Iteration
parameter S_HOLD		= 2'b11; // hold the X until i_module_en 1->0

parameter MAX_32BIT		= {1'b0,{31{1'b1}}}; // 011...11
parameter MIN_32BIT		= {1'b1,{31{1'b0}}}; // 100...00

// ---------------------------------------------------------------------------
// Continuous Assignment
// ---------------------------------------------------------------------------
assign o_done	= o_done_r;
genvar _i;
generate
for(_i=0;_i<=15;_i=_i+1)
	assign o_x[(_i*32+31):(_i*32)]	= X[_i];
endgenerate

// ---------------------------------------------------------------------------
// Combinational Blocks
// ---------------------------------------------------------------------------
// finite state nachine
always@(*) begin
	o_done_w	= o_done_r;
	iter_next	= iter;
	round_next	= round;
	case(cur_state)
		S_IDLE: begin
			next_state	= S_WAIT;
		end
		S_WAIT: begin
			if(i_module_en) begin
				next_state	= S_EX;
				o_done_w	= 0;
				iter_next	= 0;
				round_next	= 0;
			end else begin
				next_state	= S_WAIT;
			end
		end
		S_EX: begin
			if(iter == 4'd15) begin
				next_state	= S_HOLD;
				o_done_w	= 1;
			end else begin
				next_state	= S_EX;
				if(round == 5'd18) begin
					iter_next	= iter + 1;
					round_next	= 0;
				end else begin
					round_next  = round + 1;
				end
			end
		end
		S_HOLD: begin
			if(!i_module_en) begin
				next_state	= S_WAIT;
			end else begin
				next_state	= S_HOLD;
			end
		end
	endcase
end

// set A and B
always@(*) begin
	for(i=0;i<=15;i=i+1) begin
		A_next[i]	= A[i];
		B_next[i]	= B[i];
		//X_next[i]	= X[i];
	end
	// Set A, B and X0 when i_module_en 0->1
	if(cur_state == S_WAIT && i_module_en) begin
		for(i=0;i<=15;i=i+1) begin
			for(j=0;j<=15;j=j+1) begin
				A_next[i][j*16+15 -:16]	= i_a[j*256+i*16+15 -:16];
			end
			B_next[i]	= i_b[i*16+15 -:16];
			//X_next[i]	= {{16{i_b[i*16+15]}},i_b[i*16+15 -:16]} * {{16{i_a[i*256+i*16+15]}},i_a[i*256+i*16+15 -:16]};
		end
	end
end

// Compute X
always@(*) begin
	// compute X for 16 iteration
	for(i=0;i<=15;i=i+1) begin
		AX_next[i]		= AX[i];
		SUM_next[i]		= SUM[i];
		newX_next[i]	= newX[i];
		X_next[i]		= X[i];
	end
	if(cur_state == S_WAIT && i_module_en) begin
		for(i=0;i<=15;i=i+1) begin
			X_next[i]   = {{16{i_b[i*16+15]}},i_b[i*16+15 -:16]} * {{16{i_a[i*256+i*16+15]}},i_a[i*256+i*16+15 -:16]};
		end
	end
	else if(cur_state == S_EX) begin
		// x0~x16
		for(i=0;i<=15;i=i+1) begin
			if(round == 5'd18) begin // Set X(S15.16) = newX(S17.30)
				if(^newX[i][47:45]) begin // overflow, newX = (max|min) of S15.16
					X_next[i]	= {newX[i][47], {31{~newX[i][47]}}}; // (011....11 | 100...00)
				end else begin
					X_next[i]	= newX[i][45:14]; // S17.30 --> S15.16
				end
			end // else, compute xi
			else if(round == 5'd17) begin // X(S17.30) = 1/A(S1.14) * SUM(S15.16)
				if(^SUM[i][36:31]) begin // overflow, SUM = (max|min) of S15.16
					newX_next[i]	= {{32{A[i][i*16+15]}}, A[i][i*16+15 -:16]} * {SUM[i][36], {31{~SUM[i][36]}}}; // (01..1 | 10..0)
				end else begin
					newX_next[i]	= {{32{A[i][i*16+15]}}, A[i][i*16+15 -:16]} * {{16{SUM[i][31]}}, SUM[i][31:0]};
				end
			end else if(round <= 5'd16) begin
				// Compute SUM
				if(round == 0) begin // SUM(S20.16) = B(S15) // init SUM with B
					SUM_next[i] = {{5{B[i][15]}}, B[i], {16{1'b0}}};
				end else if(round-1 != i) begin // SUM(S20.16) = SUM + -AX(S15.16)
					if(^AX[i][47:31]) begin // overflow, AX = (max|min) of S15.16
						SUM_next[i] = SUM[i] - {{6{AX[i][47]}}, {31{~AX[i][47]}}}; // (011....11 | 100...00)
					end else begin
						SUM_next[i] = SUM[i] - {{5{AX[i][31]}}, AX[i][31:0]};
					end
				end
				// Compute AX
				if(round < 5'd16) begin // AX(S31.16) = A(S15) * X(S15.16)
					AX_next[i]	= {{32{A[i][(round<<4)+15]}}, A[i][(round<<4)+15 -:16]} * {{16{X[i][31]}}, X[i]};
				end
			end
		end
	end
end

// ---------------------------------------------------------------------------
// Sequential Block
// ---------------------------------------------------------------------------
always@(posedge i_clk or posedge i_reset) begin
	if(i_reset) begin
		o_done_r	<= 0;
		for(i=0;i<=15;i=i+1) begin
			X[i]		<= 0;
			A[i]		<= 0;
			B[i]		<= 0;
			AX[i]		<= 0;
			SUM[i]		<= 0;
			newX[i]		<= 0;
		end

		cur_state	<= S_IDLE;
		iter		<= 0;
	end else begin
		o_done_r	<= o_done_w;
		for(i=0;i<=15;i=i+1) begin
			X[i]		<= X_next[i];
			A[i]		<= A_next[i];
			B[i]		<= B_next[i];
			AX[i]		<= AX_next[i];
			SUM[i]		<= SUM_next[i];
			newX[i]		<= newX_next[i];
		end

		cur_state	<= next_state;
		iter		<= iter_next;
	end
end
endmodule
