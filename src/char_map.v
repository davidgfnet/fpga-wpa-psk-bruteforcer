
// Created by David Guillen Fandos
// david@davidgf.net
// You may use it as long as you share the sources

`timescale 1ns / 1ps

// This module maps 8 bit index to a byte (essentially a 256 byte memory)

module char_map(
	input         clk,

	// Read port
	input  [ 7:0] char_pos_rd,          // Char position to read

	// Write port
	input         wr_enable,
	input  [ 7:0] char_pos_wr,          // Char position to write
	input  [ 7:0] char_val_wr,          // Char value to write

	// Output for the read port
	output [ 7:0] msbyte_out            // 8 bit byte value
);

// Keep the map in flip flops
reg [7:0] regmap [0:255];

// Updates
always @(posedge clk)
begin
	if (wr_enable) begin
		regmap[char_pos_wr] <= char_val_wr;
	end
end

assign msbyte_out = regmap[char_pos_rd];

endmodule

