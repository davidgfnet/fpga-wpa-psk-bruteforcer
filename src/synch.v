
// Created by David Guillen Fandos
// david@davidgf.net
// You may use it as long as you share the sources

`timescale 1ns / 1ps

// Basic N depth synchronizer

module synch #(parameter depth = 10)
(
	input  clk,
	input  in,
	output out
);

// ACK synchronizer
//ASYNC_REG = "TRUE", 
(* SHIFT_EXTRACT="NO", OPTIMIZE ="OFF", KEEP="yes" *)
reg  [(depth-1):0] istate;

always @(posedge clk)
	istate <= { in, istate[(depth-1):1] };

assign out = istate[0];

endmodule

