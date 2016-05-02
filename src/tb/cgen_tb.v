`timescale 1ns / 1ps

module cgen_tb();

reg clk = 0;
reg reset = 1;

initial begin
	//$dumpfile("md5tb.vcd");
	$dumpvars(0, clk);
	$dumpvars(0, word_counter);

	$dumpvars(0, valid);
	$dumpvars(0, finished);
	$dumpvars(0, char_offset);
	$dumpvars(0, char_value);

	# 20000 $finish;
end

always #0.5 clk = !clk;

initial #10 reset = 0;

wire [31:0] word_counter;
wire        valid;
wire        finished;
wire [6:0] char_value;
wire [3:0] char_offset;

char_gen testm(
	.clk(clk),
	.reset(reset),

	.start_offset(0),
	.max_characters(4),
	.charset_size(7),
	.advance_next(1),

	.word_counter(word_counter),
	.valid(valid),
	.finished(finished),

	.char_offset(char_offset),
	.char_value(char_value)

);

endmodule

