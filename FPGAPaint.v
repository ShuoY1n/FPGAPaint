module FPGAPaint (
	input [9:0] SW,
	input [3:0] KEY,
	input CLOCK_50,

	inout PS2_CLK,
	inout PS2_DAT,
	
	output [7:0] VGA_R,
	output [7:0] VGA_G,
	output [7:0] VGA_B,
	output VGA_HS,
	output VGA_VS,
	output VGA_BLANK_N,
	output VGA_SYNC_N,
	output VGA_CLK
);

// Screen dimensions
parameter SCREEN_WIDTH = 320;
parameter SCREEN_HEIGHT = 240;

// Color definitions
parameter COLOR_BACKGROUND = 9'b111_111_111;
parameter COLOR_DRAW = 9'b000_000_000;
parameter COLOR_ERASE = 9'b111_111_111;

// Reset signal from KEY[0]
wire reset;
assign reset = ~KEY[0];

// PS2 controller signals
wire [7:0] ps2_received_data;
wire ps2_received_data_en;

// Mouse button signals
wire mouse_left_button;
wire mouse_right_button;
wire mouse_middle_button;
wire [8:0] mouse_delta_x;
wire [8:0] mouse_delta_y;
wire mouse_data_valid;

// Current mouse position on screen
reg [8:0] mouse_x_pos;
reg [7:0] mouse_y_pos;

// Drawing enable controlled by SW[0]
wire drawing_enabled;
assign drawing_enabled = SW[0];

// VGA signals
reg [8:0] vga_color;
reg [8:0] vga_x;
reg [7:0] vga_y;
reg vga_write;

// Size of the drawing cursor
reg [4:0] SQUARE_SIZE;

// Mouse movement correction values
reg [7:0] corrected_delta_x;
reg [7:0] corrected_delta_y;

// Pen color from switches SW[9:7]
wire [8:0] pen_colors;
assign pen_colors = {SW[9], SW[9], SW[9], SW[8], SW[8], SW[8], SW[7], SW[7], SW[7]};

// PS2 controller for mouse
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

// Mouse parser to decode PS2 data
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

// Mouse position tracking
always @(posedge CLOCK_50) begin
	if (reset) begin
		mouse_x_pos <= SCREEN_WIDTH / 2;
		mouse_y_pos <= SCREEN_HEIGHT / 2;
	end
	else begin
		if (mouse_data_valid) begin
			if (mouse_delta_x[7:0] >= 128)
				corrected_delta_x = 8'd256 - mouse_delta_x[7:0];
			else
				corrected_delta_x = mouse_delta_x[7:0];
				
			if (mouse_delta_y[7:0] >= 128)
				corrected_delta_y = 8'd256 - mouse_delta_y[7:0];
			else
				corrected_delta_y = mouse_delta_y[7:0];
			
			if (corrected_delta_x != 0) begin
				if (mouse_delta_x[7:0] < 128) begin
					if (mouse_x_pos + corrected_delta_x < SCREEN_WIDTH)
						mouse_x_pos <= mouse_x_pos + corrected_delta_x;
					else
						mouse_x_pos <= 9'd319;
				end
				else begin
					if (mouse_x_pos >= corrected_delta_x)
						mouse_x_pos <= mouse_x_pos - corrected_delta_x;
					else
						mouse_x_pos <= 9'd0;
				end
			end
			
			if (corrected_delta_y != 0) begin
				if (mouse_delta_y[7:0] > 128) begin
					if (mouse_y_pos + corrected_delta_y < SCREEN_HEIGHT)
						mouse_y_pos <= mouse_y_pos + corrected_delta_y;
					else
						mouse_y_pos <= 8'd239;
				end
				else begin
					if (mouse_y_pos >= corrected_delta_y)
						mouse_y_pos <= mouse_y_pos - corrected_delta_y;
					else
						mouse_y_pos <= 8'd0;
				end
			end
		end
	end
end

// VGA adapter for display
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

// Square drawing state machine
reg [1:0] draw_state;
reg [4:0] x_offset;
reg [4:0] y_offset;

parameter DRAW_IDLE = 2'b00;
parameter DRAW_LOOP = 2'b01;
parameter DRAW_FINISH = 2'b10;

reg [4:0] center_offset;

wire [9:0] px;
wire [8:0] py;

// Calculate pixel position centered on cursor
assign px = mouse_x_pos + x_offset - center_offset;
assign py = mouse_y_pos + y_offset - center_offset;

// Main drawing control logic
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
		
		// Priority 1: Screen reset
		if (reset_state == RESET_CLEAR) begin
			vga_x <= reset_x;
			vga_y <= reset_y;
			vga_color <= COLOR_BACKGROUND;
			vga_write <= 1'b1;
		end
		// Priority 2: Rectangle drawing
		else if (rect_state == RECT_DRAW_TOP || 
		         rect_state == RECT_DRAW_RIGHT ||
		         rect_state == RECT_DRAW_BOTTOM ||
		         rect_state == RECT_DRAW_LEFT) begin
			vga_x <= rect_x;
			vga_y <= rect_y;
			vga_color <= pen_colors;
			vga_write <= 1'b1;
		end
		// Priority 3: Normal square drawing
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
					vga_write <= 1'b1;
					vga_x <= px[8:0];
					vga_y <= py[7:0];
					
					if (mouse_left_button) begin
						vga_color <= pen_colors;
					end
					else if (mouse_right_button) begin
						vga_color <= COLOR_ERASE;
					end
					
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

// Cursor size control state machine
parameter SIZE1 = 5'd1, WAIT1 = 5'd2, SIZE2 = 5'd3, WAIT2 = 5'd4, SIZE3 = 5'd5, WAIT3 = 5'd6, SIZE4 = 5'd7, WAIT4 = 5'd8;
reg [4:0] Cusor_Size_State;

