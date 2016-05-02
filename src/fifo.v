
// Created by David Guillen Fandos
// david@davidgf.net
// You may use it as long as you share the sources

`timescale 1ns / 1ps

module fifo #(
	parameter width = 16,       // Data size in bits
	parameter max_entries = 32, // Num mem entries
	parameter entrysz = 5       // Log2(Num entries) (set for 32 entries fifo)
)
(
	input clk,
	input reset,

	// Write port
	input  [(width-1):0] wr_port,  // Data in port
	input                wr_req,   // Request to add data into the queue
	output               q_full,   // The queue is full (cannot write any more)

	// Read port
	output [(width-1):0] rd_port,  // Next data in the queue
	output               q_empty,  // The queue is empty! (cannot read!)
	input                rd_done   // The user read the current data within the queue
);

reg [(width-1):0] entries [0:(max_entries-1)];

initial $dumpvars(0, write_ptr);
initial $dumpvars(0, read_ptr);
initial $dumpvars(0, nentries);
initial $dumpvars(0, nentries_next);
initial $dumpvars(0, reading);
initial $dumpvars(0, writing);
initial $dumpvars(0, rd_port);

// The MSB bit of the rd/wr pointer is used for wraping purposes
// So when rd=wr means it's empty and when wr = rd + N (where N is
// queue size) means that it's full.

// N entries logic
reg  [entrysz:0]  nentries;
wire [entrysz:0]  nentries_next;

assign nentries_next = (reading & !writing) ? nentries - 1'b1 :
                       (!reading & writing) ? nentries + 1'b1 :
                                              nentries;

// Pointers logic
reg  [(entrysz-1):0]  write_ptr, read_ptr;
wire [(entrysz-1):0]  next_write_ptr, next_read_ptr;

assign next_write_ptr = (writing) ? write_ptr + 1'b1 : write_ptr;
assign next_read_ptr  = (reading) ? read_ptr  + 1'b1 :  read_ptr;

always @(posedge clk)
begin
	if (reset) begin
		nentries <= 0;
		read_ptr <= 0;
		write_ptr <= 0;
		int_q_empty <= 1;
	end else begin
		nentries <= nentries_next;
		read_ptr <= next_read_ptr;
		write_ptr <= next_write_ptr;
		int_q_empty <= next_q_empty;
	end
end

// Full & empty logic
reg  int_q_empty;

wire next_q_empty = ~(|nentries_next);

// Read & Write signals
wire writing = !q_full  &&  wr_req;
wire reading = !q_empty && rd_done;

reg [(width-1):0]   rd_port_int;

always @(posedge clk)
begin
	// Write port
	if (writing)
		entries[write_ptr] <= wr_port;

	// Read port
	if (q_empty)
		rd_port_int <= wr_port;
	else
		rd_port_int <= entries[next_read_ptr];
end

// OUTPUTS!

// Control signal for reader & writer
assign q_full = nentries[entrysz];
assign q_empty = int_q_empty;

// Read logic
assign rd_port = rd_port_int;

endmodule

