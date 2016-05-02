
// Created by David Guillen Fandos
// david@davidgf.net
// You may use it as long as you share the sources

`timescale 1ns / 1ps

// This is the PMK to MIC calculator
// It takes a PMK and the PKE message (MACs & nonces) and calculates a PTK
// Then it uses the EAPOL message and the PTK to get the MIC
// It has 8192 cycles to complete the conversion in order to guarantee
// that the input FIFO will never overflow.

`define FSM_WAIT       3'h0
`define FSM_FETCH      3'h1
`define FSM_EXEC1      3'h2
`define FSM_EXEC2      3'h3
`define FSM_WB         3'h4
`define FSM_EXEC_WAIT  3'h5

`include "constants.vh"

module pmk2mic(
	input  clk,
	input  device_reset,

	// Interface to toplevel controller
	input  [15:0] command,

	// Input/Output from/to generator
	input         pmk_valid,
	input [255:0] pmk,
	output reg    readack,    // ACK that we read the hash!

	// MIC output
	output reg  [127:0] mic,   // MIC hash
	output reg          ready  // MIC is valid!
);

`include "util.vh"

// Decode CMD
wire [6:0] cmdid   = command[12:8];
wire [7:0] payload = command[ 7:0];

// Initial programming and setup
reg [ 6:0] work_addr_value;
reg        work_addr_enable;
reg [ 3:0] ucode_addr_value;
reg        ucode_addr_enable;

reg [31:0] prog_scratch_reg;

always @(posedge clk) begin
	work_addr_enable  <= 0;
	ucode_addr_enable <= 0;

	case (cmdid)
	`CMD_WR_REG_ADDR: begin
		work_addr_value  <= payload[6:0];
		ucode_addr_value <= payload[3:0];

		work_addr_enable  <= ~payload[7];
		ucode_addr_enable <=  payload[7];
	end

	// Write byte and push left others
	`CMD_WR_REG_LSB:
		prog_scratch_reg <= { prog_scratch_reg[23:0], payload };
	endcase
end

// Working RAM
// Addr  0- 31 contains PKE message (padded 8'h80, 200'h0, 16'h0520) up to 32 bytes
// Addr 32-127 contains EAPOL message (up to 384 bytes)


reg  [ 6:0] reg_read_addr;
wire [31:0] reg_read_value;
ram_module #( .DATA(32), .ADDR(7) ) register_ram (
	.a_clk(clk), .b_clk(clk),
	.a_wr(work_addr_enable),
	.a_addr(work_addr_value),
	.a_din(prog_scratch_reg),
	.b_wr(1'b0),
	.b_addr(reg_read_addr),
	.b_dout(reg_read_value)
);

// uCode RAM
reg  [  3:0] inst_pc;
wire [  7:0] inst_word;
ram_module #( .DATA(8), .ADDR(4) ) ucode_ram (
	.a_clk(clk), .b_clk(clk),
	.a_wr(ucode_addr_enable),
	.a_addr(ucode_addr_value),
	.a_din(prog_scratch_reg[7:0]),
	.b_wr(1'b0),
	.b_addr(inst_pc),
	.b_dout(inst_word)
);

// This is a microcoded machine
// It uses 8 bit instruction words to process hashes, see driver!
// Bit 7:   0 selects constant, 1 selects output from previous hash output
// Bit 6-5: 00 does not write scratch reg, 10 writes hash + 80, 11 writes hash + 0
// Bit 4:   Trigger SHA1 and wait for result, otherwise will skip SHA1 (useful for WB!)
// Bit 3:   use scratch (1) or initial_reg (0)
// Bit 2-0: register addr (if bit 3 cleared) / xor value

// FSM: Step by step create the output hash
reg [255:0] scratch_reg;
reg [511:0] hash_input_reg;

reg          sha1_start;
wire [159:0] hash_output;

reg [2:0] ucode_fsm;
always @(posedge clk) begin
	ready <= 0;
	sha1_start <= 0;

	if (device_reset) begin
		ucode_fsm <= `FSM_WAIT;
		readack <= 0;
	end else begin
		// FIFO ack flow
		if (!pmk_valid && readack)
			readack <= 0;

		case (ucode_fsm)
		`FSM_WAIT: begin
			// Wait for PMK ready
			if (pmk_valid && !readack) begin
				scratch_reg <= pmk;
				readack <= 1;
				ucode_fsm <= `FSM_FETCH;
				inst_pc <= 0;
			end
		end

		// Wait for RAM read into inst_word
		`FSM_FETCH:
			ucode_fsm <= `FSM_EXEC1;

		// Exec stages will copy registers into input_reg
		`FSM_EXEC1: begin
			reg_read_addr <= { inst_word[2:0], 4'h0 };
			ucode_fsm <= `FSM_EXEC2;
		end
		// Start the hashing core and wait!
		`FSM_EXEC2: begin
			reg_read_addr <= reg_read_addr + 1'b1;
			hash_input_reg <= { hash_input_reg[479:0], reg_read_value };
			if (reg_read_addr[6:4] != inst_word[2:0]) begin
				if (!inst_word[4])
					sha1_start <= 1;

				ucode_fsm <= `FSM_WB;
			end
		end

		`FSM_WB: begin
			// Writeback
			if (inst_word[6]) begin
				if (!inst_word[5]) begin
					scratch_reg <= { hash_output, 8'h80, 88'h0 };
				end
				else begin
					scratch_reg <= { hash_output[159:32], 128'h0 };
				end
			end
			ucode_fsm <= `FSM_EXEC_WAIT;
		end

		// Wait for sha1 ready and writeback if necessary
		`FSM_EXEC_WAIT: begin
			if (sha1_done || inst_word[4]) begin
				// Halt?
				if (&inst_pc) begin
					ucode_fsm <= `FSM_WAIT;
					ready <= 1;
					mic <= hash_output[159:32];
				end
				else begin
					ucode_fsm <= `FSM_FETCH;
					inst_pc <= inst_pc + 1'b1;
				end
			end
		end
		endcase
	end
end

// Init value give by inst word directly
wire [159:0] hash_init_state = inst_word[7] ? hash_output : 160'h67452301efcdab8998badcfe10325476c3d2e1f0;

// XOR value selection
wire [  7:0] xor_sel   = inst_word[0] ? 8'h5c : 8'h36;
wire [  7:0] xor_value = inst_word[1] ? xor_sel : 8'h00;

// Scratch padding selection
wire [255:0] scratch_padding = inst_word[2] ? ({240'h0, 16'h02A0}) : 256'h0;
wire [511:0] hash_input = inst_word[3] ? ( {64{xor_value}} ^ { scratch_reg, scratch_padding } ) : hash_input_reg;

sha1_small_core sha1core (
	.clk(clk), .reset(device_reset),
	.start(sha1_start),
	.done(sha1_done),

	// Actual data, 512 bits (beware the order and endianess!)
	.msg(word_swizzle(hash_input)),

	// SHA1 first block initial values
	.initial_status(hash_init_state),
	.hash(hash_output)
);


initial begin
	$dumpvars(0, hash_output);
	$dumpvars(0, work_addr_value);
	$dumpvars(0, work_addr_enable);
	$dumpvars(0, ucode_addr_value);
	$dumpvars(0, ucode_addr_enable);
	$dumpvars(0, prog_scratch_reg);
	$dumpvars(0, inst_pc);
	$dumpvars(0, inst_word);
	$dumpvars(0, ucode_fsm);
	$dumpvars(0, hash_input);
	$dumpvars(0, hash_init_state);
	$dumpvars(0, sha1_start);
	$dumpvars(0, hash_input_reg);
	$dumpvars(0, reg_read_addr);
end

endmodule


