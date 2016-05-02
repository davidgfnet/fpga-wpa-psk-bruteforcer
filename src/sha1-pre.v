
// Created by David Guillen Fandos
// david@davidgf.net
// You may use it as long as you share the sources

`timescale 1ns / 1ps

module sha1_pre_stage(
	input         clk,

	input  [ 31:0] d_in,   // 32 bit D[i-1]

	input  [511:0] msg_in,    // 512 bit msg
	output [511:0] msg_out,   //

	output [31:0] p_out    // 32 bit P[i] (replaces E[i])
);

// Parameters to instance the stage
parameter stagen = 0;    // This is our "i"

// Calculate k_i
wire [31:0] k_i;
assign k_i = (stagen < 20) ? 32'h5A827999 :
             (stagen < 40) ? 32'h6ED9EBA1 :
             (stagen < 60) ? 32'h8F1BBCDC :
                             32'hCA62C1D6 ;

// Calculate w[i]
wire [31:0] w_i_calc_1;
wire [31:0] w_i_calc_2;
assign w_i_calc_1 = msg_in[31+32* 0:32* 0] ^
                    msg_in[31+32* 2:32* 2] ^
                    msg_in[31+32* 8:32* 8] ^
                    msg_in[31+32*13:32*13];
assign w_i_calc_2 = { w_i_calc_1[30:0], w_i_calc_1[31] };

// Select w[i] or w[0] for window shift stage
wire [31:0] w_i;
assign w_i = (stagen < 16) ? msg_in[31+32*stagen:32*stagen] : msg_in[511:480];

// Add 3 terms up
wire [31:0] p_i;
assign p_i = w_i + k_i + d_in;  // This is w[i] + k + e (a and f remaining!)

// Internal FF stage (32 bit) + ~512bit (less depending on zeros!)
reg  [31:0] p;
reg [511:0] msg_reg;
always @(posedge clk)
begin
	p <= p_i;
	if (stagen < 15)
		msg_reg <= msg_in;
	else
		msg_reg <= { w_i_calc_2, msg_in[511:32] };
end

// Output
assign p_out = p;
assign msg_out = msg_reg;

endmodule

