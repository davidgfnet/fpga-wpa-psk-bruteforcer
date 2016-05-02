`timescale 1ns / 1ps

module genpipe_tb();

reg clk = 0;
reg reset = 1;

initial begin
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



