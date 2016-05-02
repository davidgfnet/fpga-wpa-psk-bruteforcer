
// Created by David Guillen Fandos
// david@davidgf.net
// You may use it as long as you share the sources

`timescale 1ns / 1ps

// This is the hash iteration pipe
// It outputs PMKs using initial states and essid registers
// It will use big RAMs for states

`include "constants.vh"

module bighashpipe(
	input  clk,
	input  global_reset,
	input  device_reset,

	// Interface to toplevel controller
	input  [15:0] command,
	input         cmd_rdy,
	output        cmd_ack,

	// Input/Output from/to generator (async boundary!)
	input [159:0] iopad_hash, // Hash state to be used by PBKDF2 (iopad)
	input         pad_type,   // I or O pad?
	input         iready,     // SHA1 initial status ready
	output reg    readack,    // Tell the generator to go ahead and fetch

	// I/O for the next pipe stage (synchronous output, to a HS FIFO)
	output reg [159:0] pmk_hash,  // PMK value
	output reg         pmk_step,  // PMK is 256 bit so it comes in two chunks
	output reg         ready,     // PMK is valid!

	// Output to the global logic, for frequency tracking purposes
	output fsync
);

`include "util.vh"

initial begin
	$dumpvars(0, global_fsm);
	//$dumpvars(0, global_fsm_mid);
	//$dumpvars(0, global_fsm_end);
	$dumpvars(0, pipe_counter);
	$dumpvars(0, pipe_counter_end);
	//$dumpvars(0, write_addr);
	$dumpvars(0, ipad_wren);
	$dumpvars(0, opad_wren);
	$dumpvars(0, iready_qual);
	$dumpvars(0, readack);
	$dumpvars(0, pipe1_initial);
	$dumpvars(0, pipe2_initial);
	$dumpvars(0, pipe2_out_hash);
	/*$dumpvars(0, i_ipad);
	$dumpvars(0, i_opad);
	$dumpvars(0, f_ipad);
	$dumpvars(0, f_opad);*/
	$dumpvars(0, merged_pmk);
	$dumpvars(0, pmk_hash);
	$dumpvars(0, pmk_step);
	$dumpvars(0, ready);
	$dumpvars(0, reset_hold);
end

// Decode CMD
reg [6:0] cmdid;
reg [7:0] payload;
reg  cmd_rdy_qual_delayed;
always @(posedge clk) begin
	if (cmd_rdy_qual) begin
		cmdid <= command[12:8];
		payload <= command[ 7:0];
	end
	cmd_rdy_qual_delayed <= cmd_rdy_qual;
end

// Initial programming and setup
reg [255:0] essid_reg;
reg   [4:0] essid_len; // SSID max len is 28 chars! User must pad zeros! (+ 0x80)
reg   [6:0] essid_len_hash;
reg   [4:0] essid_wrsel;

wire cmd_rdy_qual;
reg  cmd_ack_out;
synch sin (clk, cmd_rdy, cmd_rdy_qual);
synch sout(clk, cmd_ack_out, cmd_ack);

always @(posedge clk) begin
	if (!cmd_rdy_qual_delayed || global_reset)
		cmd_ack_out <= 0;

	if (cmd_rdy_qual_delayed) begin
		cmd_ack_out <= 1;

		case (cmdid)
		`CMD_SEL_SSID_BYTE: begin
			essid_wrsel <= payload[4:0];
		end
		`CMD_SET_SSID_BYTE: begin
			essid_reg <= ( essid_reg & ~(8'hFF << (essid_wrsel*8)) ) | (payload << (essid_wrsel*8));
		end
		`CMD_SET_SSID_LEN: begin
			// Length must be 1-28
			essid_len <= payload[4:0];
			// Hash length is 64 + ssid len + 4 pad bytes
			essid_len_hash <= payload[4:0] + 68;
		end
		endcase
	end
end

// SHA1 core has 82 cycle latency + 2 initial muxing latency
// Also note the offset between the two SHA1 pipe inputs
`define PIPE_OFFSET_START   (0)
`define PIPE_OFFSET_MID     (83)
`define PIPE_OFFSET_END     (1)

`define PIPE_INFLIGHT (82 + 80 + 5)

