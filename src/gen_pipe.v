
// Created by David Guillen Fandos
// david@davidgf.net
// You may use it as long as you share the sources

`timescale 1ns / 1ps

// This is the generation PIPE
// It creates I/O PADs to fill initial RAMs
// so the big hasher core can process and get PMKs

// Pipeline is as follows:
// | CGEN FSM (...) | CMAP | MERGE & XOR | SHA1 | ... | SHA1 | OUTPUT

`include "constants.vh"

module generation_pipe(
	input  clk,
	input  device_reset,

	// Interface to toplevel controller
	input  [16:0] command,

	// I/O for the next pipe stage
	output     [159:0] iopad_hash,  // Hash state to be used by PBKDF2 (ipad/opad)
	output             pad_type,    // 0 indicates IPAD ready, 1 indicates an OPAD
	output reg         ready,      // Whether the hash 

	input          hash_read,   // I/O pads read, advance to next hash please

	// Finish trigger signal
	output reg finished
);

initial begin
	$dumpvars(0, password_word);
	$dumpvars(0, merge_valid);
	$dumpvars(0, sha1_busy);
	$dumpvars(0, hash_value);
	$dumpvars(0, pass_value);
	$dumpvars(0, cgen_valid_out);
	$dumpvars(0, cgen_char_offset);
	$dumpvars(0, sha1_start);
	$dumpvars(0, sha1_done);
	$dumpvars(0, xor_value);
	$dumpvars(0, ready);
	$dumpvars(0, busy);
	$dumpvars(0, ack_qual);
	$dumpvars(0, cgen_finished);
	$dumpvars(0, advance_pwd);
	$dumpvars(0, xor_ufsm);
	$dumpvars(0, iopad_hash);
end

// Decode CMD
wire       tous    = command[16];
wire [6:0] cmdid   = command[12:8];
wire [7:0] payload = command[ 7:0];

// Initial programming and setup
reg  [3:0] start_offset;
reg  [7:0] pass_value;
reg  [7:0] map_pos;
reg  [7:0] map_value;
reg        map_write;
reg  [3:0] max_characters;
reg  [7:0] charset_size;
reg        xor_ufsm;
always @(posedge clk) begin
	map_write <= 0;

	case (cmdid)
	`CMD_SEL_MSG_LEN: begin
		max_characters <= payload[3:0];
	end
	`CMD_SEL_MAP_BYTE: begin
		map_pos <= payload;
	end
	`CMD_SET_MAP_BYTE: begin
		map_value <= payload;
		map_write <= 1;
	end
	`CMD_SET_MAP_LEN: begin
		charset_size <= payload;
	end
	`CMD_SET_OFFSET: begin
		start_offset <= payload[3:0];
	end
	endcase
end

// Global FSM
reg busy;
reg advance_pwd;

/////// CGEN STAGE ////////

wire [31:0] word_counter;
wire [ 7:0] char_id;
wire        cgen_valid_out;
wire [ 3:0] cgen_char_offset;
wire        cgen_finished;

char_gen graychar_gen(
	.clk(clk),
	.reset(device_reset),

	.max_characters(max_characters),
	.charset_size(charset_size),
	.advance_next(advance_pwd),

	.word_counter(word_counter),
	.valid(cgen_valid_out),
	.finished(cgen_finished),

	.char_offset(cgen_char_offset),
	.char_value(char_id)
);

reg cgen_valid;
always @(posedge clk) begin
	cgen_valid <= cgen_valid_out & ~advance_pwd;
	finished <= cgen_finished;
end

/////// CMAP STAGE ////////

wire [7:0] cmap_char_out;
char_map cmap(
	.clk(clk),
	.char_pos_rd(char_id),

	.wr_enable(map_write),
	.char_pos_wr(map_pos),
	.char_val_wr(map_value),

	// Output for the read port
	.msbyte_out(cmap_char_out)
);

reg  [7:0] cmap_value;
reg        cmap_valid;
reg  [3:0] cmap_char_offset;
always @(posedge clk) begin
	cmap_value <= cmap_char_out;
	cmap_valid <= cgen_valid & ~advance_pwd;
	cmap_char_offset <= cgen_char_offset + start_offset;
end

/////// MERGE STAGE ////////

// Need a 16 byte register
reg         merge_valid;
reg [127:0] password_word;
always @(posedge clk) begin
	if (device_reset) begin
		if (cmdid == `CMD_PUSH_MSG_BYTE && tous)
			password_word <= { password_word[119:0], payload };
	end
	else begin
		password_word <= {
			cmap_valid && cmap_char_offset ==  0 ? cmap_value : password_word[127:120],
			cmap_valid && cmap_char_offset ==  1 ? cmap_value : password_word[119:112],
			cmap_valid && cmap_char_offset ==  2 ? cmap_value : password_word[111:104],
			cmap_valid && cmap_char_offset ==  3 ? cmap_value : password_word[103: 96],
			cmap_valid && cmap_char_offset ==  4 ? cmap_value : password_word[ 95: 88],
			cmap_valid && cmap_char_offset ==  5 ? cmap_value : password_word[ 87: 80],
			cmap_valid && cmap_char_offset ==  6 ? cmap_value : password_word[ 79: 72],
			cmap_valid && cmap_char_offset ==  7 ? cmap_value : password_word[ 71: 64],
			cmap_valid && cmap_char_offset ==  8 ? cmap_value : password_word[ 63: 56],
			cmap_valid && cmap_char_offset ==  9 ? cmap_value : password_word[ 55: 48],
			cmap_valid && cmap_char_offset == 10 ? cmap_value : password_word[ 47: 40],
			cmap_valid && cmap_char_offset == 11 ? cmap_value : password_word[ 39: 32],
			cmap_valid && cmap_char_offset == 12 ? cmap_value : password_word[ 31: 24],
			cmap_valid && cmap_char_offset == 13 ? cmap_value : password_word[ 23: 16],
			cmap_valid && cmap_char_offset == 14 ? cmap_value : password_word[ 15:  8],
			cmap_valid && cmap_char_offset == 15 ? cmap_value : password_word[  7:  0]
		};
	end

	merge_valid <= cmap_valid & ~advance_pwd;
