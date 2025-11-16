module FPGAPaint (
	input [9:0] SW,
	input [3:0] KEY,
	input CLOCK_50,

	inout PS2_CLK,
	inout PS2_DAT,
	
	// VGA outputs
	output [7:0] VGA_R,
	output [7:0] VGA_G,
	output [7:0] VGA_B,
	output VGA_HS,
	output VGA_VS,
	output VGA_BLANK_N,
	output VGA_SYNC_N,
	output VGA_CLK
);

parameter SCREEN_WIDTH = 320;
parameter SCREEN_HEIGHT = 240;

// Color definitions (9-bit: 3 bits R, 3 bits G, 3 bits B)
parameter COLOR_BACKGROUND = 9'b111_111_111; // White background
parameter COLOR_DRAW = 9'b000_000_000;       // Black drawing color (pen color)
parameter COLOR_ERASE = 9'b111_111_111;      // White (for erasing, same as background)

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

reg [8:0] mouse_x_pos;  // 9 bits for X (0-319)
reg [7:0] mouse_y_pos;  // 8 bits for Y (0-239)

wire drawing_enabled;
assign drawing_enabled = SW[0];

// VGA drawing signals
reg [8:0] vga_color;
reg [8:0] vga_x;  // 9 bits for X (0-319)
reg [7:0] vga_y;  // 8 bits for Y (0-239)
reg vga_write;

// Square drawing - cursor size (variable, controlled by FSM)
reg [4:0] SQUARE_SIZE;  // Can be 1, 5, 10, or 30

reg [7:0] corrected_delta_x;
reg [7:0] corrected_delta_y;

wire [8:0] pen_colors;
assign pen_colors = {SW[9], SW[9], SW[9], SW[8], SW[8], SW[8], SW[7], SW[7], SW[7]};  // Pen color controlled by switches SW[9:7]

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
	else begin
		// Update mouse position
		if (mouse_data_valid) begin
			// Calculate corrected deltas: if >= 128, it's encoded as 256 - actual_delta
			if (mouse_delta_x[7:0] >= 128) // negative movement (encoded)
				corrected_delta_x = 8'd256 - mouse_delta_x[7:0];
			else
				corrected_delta_x = mouse_delta_x[7:0];
				
			if (mouse_delta_y[7:0] >= 128) // negative movement (encoded)
				corrected_delta_y = 8'd256 - mouse_delta_y[7:0];
			else
				corrected_delta_y = mouse_delta_y[7:0];
			
			// Update X position only when we have valid movement data
			if (corrected_delta_x != 0) begin
				if (mouse_delta_x[7:0] < 128) begin // positive movement (right)
					// Use wider addition to prevent overflow issues
					if (mouse_x_pos + corrected_delta_x < SCREEN_WIDTH)
						mouse_x_pos <= mouse_x_pos + corrected_delta_x;
					else
						mouse_x_pos <= 9'd319; // SCREEN_WIDTH - 1
				end
				else begin // negative movement (left)
					if (mouse_x_pos >= corrected_delta_x)
						mouse_x_pos <= mouse_x_pos - corrected_delta_x;
					else
						mouse_x_pos <= 9'd0;
				end
			end
			
			// Update Y position only when we have valid movement data
			// Y=0 is at top, Y increases downward
			if (corrected_delta_y != 0) begin
				if (mouse_delta_y[7:0] > 128) begin // positive movement (down)
					if (mouse_y_pos + corrected_delta_y < SCREEN_HEIGHT)
						mouse_y_pos <= mouse_y_pos + corrected_delta_y;
					else
						mouse_y_pos <= 8'd239; // SCREEN_HEIGHT - 1
				end
				else begin // negative movement (up)
					if (mouse_y_pos >= corrected_delta_y)
						mouse_y_pos <= mouse_y_pos - corrected_delta_y;
					else
						mouse_y_pos <= 8'd0;
				end
			end
		end
	end
end

