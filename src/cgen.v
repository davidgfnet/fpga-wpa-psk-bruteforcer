
// Created by David Guillen Fandos
// david@davidgf.net
// You may use it as long as you share the sources

`timescale 1ns / 1ps

module char_gen(
	input         clk,
	input         reset,

	// Setup inputs, only used at reset
	input  [ 3:0] max_characters,       // Max number of characters to bruteforce (minus 1)
	input  [ 7:0] charset_size,         // Number of characters (minimum should be 2, 4 to be safe)
	input         advance_next,         // Move to next word

	// Running outputs
	output reg [ 31:0] word_counter,  // 32 bit counter to identify the current message (1+ days at 200MHz, enough!)
	output reg [  3:0] char_offset,   // 4 bit char updated position
	output reg [  7:0] char_value,    // 8 bit update char value
	output reg         valid,
	output reg         finished
);

initial $dumpvars(0, fsm_status);
initial $dumpvars(0, current_ptr);
initial $dumpvars(0, word_status[0]);
initial $dumpvars(0, word_status[1]);
initial $dumpvars(0, word_status[2]);
initial $dumpvars(0, word_status[3]);
initial $dumpvars(0, updw_counters);
initial $dumpvars(0, ovfw_mask);

reg [6:0] word_status [0:15];
reg [1:0] fsm_status;
reg [3:0] current_ptr;
reg       ptr_ovfw;
reg [6:0] updated_value;

reg [15:0] updw_counters;
reg [15:0] ovfw_mask;

integer g;

// General counting happens here
always @(posedge clk) begin
	if (reset | finished) begin
		current_ptr <= 0;
		word_counter <= 0;
		char_offset <= 0;
		char_value <= 0;
		valid <= 1;
		updw_counters <= 0;
		ovfw_mask <= 0;
		for (g = 0; g < 16; g = g + 1) begin
			word_status[g] <= 0;
		end
		if (reset)
			finished <= 0;
	end else begin
		if (!valid) begin
			case (fsm_status)
			0: begin
				// Increment/decrement current char
				updated_value <= word_status[current_ptr] + (updw_counters[current_ptr] ? 7'h7F : 7'h01);
			end
			1: begin
				// Check overflow/underflow
				if ( (updated_value == 0              &&  updw_counters[current_ptr]) ||
				     (updated_value == charset_size-1 && !updw_counters[current_ptr]) ) begin

					updw_counters <= updw_counters ^ (16'h1 << current_ptr);
					ovfw_mask     <= ovfw_mask     | (16'h1 << current_ptr);
				end
				word_status[current_ptr] <= updated_value;
				// Update outputs as well

				char_offset <= current_ptr;
				char_value <= updated_value;
			end
			2: begin
				// Find longest set sequence, mark finished too
				{ptr_ovfw, current_ptr} <= (ovfw_mask[15:0] == ~16'b0) ? 5'h1F :
				                           (ovfw_mask[14:0] == ~15'b0) ? 5'h0F :
				                           (ovfw_mask[13:0] == ~14'b0) ? 5'h0E :
				                           (ovfw_mask[12:0] == ~13'b0) ? 5'h0D :
				                           (ovfw_mask[11:0] == ~12'b0) ? 5'h0C :
				                           (ovfw_mask[10:0] == ~11'b0) ? 5'h0B :
				                           (ovfw_mask[ 9:0] == ~10'b0) ? 5'h0A :
				                           (ovfw_mask[ 8:0] == ~ 9'b0) ? 5'h09 :
				                           (ovfw_mask[ 7:0] == ~ 8'b0) ? 5'h08 :
				                           (ovfw_mask[ 6:0] == ~ 7'b0) ? 5'h07 :
				                           (ovfw_mask[ 5:0] == ~ 6'b0) ? 5'h06 :
				                           (ovfw_mask[ 4:0] == ~ 5'b0) ? 5'h05 :
				                           (ovfw_mask[ 3:0] == ~ 4'b0) ? 5'h04 :
				                           (ovfw_mask[ 2:0] == ~ 3'b0) ? 5'h03 :
				                           (ovfw_mask[ 1:0] == ~ 2'b0) ? 5'h02 :
				                           (ovfw_mask[   0] == ~ 1'b0) ? 5'h01 : 5'h00;
			end
			3: begin
				// Clear bits
				finished <= ptr_ovfw | (current_ptr == max_characters);
				valid <= 1;
				ovfw_mask <= ovfw_mask & ( (current_ptr == 4'hF) ? 16'h8000 :
				                           (current_ptr == 4'hE) ? 16'hC000 :
				                           (current_ptr == 4'hD) ? 16'hE000 :
				                           (current_ptr == 4'hC) ? 16'hF000 :
				                           (current_ptr == 4'hB) ? 16'hF800 :
				                           (current_ptr == 4'hA) ? 16'hFC00 :
				                           (current_ptr == 4'h9) ? 16'hFE00 :
				                           (current_ptr == 4'h8) ? 16'hFF00 :
				                           (current_ptr == 4'h7) ? 16'hFF80 :
				                           (current_ptr == 4'h6) ? 16'hFFC0 :
				                           (current_ptr == 4'h5) ? 16'hFFE0 :
				                           (current_ptr == 4'h4) ? 16'hFFF0 :
				                           (current_ptr == 4'h3) ? 16'hFFF8 :
				                           (current_ptr == 4'h2) ? 16'hFFFC :
				                           (current_ptr == 4'h1) ? 16'hFFFE : 16'hFFFF );
			end
			endcase

			fsm_status <= fsm_status + 1;
		end
		else if (advance_next) begin
			// Start FSM to calculate the next word
			valid <= 0;
			fsm_status <= 0;
			word_counter <= word_counter + 1'b1;
		end
	end
end

endmodule

