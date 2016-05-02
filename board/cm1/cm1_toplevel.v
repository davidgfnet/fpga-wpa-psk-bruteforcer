`timescale 1ns / 1ps

// Icarus top level

module icarus_toplevel(
	input   input_clk,
	input   reset,

	// UART interface (to host)
	input   uart_rx,
	output  uart_tx,

	// Secondary UART (slave)
	input   aux_uart_rx,
	output  aux_uart_tx,

	// Switch config
	input [2:0] switch_config,

	// Some leds to ease debugging/supervision?
	output reg [3:0] led
);

// LED heartbeat relative to core_clk
reg [25:0] lcnt;
always @(posedge core_clk) begin
	lcnt <= lcnt + 1'b1;
	if (lcnt == 0)
		led <= ~led;
end

wire buffered_clk, core_clk, clk_100;

// Input buffering
IBUFG clkin1_buf (
	.O (buffered_clk),
	.I (input_clk)
);

// Simple PLL, just forwards the frequency
main_clk mainpll(buffered_clk, clk_100);

// Programmable clock
prog_clk corepll(
	.CLK_IN(buffered_clk),
	.CLK_OUT(core_clk),

	.PROGCLK(clk_100),
	.PROGDATA(prog_data[0]),
	.PROGEN(prog_en[0]),
	//.PROGDONE(),
	.RESET(reset)
);

// Frequency control
wire [16:0] fctl;
reg  [24:0] prog_data, prog_en;

always @(posedge clk_100) begin
	if (fctl[16]) begin
		// M is at 15:8, D at 7:0
		prog_data <= { 3'b000, fctl[15:8], 4'b1100, fctl[7:0], 2'b01 };
		prog_en   <= 25'b1001111111111001111111111;
	end
	else begin
		prog_en   <= { 1'b0, prog_en  [24:1] };
		prog_data <= { 1'b0, prog_data[24:1] };
	end
end

toplevel_bruteforcer bruteforcer(
	.clk(clk_100), .core_clk(core_clk),
	.reset(reset),
	.uart_rx(uart_rx), .uart_tx(uart_tx),
	.aux_uart_rx(aux_uart_rx), .aux_uart_tx(aux_uart_tx),
	.switch_config(switch_config),
	.freq_control(fctl)
);

endmodule

