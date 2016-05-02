
// Created by David Guillen Fandos
// david@davidgf.net
// You may use it as long as you share the sources

`timescale 1ns / 1ps

// This UART instance is able to send and receive
// The RX/TX buffer is just one byte, since the It has a byte queue for received data and for TX data too

module uart(
	input       clk,       // Assuming 25Mhz clock!
	input       reset,

	input       rx,        // Mapped to I/O RX input pin
	output reg  tx,        // Mapped to I/O TX output pin

	// TX
	input [7:0] tx_byte,  // Byte to send
	input       tx_req,   // Do send now!
	output reg  tx_busy,  // Busy sending stuff

	// RX
	output reg  rx_ready, // Just received some byte!
	output reg [7:0] rx_byte   // The received byte
);

initial begin
	$dumpvars(0, tx_tick_count);
	$dumpvars(0, out_buffer);
	$dumpvars(0, tx_fsm);
end

// Config for this UART
parameter clock_freq = 25000000;
parameter baud_rate =   2500000;  //115200;
parameter counter_max = clock_freq / baud_rate;
parameter counter_sample = counter_max / 2;

// RX pin is triple buffered
reg rx_in1, rx_in2, rx_in;
always @(posedge clk)
begin
	if (reset) begin
		rx_in  <= 1;
		rx_in2 <= 1;
		rx_in1 <= 0;
	end else begin
		rx_in  <=  rx_in2;
		rx_in2 <= ~rx_in1;
		rx_in1 <= ~rx;
	end
end

// RX pin is filtered using a sliding window majority vote.
reg [6:0] rx_queue; // 7 bits

always @(posedge clk)
begin
	if (reset)
		rx_queue <= 7'b1111111;
	else
		rx_queue <= { {rx_queue[5:0]}, {rx_in} };
end

// 7b window, popcount (check MSB bit)
wire [2:0] rx_wnd_cnt;
wire rx_filtered;
assign rx_wnd_cnt = rx_queue[0] + rx_queue[1] +
					rx_queue[2] + rx_queue[3] +
					rx_queue[4] + rx_queue[5] +
					rx_queue[6];
assign rx_filtered = rx_wnd_cnt[2];


// RX logic. Wait for start bit (zero in RX) before
reg [ 3:0] fsm_state;
reg [ 9:0] received_bits;
reg [15:0] bit_sample_count;
always @(posedge clk)
begin
	// RX ready is signaled for a one cycle pulse
	rx_ready <= 0;

	if (reset) begin
		fsm_state <= 0;
	end else begin
		// For the first state (wait for start bit)
		if (fsm_state == 4'h0) begin
			if (!rx_filtered) begin
				bit_sample_count <= 0;
				fsm_state <= 4'h1;
			end
		end else if (fsm_state == 4'hB) begin
			// After the stop bit, we wait for a 1 (line idle)
			if (rx_filtered) begin
				fsm_state <= 4'h0;
				if (received_bits[0] == 0 && received_bits[9] == 1) begin
					rx_byte <= received_bits[8:1];
					rx_ready <= 1;
				end
			end
		end else begin
			// Sample at the middle point and keep counting
			bit_sample_count <= bit_sample_count + 1'b1;
			if (bit_sample_count == counter_sample) begin
				received_bits <= { {rx_filtered}, {received_bits[9:1]} };
			end else if (bit_sample_count == counter_max) begin
				fsm_state <= fsm_state + 1'b1;
				bit_sample_count <= 0;
			end
		end
	end
end

// TX logic.
reg [10:0] out_buffer;
reg [ 4:0] tx_fsm;
reg [15:0] tx_tick_count;
reg [ 7:0] tx_out_serial;
always @(posedge clk)
begin
	// Use an 8 reg pipeline for the TX pin
	tx_out_serial[7:1] <= tx_out_serial[6:0];
	tx <= tx_out_serial[7];

	if (reset) begin
		tx_out_serial <= ~0;
		tx_busy <= 0;
	end else if (tx_req && !tx_busy) begin
		out_buffer <= { 2'b11, tx_byte, 1'b0 };
		tx_busy <= 1;
		tx_fsm <= 4'h0;
		tx_tick_count <= 16'h0000;
	end else if (tx_busy) begin
		tx_out_serial[0] <= out_buffer[0];
		if (tx_tick_count == counter_max) begin
			tx_tick_count <= 0;
			tx_fsm <= tx_fsm + 1'b1;
			out_buffer <= { 1'b1, out_buffer[10:1] };
		end else begin
			tx_tick_count <= tx_tick_count + 1'b1;
		end 
		if (tx_fsm == 11) // Use 2 stop bits, just in case...
			tx_busy <= 0;
	end
end

endmodule