// VGA Adapter instance
vga_adapter #(
	.RESOLUTION("320x240"),
	.COLOR_DEPTH(9),
	.BACKGROUND_IMAGE("./white_320_240_9.mif")
) vga_adapter_inst (
	.resetn(~reset),
	.clock(CLOCK_50),
	.color(vga_color),
	.x(vga_x),
	.y(vga_y),
	.write(vga_write),
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_HS(VGA_HS),
	.VGA_VS(VGA_VS),
	.VGA_BLANK_N(VGA_BLANK_N),
	.VGA_SYNC_N(VGA_SYNC_N),
	.VGA_CLK(VGA_CLK)
);

// Square drawing - simple state machine
reg [1:0] draw_state;
reg [4:0] x_offset;  // 0 to SQUARE_SIZE-1 (supports up to size 20)
reg [4:0] y_offset;  // 0 to SQUARE_SIZE-1 (supports up to size 20)

parameter DRAW_IDLE = 2'b00;
parameter DRAW_LOOP = 2'b01;
parameter DRAW_FINISH = 2'b10;

// Calculate pixel position (centered on cursor)
// Center offset assigned in FSM always block
reg [4:0] center_offset;

wire [9:0] px;
wire [8:0] py;

// Pixel X: mouse_x_pos + x_offset - center_offset (centered)
assign px = mouse_x_pos + x_offset - center_offset;

// Pixel Y: mouse_y_pos + y_offset - center_offset (centered)
assign py = mouse_y_pos + y_offset - center_offset;

always @(posedge CLOCK_50) begin
	if (reset) begin
		draw_state <= DRAW_IDLE;
		x_offset <= 5'd0;
		y_offset <= 5'd0;
		vga_write <= 1'b0;
		vga_x <= 9'd0;
		vga_y <= 8'd0;
		vga_color <= COLOR_BACKGROUND;
	end
	else begin
		vga_write <= 1'b0;
		
		// Priority 1: Screen reset (highest priority)
		if (reset_state == RESET_CLEAR) begin
			vga_x <= reset_x;
			vga_y <= reset_y;
			vga_color <= COLOR_BACKGROUND;  // Clear to background color
			vga_write <= 1'b1;
		end
		// Priority 2: Normal drawing
		else begin
			case (draw_state)
				DRAW_IDLE: begin
					if (drawing_enabled && (mouse_left_button || mouse_right_button)) begin
						draw_state <= DRAW_LOOP;
						x_offset <= 5'd0;
						y_offset <= 5'd0;
					end
				end
				
				DRAW_LOOP: begin
					// Normal drawing mode
					vga_write <= 1'b1;
					vga_x <= px[8:0];
					vga_y <= py[7:0];
					
					if (mouse_left_button) begin
						vga_color <= pen_colors;  // Left click: pen color (from switches)
					end
					else if (mouse_right_button) begin
						vga_color <= COLOR_ERASE;  // Right click: background color (white)
					end
					
					// Advance to next pixel in square grid
					if (x_offset >= (SQUARE_SIZE - 1)) begin
						x_offset <= 5'd0;
						if (y_offset >= (SQUARE_SIZE - 1)) begin
							draw_state <= DRAW_FINISH;
						end
						else begin
							y_offset <= y_offset + 1;
							draw_state <= DRAW_LOOP;
						end
					end
					else begin
						x_offset <= x_offset + 1;
						draw_state <= DRAW_LOOP;
					end
				end
				
				DRAW_FINISH: begin
					if (drawing_enabled && (mouse_left_button || mouse_right_button)) begin
						draw_state <= DRAW_LOOP;
						x_offset <= 5'd0;
						y_offset <= 5'd0;
					end
					else begin
						draw_state <= DRAW_IDLE;
					end
				end
			endcase
		end
	end
end

parameter SIZE1 = 5'd1, WAIT1 = 5'd2, SIZE2 = 5'd3, WAIT2 = 5'd4, SIZE3 = 5'd5, WAIT3 = 5'd6, SIZE4 = 5'd7, WAIT4 = 5'd8;
reg [4:0] Cusor_Size_State;

