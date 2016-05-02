
// Created by David Guillen Fandos
// david@davidgf.net
// You may use it as long as you share the sources

`timescale 1ns / 1ps
`include "constants.vh"

// MD5 cracker instance toplevel entity

module toplevel_bruteforcer(
	input   clk,
	input   core_clk,
	input   reset,

	// UART interface (to host)
	input   uart_rx,
	output  uart_tx,

	// Secondary UART (slave)
	input   aux_uart_rx,
	output  aux_uart_tx,

	// Optional frequency control
	output reg [16:0] freq_control,

	// Switch config
	input [2:0] switch_config

	// Some leds to ease debugging/supervision?
);

initial begin
	$dumpvars(0, cmd_reg);
	$dumpvars(0, fsm_status);
	$dumpvars(0, uart_rx_ready);

	$dumpvars(0, device_reset);
	$dumpvars(0, uart_tx);
	$dumpvars(0, uart_rx_byte);
	$dumpvars(0, uart_tx_byte);
	$dumpvars(0, uart_tx_busy);

	$dumpvars(0, mic_out);
	$dumpvars(0, mic_reg);
	$dumpvars(0, mic_ready);

	$dumpvars(0, pmk_ready_high);
	$dumpvars(0, pmk_ready_low);

	$dumpvars(0, uartfifo_rd_port);
	$dumpvars(0, uartfifo_ready);
	$dumpvars(0, uartfifo_read);

	$dumpvars(0, uartfifo_fsm);

	$dumpvars(0, finish_counter);
	$dumpvars(0, recv_finished);
	$dumpvars(0, sent_finished);
end

always @(posedge clk)
	if (mic_ready && !sent_finished)
		$display("%h", mic_out);

// Config
wire [2:0] slave = switch_config;

// UART interface
wire       uart_rx_ready;
wire [7:0] uart_rx_byte;
reg        uart_tx_request;
wire       uart_tx_busy;
reg  [7:0] uart_tx_byte;

uart sys_uart(
	.clk(clk), .reset(reset),
	.rx(uart_rx), .tx(uart_tx),

	.tx_byte(uart_tx_byte), .tx_req(uart_tx_request), .tx_busy(uart_tx_busy),
	.rx_ready(uart_rx_ready), .rx_byte(uart_rx_byte)
);

// Uart TX logic
wire [39:0] uartfifo_rd_port, auxuartfifo_rd_port;
wire        uartfifo_ready, auxuartfifo_ready;
reg         uartfifo_read, auxuartfifo_read;
reg  [ 2:0] uartfifo_fsm;
reg  [ 1:0] uart_arb_token;
always @(posedge clk) begin
	uart_tx_request <= 0;

	if (reset) begin
		uartfifo_fsm <= 0;
		uart_arb_token <= 0;
		uartfifo_read <= 0;
		auxuartfifo_read <= 0;
	end
	else if (uart_arb_token == 0) begin
		// Arbitrate
		if (uartfifo_ready)
			uart_arb_token <= 2'b01;
		else if (auxuartfifo_ready)
			uart_arb_token <= 2'b10;
	end
	else if (!uart_tx_busy && !uart_tx_request && uart_arb_token[0]) begin
		if (uartfifo_fsm < 5) begin
			uart_tx_byte <= uartfifo_rd_port >> (uartfifo_fsm * 8);
			uart_tx_request <= 1;
			uartfifo_fsm <= uartfifo_fsm + 1'b1;
		end
		else begin
			if (uartfifo_read && !uartfifo_ready) begin
				uartfifo_read <= 0;
				uartfifo_fsm <= 0;
				uart_arb_token <= 0;
			end
			else if (!uartfifo_read) begin
				uartfifo_read <= 1;
			end
		end
	end
	else if (!uart_tx_busy && !uart_tx_request && uart_arb_token[1]) begin
		if (uartfifo_fsm < 5) begin
			uart_tx_byte <= auxuartfifo_rd_port >> (uartfifo_fsm * 8);
			uart_tx_request <= 1;
			uartfifo_fsm <= uartfifo_fsm + 1'b1;
		end
		else begin
			if (auxuartfifo_read && !auxuartfifo_ready) begin
				auxuartfifo_read <= 0;
				uartfifo_fsm <= 0;
				uart_arb_token <= 0;
			end
			else if (!auxuartfifo_read) begin
				auxuartfifo_read <= 1;
			end
		end
	end
end

// CMD reception and processing (2 bytes per command)
reg [ 15:0] cmd_reg;
reg [ 16:0] cmd_reg_devices;
reg [ 15:0] cmd_reg_fastdev;
reg         cmd_reg_rdy;
wire        cmd_reg_ack;
reg [  3:0] fsm_status;
reg [127:0] mic_reg;

