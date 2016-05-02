
// Created by David Guillen Fandos
// david@davidgf.net
// You may use it as long as you share the sources

`timescale 1ns / 1ps

module sha1_post_stage(
	input         clk,

	input  [31:0] a_in,       // 32 bit A[i]
	input  [31:0] b_in,       // 32 bit B[i]
	input  [31:0] c_in,       // 32 bit C[i]
	input  [31:0] d_in,       // 32 bit D[i]
	input  [31:0] p_in,       // 32 bit P[i] (input from "current" stage)

	output [31:0] a_out,      // 32 bit A[i] (outputs to next stage)
	output [31:0] b_out,      // 32 bit B[i]
	output [31:0] c_out,      // 32 bit C[i]
	output [31:0] d_out       // 32 bit D[i]
);

// Parameters to instance the stage
parameter stage_number = 0;  // This is our "i"

// Calculate f_i
wire [31:0] f_i;
assign f_i = (stage_number < 20) ? (b_in & c_in) | ((~b_in) & d_in)              :
             (stage_number < 40) ?  b_in ^ c_in ^ d_in                           :
             (stage_number < 60) ? (b_in & c_in) | (b_in & d_in) | (c_in & d_in) :
                                    b_in ^ c_in ^ d_in                           ;

// Rotate A before adding it
wire [31:0] a_rot;
assign a_rot = {a_in[26:0], a_in[31:27]};

// Actual calculation
wire [31:0] a_next;
assign a_next = f_i + a_rot + p_in;

// B gets rotated into C
wire [31:0] c_next;
assign c_next = { b_in[1:0], b_in[31:2] };

reg [ 31:0] a_reg;
reg [ 31:0] b_reg;
reg [ 31:0] c_reg;
reg [ 31:0] d_reg;

// Update internal state
// This pipestage contains 32b*4 = 128b
always @(posedge clk)
begin
	a_reg <= a_next;
	b_reg <= a_in;
	c_reg <= c_next;
	d_reg <= c_in;
end

// Output
assign a_out = a_reg;
assign b_out = b_reg;
assign c_out = c_reg;
assign d_out = d_reg;

endmodule

