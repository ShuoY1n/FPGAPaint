module FPGAPaint (
	input [9:0] SW,
	input [3:0] KEY,
	input CLOCK_50,
	
	output [9:0] LEDR,

	inout PS2_CLK,
	inout PS2_DAT
);

parameter SCREEN_WIDTH = 320;
parameter SCREEN_HEIGHT = 480;

wire reset;
assign reset = ~KEY[0];

wire [7:0] ps2_received_data;
wire ps2_received_data_en;

wire mouse_left_button;
wire mouse_right_button;
wire mouse_middle_button;
wire [8:0] mouse_delta_x; // First bit is the direction of movement
wire [8:0] mouse_delta_y;
wire mouse_data_valid;

reg [9:0] mouse_x_pos;
reg [9:0] mouse_y_pos;

wire drawing_enabled;
assign drawing_enabled = SW[0];

// Direction indicators - latched so they stay on once detected
reg move_left_latched;
reg move_right_latched;
reg move_up_latched;
reg move_down_latched;

// Detect movement in each direction
wire move_left_detect;
wire move_right_detect;
wire move_up_detect;
wire move_down_detect;

// Assigns for testing (removed mouse_data_valid check for immediate updates)
assign move_left_detect = mouse_data_valid && (mouse_delta_x[8] == 1) && (mouse_delta_x[7:0] != 0);
assign move_right_detect = mouse_data_valid && (mouse_delta_x[8] == 0) && (mouse_delta_x[7:0] != 0);
assign move_up_detect = mouse_data_valid && (mouse_delta_y[8] == 1) && (mouse_delta_y[7:0] != 0);
assign move_down_detect = mouse_data_valid && (mouse_delta_y[8] == 0) && (mouse_delta_y[7:0] != 0);

// Latch movement indicators - once set, stay on until reset
always @(posedge CLOCK_50) begin
	if (reset) begin
		move_left_latched <= 1'b0;
		move_right_latched <= 1'b0;
		move_up_latched <= 1'b0;
		move_down_latched <= 1'b0;
	end
	else begin
		// Set latches when movement detected, but don't clear them
		if (move_left_detect)
			move_left_latched <= 1'b1;
		if (move_right_detect)
			move_right_latched <= 1'b1;
		if (move_up_detect)
			move_up_latched <= 1'b1;
		if (move_down_detect)
			move_down_latched <= 1'b1;
	end
end


// PS2 Controller with mouse initialization enabled
// Module was provided to us
PS2_Controller #(.INITIALIZE_MOUSE(1)) ps2_controller_inst (
	.CLOCK_50(CLOCK_50),
	.reset(reset),
	.the_command(8'h00),
	.send_command(1'b0),
	
	.PS2_CLK(PS2_CLK),
	.PS2_DAT(PS2_DAT),
	
	.command_was_sent(),
	.error_communication_timed_out(),
	.received_data(ps2_received_data),
	.received_data_en(ps2_received_data_en)
);

// Parses the PS2 outputs into named channels for better processing
PS2_Mouse_Parser mouse_parser_inst (
	.CLOCK_50(CLOCK_50),
	.reset(reset),
	.ps2_received_data(ps2_received_data),
	.ps2_received_data_en(ps2_received_data_en),
	
	.left_button(mouse_left_button),
	.right_button(mouse_right_button),
	.middle_button(mouse_middle_button),
	.mouse_delta_x(mouse_delta_x),
	.mouse_delta_y(mouse_delta_y),
	.mouse_data_valid(mouse_data_valid)
);

always @(posedge CLOCK_50) begin
	if (reset) begin
		mouse_x_pos <= SCREEN_WIDTH / 2; // Start at center of screen
		mouse_y_pos <= SCREEN_HEIGHT / 2;
	end
	else if (mouse_data_valid) begin
		// Update X position only when we have valid movement data
		if (mouse_delta_x[7:0] != 0) begin
			if (mouse_delta_x[8] == 0) begin // positive movement (right)
				if (mouse_x_pos + mouse_delta_x[7:0] < SCREEN_WIDTH)
					mouse_x_pos <= mouse_x_pos + mouse_delta_x[7:0];
				else
					mouse_x_pos <= SCREEN_WIDTH - 1;
			end
			else begin // negative movement (left)
				if (mouse_x_pos >= mouse_delta_x[7:0])
					mouse_x_pos <= mouse_x_pos - mouse_delta_x[7:0];
				else
					mouse_x_pos <= 10'd0;
			end
		end
		
		// Update Y position only when we have valid movement data
		// Y=0 is at top, Y increases downward
		if (mouse_delta_y[7:0] != 0) begin
			if (mouse_delta_y[8] == 0) begin // positive movement (down)
				if (mouse_y_pos + mouse_delta_y[7:0] < SCREEN_HEIGHT)
					mouse_y_pos <= mouse_y_pos + mouse_delta_y[7:0];
				else
					mouse_y_pos <= SCREEN_HEIGHT - 1;
			end
			else begin // negative movement (up)
				if (mouse_y_pos >= mouse_delta_y[7:0])
					mouse_y_pos <= mouse_y_pos - mouse_delta_y[7:0];
				else
					mouse_y_pos <= 10'd0;
			end
		end
	end
end





// Display status on LEDs
assign LEDR[0] = drawing_enabled; // LED[0] = drawing mode enabled
assign LEDR[1] = mouse_right_button; // LED[2] = right mouse button
assign LEDR[2] = mouse_left_button; // LED[1] = left mouse button
assign LEDR[3] = move_right_latched;
assign LEDR[4] = move_left_latched; // LED[4] = mouse moving left (latched)
assign LEDR[5] = move_up_latched; // LED[5] = mouse moving up (latched)
assign LEDR[6] = move_down_latched; // LED[6] = mouse moving down (latched)
assign LEDR[7] = 1'b0; // LED[7] = unused
assign LEDR[8] = 1'b0; // LED[8] = unused
assign LEDR[9] = 1'b0; // LED[9] = unused

endmodule