always @(posedge CLOCK_50) begin
	if (reset) begin
		Cusor_Size_State <= SIZE1;
		SQUARE_SIZE <= 5'd1;
		center_offset <= 5'd0;
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
				SQUARE_SIZE <= SQUARE_SIZE;
				center_offset <= center_offset;
			end
		endcase
	end
end

// Rectangle drawing state machine
reg [3:0] rect_state;
parameter RECT_IDLE = 4'd0;
parameter RECT_WAIT_SECOND = 4'd1;
parameter RECT_DRAW_TOP = 4'd2;
parameter RECT_DRAW_RIGHT = 4'd3;
parameter RECT_DRAW_BOTTOM = 4'd4;
parameter RECT_DRAW_LEFT = 4'd5;
parameter RECT_DONE = 4'd6;

// Rectangle corner coordinates
reg [8:0] rect_x0, rect_x1;
reg [7:0] rect_y0, rect_y1;

// Normalized min/max coordinates
reg [8:0] rect_x_min, rect_x_max;
reg [7:0] rect_y_min, rect_y_max;

// Current drawing position
reg [8:0] rect_x;
reg [7:0] rect_y;

// Middle mouse button edge detection
reg prev_mouse_middle;
wire mouse_middle_clicked;
assign mouse_middle_clicked = mouse_middle_button && !prev_mouse_middle;

// Screen reset state machine
reg [2:0] reset_state;
parameter RESET_IDLE = 3'd0;
parameter RESET_CLEAR = 3'd1;
parameter RESET_DONE = 3'd2;

// Screen reset position trackers
reg [8:0] reset_x;
reg [7:0] reset_y;
reg reset_triggered;
reg prev_reset_key;

// Edge detection for middle mouse button
always @(posedge CLOCK_50) begin
	if (reset) begin
		prev_mouse_middle <= 1'b0;
	end
	else begin
		prev_mouse_middle <= mouse_middle_button;
	end
end

// Rectangle drawing logic
always @(posedge CLOCK_50) begin
	if (reset) begin
		rect_state <= RECT_IDLE;
		rect_x0 <= 9'd0;
		rect_y0 <= 8'd0;
		rect_x1 <= 9'd0;
		rect_y1 <= 8'd0;
		rect_x_min <= 9'd0;
		rect_x_max <= 9'd0;
		rect_y_min <= 8'd0;
		rect_y_max <= 8'd0;
		rect_x <= 9'd0;
		rect_y <= 8'd0;
	end
	else begin
		case (rect_state)
			RECT_IDLE: begin
				// Wait for first corner click
				if (mouse_middle_clicked && drawing_enabled) begin
					rect_x0 <= mouse_x_pos;
					rect_y0 <= mouse_y_pos;
					rect_state <= RECT_WAIT_SECOND;
				end
			end
			
			RECT_WAIT_SECOND: begin
				// Wait for second corner click and calculate bounds
				if (mouse_middle_clicked) begin
					rect_x1 <= mouse_x_pos;
					rect_y1 <= mouse_y_pos;
					
					if (mouse_x_pos < rect_x0) begin
						rect_x_min <= mouse_x_pos;
						rect_x_max <= rect_x0;
					end
					else begin
						rect_x_min <= rect_x0;
						rect_x_max <= mouse_x_pos;
					end
					
					if (mouse_y_pos < rect_y0) begin
						rect_y_min <= mouse_y_pos;
						rect_y_max <= rect_y0;
					end
					else begin
						rect_y_min <= rect_y0;
						rect_y_max <= mouse_y_pos;
					end
					
					rect_x <= (mouse_x_pos < rect_x0) ? mouse_x_pos : rect_x0;
					rect_y <= (mouse_y_pos < rect_y0) ? mouse_y_pos : rect_y0;
					rect_state <= RECT_DRAW_TOP;
				end
			end
			
			RECT_DRAW_TOP: begin
				// Draw top edge
				if (rect_x < rect_x_max) begin
					rect_x <= rect_x + 1'b1;
				end
				else begin
					rect_x <= rect_x_max;
					rect_y <= rect_y_min;
					rect_state <= RECT_DRAW_RIGHT;
				end
			end
			
			RECT_DRAW_RIGHT: begin
				// Draw right edge
				if (rect_y < rect_y_max) begin
					rect_y <= rect_y + 1'b1;
				end
				else begin
					rect_x <= rect_x_max;
					rect_y <= rect_y_max;
					rect_state <= RECT_DRAW_BOTTOM;
				end
			end
			
			RECT_DRAW_BOTTOM: begin
				// Draw bottom edge
				if (rect_x > rect_x_min) begin
					rect_x <= rect_x - 1'b1;
				end
				else begin
					rect_x <= rect_x_min;
					rect_y <= rect_y_max;
					rect_state <= RECT_DRAW_LEFT;
				end
			end
			
			RECT_DRAW_LEFT: begin
				// Draw left edge
				if (rect_y > rect_y_min) begin
					rect_y <= rect_y - 1'b1;
				end
				else begin
					rect_state <= RECT_DONE;
				end
			end
			
			RECT_DONE: begin
				rect_state <= RECT_IDLE;
			end
		endcase
	end
end

// Edge detection for reset button KEY[3]
always @(posedge CLOCK_50) begin
	if (reset) begin
		prev_reset_key <= 1'b1;
		reset_triggered <= 1'b0;
	end
	else begin
		prev_reset_key <= KEY[3];
		if (!KEY[3] && prev_reset_key) begin
			reset_triggered <= 1'b1;
		end
		else if (reset_state == RESET_DONE) begin
			reset_triggered <= 1'b0;
		end
	end
end

// Screen reset control
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
