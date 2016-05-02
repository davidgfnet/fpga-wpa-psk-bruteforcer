`timescale 1ns / 1ps

module sha1_tb();

function [511:0] word_swizzle;
	input [511:0] inword;
	word_swizzle = {
		inword[ 31:  0],
		inword[ 63: 32],
		inword[ 95: 64],
		inword[127: 96],
		inword[159:128],
		inword[191:160],
		inword[223:192],
		inword[255:224],
		inword[287:256],
		inword[319:288],
		inword[351:320],
		inword[383:352],
		inword[415:384],
		inword[447:416],
		inword[479:448],
		inword[511:480]
	};
endfunction

reg clk = 0;
reg [1:0] sel = 0;
// Hello world sha1 string
wire [511:0] msg_raw = { 128'h68656c6c6f20776f726c648000000000,
                         128'h00000000000000000000000000000000,
                         128'h00000000000000000000000000000000,
                         128'h00000000000000000000000000000058 };
wire [511:0] msg_raw2= { 128'h68656c6c6c20776f726c648000000000,
                         128'h00000000000000000000000000000000,
                         128'h00000000000000000000000000000000,
                         128'h00000000000000000000000000000058 };

// Expecting hash 2aae6c35c94fcfb415dbe95f408b9ce91ee846ed (without the adds)
// 2aae6c35 -> c3694934

wire [511:0] msg_in = word_swizzle(sel[0] ? msg_raw : msg_raw2);

initial begin
	//$dumpfile("md5tb.vcd");
	$dumpvars(0, clk);
	$dumpvars(0, msg_in);
	$dumpvars(0, hash_a);
	$dumpvars(0, hash_b);
	$dumpvars(0, hash_c);
	$dumpvars(0, hash_d);
	$dumpvars(0, hash_e);

	$dumpvars(0, valid);
	$dumpvars(0, valid2);

	# 10000 $finish;
end

always #0.5 clk = !clk;

always @(posedge clk)
	sel <= sel + 1;

wire [31:0] hash_a;
wire [31:0] hash_b;
wire [31:0] hash_c;
wire [31:0] hash_d;
wire [31:0] hash_e;

sha1_pipeline testpipe (
	.clk(clk),

	.msg_in(msg_in),

	.a_in(32'h67452301), .b_in(32'hefcdab89),
	.c_in(32'h98badcfe), .d_in(32'h10325476),
	.e_in(32'hc3d2e1f0),

	.a_out(hash_a), .b_out(hash_b),
	.c_out(hash_c), .d_out(hash_d),
	.e_out(hash_e)
);

wire valid  = (hash_a + 32'h67452301 == 32'h2aae6c35);
wire valid2 = (hash_a + 32'h67452301 == 32'hc7fa8d5b);

endmodule