end

// XOR value calculation

wire [511:0] xor_value;
assign xor_value = xor_ufsm ? {64{8'h5c}} : {64{8'h36}};

/////// SHA1s STAGE ////////

wire         sha1_busy;
wire [159:0] hash_value;
wire         sha1_start;
wire         sha1_done;
wire [511:0] hash_input;

assign sha1_start = merge_valid & !sha1_busy & !device_reset & busy & !sha1_done & !ready;

assign hash_input = {
	384'h0,            // It's the first SHA1 iteration, thus no padding nor size!
	password_word[ 31:  0],
	password_word[ 63: 32],
	password_word[ 95: 64],
	password_word[127: 96]
} ^ xor_value;

sha1_small_core testpipe (
	.clk(clk),
	.reset(device_reset),
	.start(sha1_start),
	.busy(sha1_busy),
	.hash(hash_value),
	.done(sha1_done),

	// Actual data, 512 bits (beware the order and endianess!)
	.msg(hash_input),

	// SHA1 first block initial values
	.initial_status(160'h67452301efcdab8998badcfe10325476c3d2e1f0)
);

// ACK from downwards
wire ack_qual;
synch sr (clk, hash_read, ack_qual);

always @(posedge clk) begin
	advance_pwd <= 0;

	// Reset logic
	if (device_reset) begin
		ready <= 0;
		xor_ufsm <= 0;
		// Start as busy, since cgen will have a valid value on reset
		busy <= 1;
	end

	if (sha1_done) begin
		// If read_next, means we have a plaintext ready, advertize it!
		ready <= 1;
		busy <= 0;
	end
	else begin
		// We got an ACK, deassert ready
		if (ack_qual && ready)
			ready <= 0;

		// ACK deasserted, we can issue new password!
		if (!ack_qual && !ready && !busy) begin
			// First issue advance pwd to invalidate pipeline
			if (!xor_ufsm) begin
				xor_ufsm <= ~xor_ufsm;
				busy <= 1;
			end
			else begin
				if (!advance_pwd)
					advance_pwd <= 1;
				else begin
					busy <= 1;
					xor_ufsm <= ~xor_ufsm;
				end
			end
		end
	end
end

// I/Opad outputs
assign iopad_hash = hash_value;
// Pad type used
assign pad_type = xor_ufsm;

endmodule

