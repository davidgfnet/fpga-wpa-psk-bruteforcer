
// Created by David Guillen Fandos
// david@davidgf.net
// You may use it as long as you share the sources

`timescale 1ns / 1ps

module sha1_pipeline(
	input         clk,

	input  [511:0] msg_in,    // 512 bit msg

	input  [31:0] a_in,       // 32 bit A[0] // This is the initial state for the hasher machinery
	input  [31:0] b_in,       // 32 bit B[0]
	input  [31:0] c_in,       // 32 bit C[0]
	input  [31:0] d_in,       // 32 bit D[0]
	input  [31:0] e_in,       // 32 bit E[0]

	output reg [31:0] a_out,  // 32 bit A
	output reg [31:0] b_out,  // 32 bit B
	output reg [31:0] c_out,  // 32 bit C
	output reg [31:0] d_out,  // 32 bit D
	output reg [31:0] e_out   // 32 bit E
);

	wire [ 31:0] pipe_a [ 0:81];
	wire [ 31:0] pipe_b [ 0:81];
	wire [ 31:0] pipe_c [ 0:81];
	wire [ 31:0] pipe_d [ 0:81];
	wire [ 31:0] pipe_e [ 0:81];
	wire [511:0] mpipe  [ 0:81];

	assign pipe_a[1] = a_in_1;
	assign pipe_b[1] = b_in_1;
	assign pipe_c[1] = c_in_1;
	assign pipe_d[1] = d_in_1;
	assign pipe_d[0] = e_in;
	assign mpipe [0] = msg_in;

	// Delay ABCD inputs (PRE & POST stages are offseted one cycle
	reg [ 31:0] a_in_1, b_in_1, c_in_1, d_in_1;
	always @(posedge clk) begin
		a_in_1 <= a_in;
		b_in_1 <= b_in;
		c_in_1 <= c_in;
		d_in_1 <= d_in;
	end

	generate genvar sn;
	for (sn = 0; sn < 80; sn = sn + 1) begin : ST

		sha1_pre_stage #( .stagen(sn) ) sha1pre (
			.clk(clk),
			.d_in(pipe_d[sn]),
			.msg_in(mpipe[sn]), .msg_out(mpipe[sn+1]),
			.p_out(pipe_e[sn+1])
		);

		sha1_post_stage #( .stage_number(sn) ) sha1post (
			.clk(clk),

			.a_in(pipe_a[sn+1]), .b_in(pipe_b[sn+1]),
			.c_in(pipe_c[sn+1]), .d_in(pipe_d[sn+1]),
			.p_in(pipe_e[sn+1]),

			.a_out(pipe_a[sn+2]), .b_out(pipe_b[sn+2]),
			.c_out(pipe_c[sn+2]), .d_out(pipe_d[sn+2])
		);

	end
	endgenerate

	// Output calculation (endian swap them)
	// Need to add initial SHA1 state to get proper sha1_end result
	reg [ 31:0] e_out_1;
	always @(posedge clk) begin
		a_out <= pipe_a[81];
		b_out <= pipe_b[81];
		c_out <= pipe_c[81];
		d_out <= pipe_d[81];
		e_out_1 <= pipe_d[80];
		e_out <= e_out_1;
	end

endmodule