// There are 3 FSMs: Global (tells which half is being filled
// and which one is being used, and the number of iterations we've done),
// Fill (scans and fills RAMs) and Scan (that outputs data for the hash calculation)

// FSMs are aligned with MUX0 pipestage

reg  [13:0] global_fsm, global_fsm_mid, global_fsm_end;
reg  [ 7:0] write_addr;
reg  [ 7:0] pipe_counter, pipe_counter_mid, pipe_counter_end;
reg         reset_hold;

wire        active_half     = global_fsm[13];   // Indicates the active half
wire        active_half_mid = global_fsm_mid[13];
wire        active_half_end = global_fsm_end[13];

wire        essid_iteration = global_fsm[12];   // Outer iteration loop (change essid!)
wire [11:0] num_iterations  = global_fsm[11:0]; // 12 bits, 4096 iterations

assign fsync = essid_iteration;

// Global FSM
always @(posedge clk) begin
	if (device_reset) begin
		pipe_counter     <= - `PIPE_OFFSET_START;
		pipe_counter_mid <= - `PIPE_OFFSET_MID;
		pipe_counter_end <=   `PIPE_OFFSET_END;

		global_fsm     <= 0;
		global_fsm_mid <= 0;
		global_fsm_end <= ~0;

		reset_hold <= 1;

	end else begin
		// Stop resetting after N/2 cycles at the beggining
		if (essid_iteration)
			reset_hold <= 0;

		if (pipe_counter == `PIPE_INFLIGHT - 1) begin
			pipe_counter <= 0;
			global_fsm <= global_fsm + 1'b1;
		end else begin
			pipe_counter <= pipe_counter + 1'b1;
		end

		if (pipe_counter_mid == `PIPE_INFLIGHT - 1) begin
			pipe_counter_mid <= 0;
			global_fsm_mid <= global_fsm_mid + 1'b1;
		end else begin
			pipe_counter_mid <= pipe_counter_mid + 1'b1;
		end

		if (pipe_counter_end == `PIPE_INFLIGHT - 1) begin
			pipe_counter_end <= 0;
			global_fsm_end <= global_fsm_end + 1'b1;
		end else begin
			pipe_counter_end <= pipe_counter_end + 1'b1;
		end
	end
end

// RAM Fill FSM!
// Receive ready | Write enable & Ack generator

wire iready_qual;
synch sr (clk, iready, iready_qual);

reg ipad_wren, opad_wren;
reg active_half_prev;