reg  device_reset;
wire device_reset_core;
synch resetsync(core_clk, device_reset, device_reset_core);

wire [ 2:0] cracker_device = cmd_reg[15:13]; // 3 bits for the cracker id (overkill really)
wire [ 4:0] cmd_num        = cmd_reg[12: 8]; // 5 bits for the command (almost full)
wire [ 7:0] bpayload       = cmd_reg[ 7: 0]; // 8 bit payload

always @(posedge clk) begin
	cmd_reg_devices <= 0;
	freq_control <= { 1'b0, freq_control[15:0] };

	if (reset) begin
		fsm_status <= 0;
		device_reset <= 1;
	end else begin
		case (fsm_status)
		0: begin 
			if (uart_rx_ready) begin
				cmd_reg <= { 8'h00, uart_rx_byte };
				fsm_status <= 1;
			end
		end
		1: begin
			if (uart_rx_ready) begin
				cmd_reg <= { uart_rx_byte, cmd_reg[7:0] };
				fsm_status <= 2;
			end
		end
		default: begin
			// Read CMD and actuate accordingly
			fsm_status <= 0;
			case (cmd_num)
				`CMD_RESET: begin
					// Put devices on reset (clear & do nothing!)
					device_reset <= 1;
				end
				`CMD_START: begin
					// De-assert reset
					device_reset <= 0;
				end
				// Reference MIC to look for
				`CMD_PUSH_MIC_BYTE: begin
					mic_reg <= { mic_reg[119:0], bpayload };
				end
				// Core freq control bits
				`CMD_SET_CLK_M_VAL: begin
					freq_control <= { 1'b0, bpayload, freq_control[7:0] };
				end
				`CMD_SET_CLK_D_VAL: begin
					freq_control <= { 1'b1, freq_control[15:8], bpayload };
				end
			endcase
			// Propagate the command to the blocks (or zero, reset)
			cmd_reg_devices <= { (cracker_device == slave) ? 1'b1 : 1'b0, cmd_reg };
			cmd_reg_fastdev <= cmd_reg;
			cmd_reg_rdy <= 1;
		end
		endcase
	end

	if (cmd_reg_ack || reset) begin
		cmd_reg_rdy <= 0;
		cmd_reg_fastdev <= 0;
	end
end

// GEN_PIPE
// Chargen will generate charid + offset, then charmap will
// output the character byte itself.
// At the very end we get a char+offset for every MD5 pipe

wire [159:0] iopad_hash;
wire         pad_type;
wire         gen_ready;
wire         hash_read;
wire         fe_finished;
reg          recv_finished;
wire         recv_finished_core;

generation_pipe genpipe (
	.clk(clk), .device_reset(device_reset),
	.command(cmd_reg_devices),
	.hash_read(hash_read),
	.iopad_hash(iopad_hash), .pad_type(pad_type),
	.ready(gen_ready),
	.finished(fe_finished)
);

// Big hash pipe

wire [159:0] pmk_hash;
wire         pmk_step;
wire         pmk_ready;

bighashpipe hashpipe(
	.clk(core_clk),
	.global_reset(reset), .device_reset(device_reset_core || recv_finished_core),
	.command(cmd_reg_fastdev),
	.cmd_rdy(cmd_reg_rdy), .cmd_ack(cmd_reg_ack),

	.iopad_hash(iopad_hash), .pad_type(pad_type),
	.iready(gen_ready),
	.readack(hash_read),

	// I/O for the next pipe stage
	.pmk_hash(pmk_hash),
	.pmk_step(pmk_step),
	.ready(pmk_ready),

	// For finish tracking
	.fsync(hash_pipe_sync)
);

// PMK FIFO, here will sit waiting for MIC generation
// Split into two FIFOs (high and low bits are generated sequentially)

wire [159:0] pmk_read_high;
wire [ 95:0] pmk_read_low;

wire pmk_readack;
wire pmk_ready_high, pmk_ready_low;

handshake_fifo #(.width(160), .max_entries(256), .entrysz(8)) pmk_fifo_high (
	.clk(core_clk), .clk_slave(clk), .reset(device_reset_core),
	.wr_port(pmk_hash), .wr_req(pmk_ready && !pmk_step),
	.rd_port(pmk_read_high), .rd_ready(pmk_ready_high), .rd_ack(pmk_readack)
);
handshake_fifo #(.width( 96), .max_entries(256), .entrysz(8)) pmk_fifo_low (
	.clk(core_clk), .clk_slave(clk), .reset(device_reset_core),
	.wr_port(pmk_hash[159:64]), .wr_req(pmk_ready && pmk_step),
	.rd_port(pmk_read_low), .rd_ready(pmk_ready_low), .rd_ack(pmk_readack)
);

reg  [255:0] pmk_to_ptk_input;
wire pmk_to_ptk_ready = pmk_ready_high & pmk_ready_low;
reg  pmk_to_ptk_ready_delayed;

// Add a slow clk FF in here, to prevent metastability
// Enable signal should be metastability free :D
always @(posedge clk) begin
	if (pmk_to_ptk_ready)
		pmk_to_ptk_input <= { pmk_read_high, pmk_read_low };

	pmk_to_ptk_ready_delayed <= pmk_to_ptk_ready;
end

wire [127:0] mic_out;
wire         mic_ready;

// PMK to PTK to MIC block
pmk2mic miccalc(
	.clk(clk), .device_reset(device_reset),
	.command(cmd_reg_devices[15:0]),

	.pmk_valid(pmk_to_ptk_ready_delayed),
	.pmk(pmk_to_ptk_input),
	.readack(pmk_readack),

	.mic(mic_out),
	.ready(mic_ready)
);

// Finish (stop) logic (wait ~170*(8192*1.5) cycles)
// Note this runs at core_clk
wire hash_pipe_sync_int;
reg  hash_pipe_sync_int_prev;
reg  [2:0] finish_counter;

synch fs1(clk, hash_pipe_sync, hash_pipe_sync_int);
synch fs2(core_clk, recv_finished, recv_finished_core);

always @(posedge clk) begin
	hash_pipe_sync_int_prev <= hash_pipe_sync_int;
	recv_finished <= (finish_counter == 0);

	if (device_reset) begin
		finish_counter <= 3'h6;
	end
	else if (fe_finished && finish_counter != 0) begin
		if (hash_pipe_sync_int ^ hash_pipe_sync_int_prev) begin
			finish_counter <= finish_counter - 1'b1;
		end
	end
end


// MIC match logic
reg [31:0] word_counter;
reg [40:0] int_tx_msg;
reg sent_finished;

always @(posedge clk) begin
	int_tx_msg <= { 1'b0, 40'hx };

	if (device_reset) begin
		word_counter <= -167; // To match pipe inflight
		sent_finished <= 0;
	end

	if (mic_ready && !sent_finished) begin
		word_counter <= word_counter + 1'b1;

		if (mic_reg == mic_out) begin
			int_tx_msg <= { 1'b1, slave, `RESP_HIT, word_counter };
			$display("Got hit %h", word_counter);
		end
	end
	else if (recv_finished && !sent_finished) begin
		int_tx_msg <= { 1'b1, slave, `RESP_FINISHED, 32'h0 };
		$display("Finished!");
		sent_finished <= 1;
	end
end

handshake_fifo #(.width(40), .max_entries(64), .entrysz(6)) word_match_fifo (
	.clk(clk), .clk_slave(clk), .reset(device_reset),
	.wr_port(int_tx_msg[39:0]), .wr_req(int_tx_msg[40]),
	.rd_port(uartfifo_rd_port), .rd_ready(uartfifo_ready), .rd_ack(uartfifo_read)
);

// Secondary UART
wire       aux_uart_rx_ready;
wire [7:0] aux_uart_rx_byte;

reg  [40:0] aux_uart_tx_byte;
reg  [ 4:0] aux_fsm_counter;

uart aux_uart(
	.clk(clk), .reset(reset),
	.rx(aux_uart_rx),

	.tx_req(1'b0),
	.rx_ready(aux_uart_rx_ready), .rx_byte(aux_uart_rx_byte)
);

always @(posedge clk) begin
	if (aux_fsm_counter == 0 || device_reset)
		aux_fsm_counter <= 5;

	// Disable write
	aux_uart_tx_byte <= { 1'b0, aux_uart_tx_byte[39:0] };

	if (!device_reset) begin
		if (aux_uart_rx_ready) begin
			aux_uart_tx_byte <= {
				aux_fsm_counter == 1 ? 1'b1 : 1'b0,
				aux_uart_rx_byte, aux_uart_tx_byte[39:8]
			};
			aux_fsm_counter <= aux_fsm_counter - 1'b1;
		end
	end
end

handshake_fifo #(.width(40), .max_entries(64), .entrysz(6)) auxuart_fifo (
	.clk(clk), .clk_slave(clk), .reset(device_reset),
	.wr_port(aux_uart_tx_byte[39:0]), .wr_req(aux_uart_tx_byte[40]),
	.rd_port(auxuartfifo_rd_port), .rd_ready(auxuartfifo_ready), .rd_ack(auxuartfifo_read)
);

// Forward TX pin
assign aux_uart_tx = uart_rx;

endmodule


