
// Created by David Guillen Fandos
// david@davidgf.net
// You may use it as long as you share the sources

`timescale 1ns / 1ps

// This is a handshake FIFO
// The FIFO has a synchronous write interface and an async
// read iface with a full handshake protocol (suitable for clock
// domain crossings). It uses a RAM so it is synthetisable friendly

module handshake_fifo #(
	parameter width = 16,       // Data size in bits
	parameter max_entries = 32, // Num mem entries
	parameter entrysz = 5       // Log2(Num entries) (set for 32 entries fifo)
)
(
	input clk,
	input clk_slave,
	input reset,

	// Write port
	input  [(width-1):0] wr_port,  // Data in port
	input                wr_req,   // Request to add data into the queue
	output reg           q_full,   // The queue is full (cannot write any more)

	// Read port
	output [(width-1):0] rd_port,  // Next data in the queue
	output               rd_ready, // The queue has at least one element!
	input                rd_ack    // The consumer ACKs that read is complete
);

// We can have up to max_entries-1 elements in the FIFO
reg  [(entrysz-1):0]  nentries;
reg  [(entrysz-1):0]  write_ptr, read_ptr;

ram_module #(.DATA(width), .ADDR(entrysz)) storage_instance (
	.a_clk(clk), .b_clk(clk),
	.a_wr(wr_req), .a_addr(write_ptr), .a_din(wr_port),
	.b_wr(1'b0), .b_addr(read_ptr), .b_dout(rd_port)
);

// ACK synchronizer (in and out)
wire rd_ack_qual;
synch s1 (clk, rd_ack, rd_ack_qual);
reg  i_rd_ready;
synch s2 (clk_slave, i_rd_ready, rd_ready);

wire wr_req_qual = wr_req && !q_full;
wire reading = (i_rd_ready && rd_ack_qual);
// Num entries for the next cycle
wire [(entrysz-1):0] nentries_next = (reading & !wr_req_qual) ? nentries - 1'b1 :
                                     (!reading & wr_req_qual) ? nentries + 1'b1 :
                                                                nentries;

always @(posedge clk) begin
	if (reset) begin
		write_ptr <= 0;
		read_ptr  <= 0;
		nentries  <= 0;
		i_rd_ready  <= 0;
	end
	else begin
		//assert(!reading || (nentries != 0));

		// We are sending data and just received the "read!" signal
		if (i_rd_ready && rd_ack_qual) begin
			// The reader ACKed us, decrement entries and deassert read
			i_rd_ready <= 0;
			read_ptr <= read_ptr + 1'b1;
		end

		// If FSM is idle, write i_rd_ready
		if (!i_rd_ready && !rd_ack_qual) begin
			i_rd_ready <= (nentries != 0);
		end
		
		nentries <= nentries_next;

		// Write ptr (do not overflow on full!)
		if (wr_req && !q_full)
			write_ptr <= write_ptr + 1'b1;

		// Full signal (when num entries it's ~0)
		q_full <= (nentries == ~0) || (nentries_next == ~0);
	end
end

initial $dumpvars(0, write_ptr);
initial $dumpvars(0, read_ptr);
initial $dumpvars(0, nentries);
initial $dumpvars(0, nentries_next);
initial $dumpvars(0, rd_ack_qual);
initial $dumpvars(0, rd_ack);
initial $dumpvars(0, q_full);
initial $dumpvars(0, rd_port);
initial $dumpvars(0, wr_req_qual);

endmodule

