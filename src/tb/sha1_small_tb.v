`timescale 1ns / 1ps

module sha1small_tb();

reg clk = 0;
reg reset = 1;

// Hello world sha1 string
wire [511:0] msg_raw;
assign msg_raw = { 128'h68656c6c6f20776f726c648000000000,
                   128'h00000000000000000000000000000000,
                   128'h00000000000000000000000000000000,
                   128'h00000000000000000000000000000058 };

// Expecting hash 2aae6c35c94fcfb415dbe95f408b9ce91ee846ed (without the adds)
// 2aae6c35 -> c3694934

wire [511:0] msg_in = {
	msg_raw[ 31:  0],
	msg_raw[ 63: 32],
	msg_raw[ 95: 64],
	msg_raw[127: 96],
	msg_raw[159:128],
	msg_raw[191:160],
	msg_raw[223:192],
	msg_raw[255:224],
	msg_raw[287:256],
	msg_raw[319:288],
	msg_raw[351:320],
	msg_raw[383:352],
	msg_raw[415:384],
	msg_raw[447:416],
	msg_raw[479:448],
	msg_raw[511:480]
};

initial begin
	$dumpvars(0, clk);
	$dumpvars(0, msg_in);
	$dumpvars(0, reset);
	$dumpvars(0, busy);
	$dumpvars(0, hash);

	# 350 $finish;
end

always #0.5 clk = !clk;
initial #10 reset = 0;

wire busy;
wire [159:0] hash;

sha1_small_core testpipe (
	.clk(clk),
	.reset(reset),
	.start(~reset),
	.busy(busy),
	.hash(hash),

	.msg(msg_in),
	.initial_status(160'h67452301efcdab8998badcfe10325476c3d2e1f0)
);

//wire valid;
//assign valid = (hash_a == 32'hc3694934);

endmodule

