
// Created by David Guillen Fandos
// david@davidgf.net
// You may use it as long as you share the sources

`timescale 1ns / 1ps

// This small core is dual-stage.
// It generates 2 hashes every 65 clocks
// Used to generate initial SHA1 state for PBKDF2-HMAC

module sha1_small_core(
	input         clk,
	input       reset,
	input       start,

	input  [159:0] initial_status,  // 160 bit initial sha1 status
	input  [511:0] msg,             // 512 bit message

	output reg [159:0] hash,  // 160 bit hash result (internal state! No final hash!)
	output reg         busy,
	output reg         done
);

initial $dumpvars(0, fsm_status);
initial $dumpvars(0, msg);
initial $dumpvars(0, internal_message);
initial $dumpvars(0, a1);
initial $dumpvars(0, b1);
initial $dumpvars(0, c1);
initial $dumpvars(0, d1);
initial $dumpvars(0, e1);
initial $dumpvars(0, a2);
initial $dumpvars(0, b2);
initial $dumpvars(0, c2);
initial $dumpvars(0, d2);
initial $dumpvars(0, e2);
initial $dumpvars(0, a3);
initial $dumpvars(0, b3);
initial $dumpvars(0, c3);
initial $dumpvars(0, d3);
initial $dumpvars(0, e3);


// FSM controls
reg [  6:0] fsm_status;
reg [159:0] initial_state;
reg [511:0] internal_message;

always @(posedge clk) begin
	done <= 0;

	if (reset) begin
		busy <= 0;
	end else begin
		if (!busy && start) begin
			// Machinery start
			busy <= 1;
			fsm_status <= 0;
			initial_state <= initial_status;
			internal_message <= msg;
		end
		else if (busy) begin
			fsm_status <= fsm_status + 1'b1;
			if (fsm_status == 80) begin
				busy <= 0;
				done <= 1;
				hash <= {
					a3 + initial_state[159:128], 
					b3 + initial_state[127: 96],
					c3 + initial_state[ 95: 64],
					d3 + initial_state[ 63: 32],
					e3 + initial_state[ 31:  0]
				};
			end
			internal_message <= { w_i_calc_2, internal_message[511:32] };
		end
	end
end

// Stage 1 (pre-stage)
wire [31:0] a1, b1, c1, d1, e1;
assign a1 = (fsm_status == 0) ? initial_state[159:128] : a3;
assign b1 = (fsm_status == 0) ? initial_state[127: 96] : b3;
assign c1 = (fsm_status == 0) ? initial_state[ 95: 64] : c3;
assign d1 = (fsm_status == 0) ? initial_state[ 63: 32] : d3;
assign e1 = (fsm_status == 0) ? initial_state[ 31:  0] : e3;

// Calculate k_i
wire [31:0] k_i;
assign k_i = (fsm_status < 20) ? 32'h5A827999 :
             (fsm_status < 40) ? 32'h6ED9EBA1 :
             (fsm_status < 60) ? 32'h8F1BBCDC :
                                 32'hCA62C1D6 ;


// Calculate w[i]
wire [31:0] w_i_calc_1;
wire [31:0] w_i_calc_2;
assign w_i_calc_1 = internal_message[31+32* 0:32* 0] ^
                    internal_message[31+32* 2:32* 2] ^
                    internal_message[31+32* 8:32* 8] ^
                    internal_message[31+32*13:32*13];
assign w_i_calc_2 = { w_i_calc_1[30:0], w_i_calc_1[31] };

// Select w[i] or w[0] for window shift stage
wire [31:0] w_i;
assign w_i = internal_message[31:0];

// Add 3 terms up
wire [31:0] p_i;
assign p_i = w_i + k_i + e1;  // This is w[i] + k + e (a and f remaining!)

// Stage 1 to Stage 2
wire [31:0] a2 = a1;
wire [31:0] b2 = b1;
wire [31:0] c2 = c1;
wire [31:0] d2 = d1;
wire [31:0] e2 = p_i;

// Stage 2

// Calculate f_i
wire [31:0] f_i;
assign f_i = (fsm_status < 20) ? (b2 & c2) | ((~b2) & d2)          :
             (fsm_status < 40) ?  b2 ^ c2 ^ d2                     :
             (fsm_status < 60) ? (b2 & c2) | (b2 & d2) | (c2 & d2) :
                                  b2 ^ c2 ^ d2                     ;


// Rotate A before adding it
wire [31:0] a_rot;
assign a_rot = {a2[26:0], a2[31:27]};

// Actual calculation
wire [31:0] a_next;
assign a_next = f_i + a_rot + e2;

// B gets rotated into C
wire [31:0] c_next;
assign c_next = { b2[1:0], b2[31:2] };

// Stage 2 end
reg [31:0] a3, b3, c3, d3, e3;
always @(posedge clk) begin
	if (busy) begin
		a3 <= a_next;
		b3 <= a2;
		c3 <= c_next;
		d3 <= c2;
		e3 <= d2;
	end
end

endmodule

