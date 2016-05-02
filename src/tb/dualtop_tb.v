`timescale 1ns / 1ps

// WPA cracker instance toplevel entity

module dualtoplevel_tb();

// UART interface
wire rx = 1;
wire tx;
reg clk = 1, reset = 1;

reg tx_req;
wire tx_busy;
reg [7:0] tx_byte;

wire br_1to2;
wire br_2to1;
wire tohost;

toplevel_bruteforcer test1 (
	.clk(clk), .core_clk(clk),
	.reset(reset),
	.uart_rx(tx),
	.uart_tx(tohost),
	.aux_uart_rx(br_2to1),
	.aux_uart_tx(br_1to2),
	.switch_config(3'h0)
);

toplevel_bruteforcer test2 (
	.clk(clk), .core_clk(clk),
	.reset(reset),
	.uart_rx(br_1to2),
	.uart_tx(br_2to1),
	.aux_uart_rx(1'b1),
	.switch_config(3'h1)
);

uart test_uart(
	.clk(clk), .reset(reset),
	.rx(rx), .tx(tx),

	.tx_byte(tx_byte), .tx_req(tx_req), .tx_busy(tx_busy)
);

`define TESTB_SIZE  1694

reg [7:0] uart_data  [0: `TESTB_SIZE-1];

initial begin
	$readmemh("toplevel.vectors", uart_data);

	$dumpvars(0, tx);
	$dumpvars(0, rx);
	$dumpvars(0, clk);
	$dumpvars(0, reset);

	$dumpvars(0, tx_busy);
	$dumpvars(0, tx_req);
	$dumpvars(0, tx_byte);
	$dumpvars(0, fsm_state);

	$dumpvars(0, tohost);

	$dumpvars(0, br_1to2);
	$dumpvars(0, br_2to1);

	# 440000000 $finish;
end

always #20 clk = !clk;
always #200 reset = 0;

initial #220000000 fsm_state = 0;

reg [15:0] fsm_state  =  0;

always @(posedge clk) begin
	tx_req <= 0;
	if (reset) begin
		fsm_state  <= 0;
	end else begin
		if (fsm_state < `TESTB_SIZE) begin
			if (!tx_busy && !tx_req) begin
				tx_req <= 1;
				tx_byte <= uart_data[fsm_state];
				fsm_state <= fsm_state + 1;
			end else begin
				tx_req <= 0;
			end
		end

	end
end

endmodule