always @(posedge clk) begin
	ipad_wren <= 0;
	opad_wren <= 0;
	active_half_prev <= active_half;

	// When the active half is updated, restart the writing machinery
	if (device_reset || (active_half_prev ^ active_half)) begin
		write_addr <= 0;
		readack <= 0;
	end else begin
		// Asserted write this cycle, increment ptr and ACK on next cycle (on OPAD only!)
		if (opad_wren)
			write_addr <= write_addr + 1'b1;

		if (readack) begin
			// Already wrote to RAM, just wait for ACK to complete
			if (!iready_qual)
				readack <= 0;
		end
		else begin
			// No ACK ongoing, check if we have a new element coming
			if (iready_qual && write_addr < `PIPE_INFLIGHT && essid_iteration) begin
				// We delay writes until we are in the second phase of the pipeline
				// The reason for that is to avoid colisions in RAM read/write at the edges
				ipad_wren <= ~pad_type;
				opad_wren <=  pad_type;
				readack <= 1;
			end
		end
	end
end


// We have two big memories (82Kb each). We will fill one half of it
// and use the other half to work, therefore 1 port is dedicated to 
// writes and the other one to reads

// This is MUX0 pipestage

wire [159:0] i_ipad, i_opad, f_ipad, f_opad;
ram_module #( .DATA(160), .ADDR(9) ) ipad_ram (
	.a_clk(clk), .b_clk(clk),
	.a_wr(ipad_wren),
	.a_addr({ ~active_half, write_addr }),
	.a_din(iopad_hash),
	.b_wr(1'b0),
	.b_addr({ active_half, pipe_counter }),
	.b_dout(i_ipad)
);
ram_module #( .DATA(160), .ADDR(9) ) ipad_ram2 (
	.a_clk(clk), .b_clk(clk),
	.a_wr(ipad_wren),
	.a_addr({ ~active_half, write_addr }),
	.a_din(iopad_hash),
	.b_wr(1'b0),
	.b_addr({ active_half_mid, pipe_counter_mid }),
	.b_dout(f_ipad)
);
ram_module #( .DATA(160), .ADDR(9) ) opad_ram (
	.a_clk(clk),.b_clk(clk),
	.a_wr(opad_wren),
	.a_addr({ ~active_half, write_addr }),
	.a_din(iopad_hash),
	.b_wr(1'b0),
	.b_addr({ active_half_mid, pipe_counter_mid }),
	.b_dout(i_opad)
);
ram_module #( .DATA(160), .ADDR(9) ) opad_ram2 (
	.a_clk(clk),.b_clk(clk),
	.a_wr(opad_wren),
	.a_addr({ ~active_half, write_addr }),
	.a_din(iopad_hash),
	.b_wr(1'b0),
	.b_addr({ active_half_end, pipe_counter_end }),
	.b_dout(f_opad)
);

reg first_iteration_mux1;
reg essid_iteration_mux1;
always @(posedge clk) begin
	first_iteration_mux1 <= (num_iterations == 0);
	essid_iteration_mux1 <= essid_iteration;
end

// This is MUX1 pipestage
// Essid padding, assume that essid is zero padded (so we can OR it)
wire [255:0] ssid_ptched = essid_reg | ( (essid_iteration_mux1 ? 2'h2 : 2'h1) << ((essid_len + 5'h3) * 8) );

wire [255:0] essid_input = {
	ssid_ptched[  7:  0], ssid_ptched[ 15:  8], ssid_ptched[ 23: 16], ssid_ptched[ 31: 24],
	ssid_ptched[ 39: 32], ssid_ptched[ 47: 40], ssid_ptched[ 55: 48], ssid_ptched[ 63: 56],
	ssid_ptched[ 71: 64], ssid_ptched[ 79: 72], ssid_ptched[ 87: 80], ssid_ptched[ 95: 88],
	ssid_ptched[103: 96], ssid_ptched[111:104], ssid_ptched[119:112], ssid_ptched[127:120],
	ssid_ptched[135:128], ssid_ptched[143:136], ssid_ptched[151:144], ssid_ptched[159:152],
	ssid_ptched[167:160], ssid_ptched[175:168], ssid_ptched[183:176], ssid_ptched[191:184],
	ssid_ptched[199:192], ssid_ptched[207:200], ssid_ptched[215:208], ssid_ptched[223:216],
	ssid_ptched[231:224], ssid_ptched[239:232], ssid_ptched[247:240], ssid_ptched[255:248]
};


// Do the essid muxing!
wire [511:0] pipe1_initial = first_iteration_mux1 ?
	// Zero padded ssid (+ 1 or 2) + zero filler + size
	{ essid_input, (essid_len == 28 ? 1'b1 : 1'b0), 245'h0, essid_len_hash, 3'h0 } :
	// Result from previous operation [size is 64 bytes + 20 bytes = 84 bytes]
	{ pipe2_out_hash, 1'b1, 335'h0, 16'h02A0 };

// Pre-stage FF
reg [159:0] i_ipad_delayed;
reg [511:0] pipe1_initial_delayed;
always @(posedge clk) begin
	i_ipad_delayed <= i_ipad;
	pipe1_initial_delayed <= pipe1_initial;
end

// Big SHA1 pipes!

wire [31:0]  pipe1_out [0:4];
sha1_pipeline stage1(
	.clk(clk),
	.msg_in(word_swizzle(pipe1_initial_delayed)),

	.a_in(i_ipad_delayed[159:128]),
	.b_in(i_ipad_delayed[127: 96]),
	.c_in(i_ipad_delayed[ 95: 64]),
	.d_in(i_ipad_delayed[ 63: 32]),
	.e_in(i_ipad_delayed[ 31:  0]),

	.a_out(pipe1_out[0]),
	.b_out(pipe1_out[1]),
	.c_out(pipe1_out[2]),
	.d_out(pipe1_out[3]),
	.e_out(pipe1_out[4])
);

// The input for the 2nd state is the 160b output from
// previous stage properly padded (0x80 + zeros + size)
// This will optimize the synthesis, since we have some
// constant inputs.

wire [31:0] pipe2_out [0:4];
wire [511:0] pipe2_initial = {
	pipe1_out[0] + f_ipad[159:128],    // 160 bits
	pipe1_out[1] + f_ipad[127: 96],
	pipe1_out[2] + f_ipad[ 95: 64],
	pipe1_out[3] + f_ipad[ 63: 32],
	pipe1_out[4] + f_ipad[ 31:  0],
	32'h80000000, 256'h0,  // 32 + 256 bits
	64'h00000000000002A0   // 64+20 size (=672 bits)
};

reg [511:0] pipe2_initial_delayed;
reg [159:0] i_opad_delayed;
always @(posedge clk) begin
	pipe2_initial_delayed <= pipe2_initial;
	i_opad_delayed <= i_opad;
end

sha1_pipeline stage2(
	.clk(clk),
	.msg_in(word_swizzle(pipe2_initial_delayed)),

	.a_in(i_opad_delayed[159:128]),
	.b_in(i_opad_delayed[127: 96]),
	.c_in(i_opad_delayed[ 95: 64]),
	.d_in(i_opad_delayed[ 63: 32]),
	.e_in(i_opad_delayed[ 31:  0]),

	.a_out(pipe2_out[0]),
	.b_out(pipe2_out[1]),
	.c_out(pipe2_out[2]),
	.d_out(pipe2_out[3]),
	.e_out(pipe2_out[4])
);

wire [159:0] pipe2_out_state = {
	pipe2_out[0] + f_opad[159:128],
	pipe2_out[1] + f_opad[127: 96],
	pipe2_out[2] + f_opad[ 95: 64],
	pipe2_out[3] + f_opad[ 63: 32],
	pipe2_out[4] + f_opad[ 31:  0]
};

reg [159:0] pipe2_out_hash;
always @(posedge clk)
	pipe2_out_hash <= pipe2_out_state;

// PMK merge stage
// One port used for reading the other for writing
// Read the current PMK value and XOR it with the output hash
// and store it back. First iteration is xor free.

reg [ 7:0] pipe_counter_end_merge, pipe_counter_end_merge_wb;
reg [13:0] global_fsm_end_merge, global_fsm_end_merge_wb;
reg merged_pmk_mux;
always @(posedge clk) begin
	pipe_counter_end_merge <= pipe_counter_end;
	global_fsm_end_merge <= global_fsm_end;
	pipe_counter_end_merge_wb <= pipe_counter_end_merge;
	global_fsm_end_merge_wb <= global_fsm_end_merge;
	merged_pmk_mux <= (global_fsm_end_merge[11:0] == 0);
end

wire [159:0] pmk_read;
wire [159:0] merged_pmk;

ram_module #( .DATA(160), .ADDR(8) ) pmk_scratch_ram (
	// Write port
	.a_clk(clk),
	.a_wr(1'b1),
	.a_addr(pipe_counter_end_merge_wb),
	.a_din(merged_pmk),

	// Read port
	.b_clk(clk),
	.b_wr(1'b0),
	.b_addr(pipe_counter_end_merge),
	.b_dout(pmk_read)
);

// Merge PMK

assign merged_pmk = merged_pmk_mux ? pipe2_out_hash : pipe2_out_hash ^ pmk_read;

always @(posedge clk) begin
	if (device_reset) begin
		ready <= 0;
	end else begin
		pmk_hash <= merged_pmk;
		pmk_step <= global_fsm_end_merge_wb[12];  // essid_iteration
		ready <= (global_fsm_end_merge_wb[11:0] == 12'hFFF) && !reset_hold; // Last iteration?
	end
end

endmodule

// Pipeline description:
// off:   0           1                81
// |  RAMs READ  |   SHA0   | ... |   SHA80   |   SHA0   | ... |   SHA80   |  HASH END  | PMK MERGE
//    i_ipad rd    init mux         f_ipad rd   init add         f_opad rd   istate add    pmk xor
//                                  i_opad rd                      pmk rd                  pmk wb