always @(posedge CLOCK_50) begin
	if (reset) begin
		Cusor_Size_State <= SIZE1;
		SQUARE_SIZE <= 5'd1;  // Initialize to size 1
		center_offset <= 5'd0;  // Initialize offset for size 1
	end
	else begin
		case (Cusor_Size_State)
			SIZE1: begin
				if (KEY[1] == 1'b0) begin
					Cusor_Size_State <= WAIT1;
				end
				else begin
					Cusor_Size_State <= SIZE1;
				end
			end
			WAIT1: begin
				if (KEY[1] == 1'b1) begin
					Cusor_Size_State <= SIZE2;
				end
				else begin
					Cusor_Size_State <= WAIT1;
				end
			end
			SIZE2: begin
				if (KEY[1] == 1'b0) begin
					Cusor_Size_State <= WAIT2;
				end
				else begin
					Cusor_Size_State <= SIZE2;
				end
			end
			WAIT2: begin
				if (KEY[1] == 1'b1) begin
					Cusor_Size_State <= SIZE3;
				end
				else begin
					Cusor_Size_State <= WAIT2;
				end
			end
			SIZE3: begin
				if (KEY[1] == 1'b0) begin
					Cusor_Size_State <= WAIT3;
				end
				else begin
					Cusor_Size_State <= SIZE3;
				end
			end
			WAIT3: begin
				if (KEY[1] == 1'b1) begin
					Cusor_Size_State <= SIZE4;
				end
				else begin
					Cusor_Size_State <= WAIT3;
				end
			end
			SIZE4: begin
				if (KEY[1] == 1'b0) begin
					Cusor_Size_State <= WAIT4;
				end
				else begin
					Cusor_Size_State <= SIZE4;
				end
			end
			WAIT4: begin
				if (KEY[1] == 1'b1) begin
					Cusor_Size_State <= SIZE1;
				end
				else begin
					Cusor_Size_State <= WAIT4;
				end
			end
		endcase

		// Update SQUARE_SIZE and center_offset based on current state
		case (Cusor_Size_State)
			SIZE1: begin
				SQUARE_SIZE <= 5'd1;
				center_offset <= 5'd0;
			end
			SIZE2: begin
				SQUARE_SIZE <= 5'd3;
				center_offset <= 5'd2;
			end
			SIZE3: begin
				SQUARE_SIZE <= 5'd7;
				center_offset <= 5'd4;
			end
			SIZE4: begin
				SQUARE_SIZE <= 5'd20;
				center_offset <= 5'd9;
			end
			default: begin
				SQUARE_SIZE <= SQUARE_SIZE;  // Hold current value
				center_offset <= center_offset;  // Hold current value
			end
		endcase
	end
end

// Screen reset state machine
reg [2:0] reset_state;
parameter RESET_IDLE = 3'd0;
parameter RESET_CLEAR = 3'd1;
parameter RESET_DONE = 3'd2;

reg [8:0] reset_x;      // Current X position during reset
reg [7:0] reset_y;      // Current Y position during reset
reg reset_triggered;    // Edge detection flag
reg prev_reset_key;     // Previous reset key state for edge detection

// Detect reset button press (edge detection on KEY[3])
always @(posedge CLOCK_50) begin
	if (reset) begin
		prev_reset_key <= 1'b1;
		reset_triggered <= 1'b0;
	end
	else begin
		prev_reset_key <= KEY[3];
		// Trigger on falling edge of KEY[3] (button pressed)
		if (!KEY[3] && prev_reset_key) begin
			reset_triggered <= 1'b1;
		end
		else if (reset_state == RESET_DONE) begin
			reset_triggered <= 1'b0;
		end
	end
end

// Screen reset state machine
always @(posedge CLOCK_50) begin
	if (reset) begin
		reset_state <= RESET_IDLE;
		reset_x <= 9'd0;
		reset_y <= 8'd0;
	end
	else begin
		case (reset_state)
			RESET_IDLE: begin
				if (reset_triggered) begin
					reset_state <= RESET_CLEAR;
					reset_x <= 9'd0;
					reset_y <= 8'd0;
				end
			end
			
			RESET_CLEAR: begin
				// Increment through all pixels
				if (reset_x < (SCREEN_WIDTH - 1)) begin
					reset_x <= reset_x + 1'b1;
				end
				else begin
					reset_x <= 9'd0;
					if (reset_y < (SCREEN_HEIGHT - 1)) begin
						reset_y <= reset_y + 1'b1;
					end
					else begin
						reset_state <= RESET_DONE;
					end
				end
			end
			
			RESET_DONE: begin
				reset_state <= RESET_IDLE;
			end
		endcase
	end
end

endmodule