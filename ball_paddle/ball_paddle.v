`default_nettype none // disable implicit definitions by Verilog
//-----------------------------------------------------------------
//
// Author: Mike Field <hamster@snap.net.nz>
//
// DVI-D uses TMDS as the 'on the wire' protocol, where each 8-bit
// value is mapped to one or two 10-bit symbols, depending on how
// many 1s or 0s have been sent. This makes it a DC balanced protocol,
// as a correctly implemented stream will have (almost) an equal
// number of 1s and 0s.
//
// Because of this implementation quite complex. By restricting the
// symbols to a subset of eight symbols, all of which having have
// five ones (and therefore five zeros) this complexity drops away
// leaving a simple implementation. Combined with a DDR register to
// send the symbols the complexity is kept very low.
//-----------------------------------------------------------------
`include "digits10.v"
`include "scoreboard.v"

module top(
    input clk100, 
    input quadA,
    input quadB,
    output [3:0] hdmi_p
);

// For holding the outward bound TMDS symbols in the slow and fast domain
reg [9:0] c0_symbol; reg [9:0] c0_high_speed;
reg [9:0] c1_symbol; reg [9:0] c1_high_speed;
reg [9:0] c2_symbol; reg [9:0] c2_high_speed;
reg [9:0] clk_high_speed;

reg [1:0] c2_output_bits;
reg [1:0] c1_output_bits;
reg [1:0] c0_output_bits;
reg [1:0] clk_output_bits;

wire clk_x5;
reg [2:0] latch_high_speed = 3'b100; // Controlling the transfers into the high speed domain

// video structure constants
parameter hpixels = 800; // horizontal pixels per line
parameter vlines =  525; // vertical lines per frame
parameter hpulse =   96; // hsync pulse length
parameter vpulse =    2; // vsync pulse length
parameter hbp =     144; // end of horizontal back porch (96 + 48)
parameter hfp =     784; // beginning of horizontal front porch (800 - 16)
parameter vbp =      35; // end of vertical back porch (2 + 33)
parameter vfp =     515; // beginning of vertical front porch (525 - 10)

// registers for storing the horizontal & vertical counters
reg [9:0] vc;
reg [9:0] hc;

// HDMI output
always @(posedge clk_x5) begin
    //-------------------------------------------------------------
    // Now take the 10-bit words and take it into the high-speed
    // clock domain once every five cycles.
    //
    // Then send out two bits every clock cycle using DDR output
    // registers.
    //-------------------------------------------------------------
    c0_output_bits  <= c0_high_speed[1:0];
    c1_output_bits  <= c1_high_speed[1:0];
    c2_output_bits  <= c2_high_speed[1:0];
    clk_output_bits <= clk_high_speed[1:0];
    if (latch_high_speed[2]) begin // pixel clock 25MHz
        c0_high_speed  <= c0_symbol;
        c1_high_speed  <= c1_symbol;
        c2_high_speed  <= c2_symbol;
        clk_high_speed <= 10'b0000011111;
        latch_high_speed <= 0;
        if (hc < hpixels) hc <= hc + 1;
        else begin
            hc <= 0;
            if (vc < vlines) vc <= vc + 1;
            else vc <= 0;
        end
    end else begin
        c0_high_speed  <= {2'b00, c0_high_speed[9:2]};
        c1_high_speed  <= {2'b00, c1_high_speed[9:2]};
        c2_high_speed  <= {2'b00, c2_high_speed[9:2]};
        clk_high_speed <= {2'b00, clk_high_speed[9:2]};
        latch_high_speed <= latch_high_speed + 1;
    end
end 

// Quadrature code based on fpga4fun.com Pong game
reg [2:0] quadAr, quadBr;
reg [9:0] paddle_pos = 316; // paddle X position

always @(posedge clk_x5) begin
    quadAr <= {quadAr[1:0], quadA};
    quadBr <= {quadBr[1:0], quadB};

    if(quadAr[2] ^ quadAr[1] ^ quadBr[2] ^ quadBr[1]) begin
        if (quadAr[2] ^ quadBr[1]) begin
            if (paddle_pos < 602) paddle_pos <= paddle_pos + 2;
        end else begin
            if (paddle_pos > 8) paddle_pos <= paddle_pos - 2;
        end
    end
end

// Game data
reg [9:0] ball_x = 320; // ball X position
reg [9:0] ball_y = 160; // ball Y position
reg ball_dir_x = 1;     // ball X direction (0=left, 1=right)
reg ball_speed_x = 0;   // ball speed (0=1 pixel/frame, 1=2 pixels/frame)
reg ball_dir_y = 1;     // ball Y direction (0=up, 1=down)

reg brick_array [0:BRICKS_H*BRICKS_V-1]; // 64*8 = 512 bits

wire [3:0] score0;    // score right digit
wire [3:0] score1;    // score left digit
wire [3:0] lives;     // # lives remaining
reg incscore;         // incscore signal
reg declives = 0;     // TODO

localparam BRICKS_H = 64; // # of bricks across
localparam BRICKS_V = 8;  // # of bricks down

localparam BALL_DIR_LEFT = 0;
localparam BALL_DIR_RIGHT = 1;
localparam BALL_DIR_DOWN = 1;
localparam BALL_DIR_UP = 0;

localparam PADDLE_WIDTH = 31; // horizontal paddle size
localparam BALL_SIZE = 6; // square ball size

reg r, g, b;
wire [9:0] hpos = hc - hbp; // Horizontal active area counter
wire [9:0] vpos = vc -vbp;  // Vertical active area counter

wire grid_gfx = (((hpos & 7) == 0) || ((vpos & 7) == 0));

wire [6:0] hcell = hpos[9:3];     // horizontal brick index
wire [6:0] vcell = vpos[9:3];     // vertical brick index
wire lr_border = hcell == 0 || hcell == 79; // along horizontal border?

reg brick_present;
reg [8:0] brick_index;// index into array of current brick
reg main_gfx;

// ball graphics signal
wire ball_gfx = ball_rel_x < BALL_SIZE && ball_rel_y < BALL_SIZE;

wire reset = 0;

wire [9:0] paddle_rel_x = hpos - paddle_pos;

// player paddle graphics signal
wire paddle_gfx = (vcell == 58) && (paddle_rel_x < PADDLE_WIDTH);

// scoreboard
wire score_gfx; // output from score generator
player_stats stats(
    .reset(reset),
    .score0(score0),
    .score1(score1),
    .incscore(incscore),
    .lives(lives),
    .declives(declives)
);

scoreboard_generator score_gen(
    .score0(score0),
    .score1(score1),
    .lives(lives),
    .vpos(vpos),
    .hpos(hpos),
    .board_gfx(score_gfx)
);

wire brick_gfx = lr_border || (brick_present && vpos[2:0] != 0 && hpos[3:1] != 4);

// scan bricks: compute brick_index and brick_present flag
always @(posedge clk_x5) begin
    // see if we are scanning brick area
    if (vpos[9:6] == 1 && !lr_border) begin
      // every 16th pixel, starting at 8
      if (hpos[3:0] == 8) begin
        // compute brick index
        brick_index <= {vpos[5:3], hpos[9:4]};
      end  else if (hpos[3:0] == 9) begin
        // load brick bit from array
        brick_present <= !brick_array[brick_index];
      end
    end else begin
      brick_present <= 0;
    end
end

// 1 when ball signal intersects main (brick + border) signal
wire ball_pixel_collide = main_gfx & ball_gfx;

reg ball_collide_paddle = 0;
reg [3:0] ball_collide_bits = 0;

// difference between ball position and video beam
wire [9:0] ball_rel_x = (hpos - ball_x);
wire [9:0] ball_rel_y = (vpos - ball_y);

// compute ball collisions with paddle and playfield
always @(posedge clk_x5) begin
    // clear all collide bits for frame
    if (vc == vfp && hc == 0) begin
        ball_collide_bits <= 0;
        ball_collide_paddle <= 0;
    end else begin
        if (ball_pixel_collide) begin
            // did we collide w/ paddle?
            if (paddle_gfx) begin
                ball_collide_paddle <= 1;
            end
            // ball has 4 collision quadrants
            if (!ball_rel_x[2] & !ball_rel_y[2]) ball_collide_bits[0] <= 1;
            if (ball_rel_x[2] & !ball_rel_y[2]) ball_collide_bits[1] <= 1;
            if (!ball_rel_x[2] & ball_rel_y[2]) ball_collide_bits[2] <= 1;
            if (ball_rel_x[2] & ball_rel_y[2]) ball_collide_bits[3] <= 1;
        end
    end
end

// compute ball collisions with brick and increment score
always @(posedge clk_x5) begin
    if (ball_pixel_collide && brick_present) begin
      brick_array[brick_index] <= 1;
      incscore <= 1; // increment score
    end else begin
      incscore <= 0; // reset incscore
    end
end

// computes position of ball in relation to center of paddle
wire signed [9:0] ball_paddle_dx = ball_x - paddle_pos + 8;

// ball bounce: determine new velocity/direction
always @(posedge clk_x5) begin
    if (vc == vfp && hc == 0) begin
      // ball collided with paddle?
      if (ball_collide_paddle) begin
        // bounces upward off of paddle
        ball_dir_y <= BALL_DIR_UP;
        // which side of paddle, left/right?
        ball_dir_x <= (ball_paddle_dx < 20) ? BALL_DIR_LEFT : BALL_DIR_RIGHT;
        // hitting with edge of paddle makes it fast
        ball_speed_x <= ball_collide_bits[3:0] != 4'b1100;
      end else begin
        // collided with playfield
        // TODO: can still slip through corners
        // compute left/right bounce
        casez (ball_collide_bits[3:0])
          4'b01?1: ball_dir_x <= BALL_DIR_RIGHT; // left edge/corner
          4'b1101: ball_dir_x <= BALL_DIR_RIGHT; // left corner
          4'b101?: ball_dir_x <= BALL_DIR_LEFT; // right edge/corner
          4'b1110: ball_dir_x <= BALL_DIR_LEFT; // right corner
          default: ;
        endcase
        // compute top/bottom bounce
        casez (ball_collide_bits[3:0])
          4'b1011: ball_dir_y <= BALL_DIR_DOWN;
          4'b0111: ball_dir_y <= BALL_DIR_DOWN;
          4'b001?: ball_dir_y <= BALL_DIR_DOWN;
          4'b0001: ball_dir_y <= BALL_DIR_DOWN;
          4'b0100: ball_dir_y <= BALL_DIR_UP;
          4'b1?00: ball_dir_y <= BALL_DIR_UP;
          4'b1101: ball_dir_y <= BALL_DIR_UP;
          4'b1110: ball_dir_y <= BALL_DIR_UP;
          default: ;
        endcase
      end
    end
end

reg [2:0] frame_counter;
// ball motion: update ball position
always @(posedge clk_x5) begin
    if (vc == vfp && hc == 0) begin
        if (&frame_counter) begin
            // move ball horizontal and vertical position
            if (ball_dir_x == BALL_DIR_RIGHT)
                ball_x <= ball_x + (ball_speed_x?1:0) + 1;
            else
                ball_x <= ball_x - (ball_speed_x?1:0) - 1;
            ball_y <= ball_y + (ball_dir_y==BALL_DIR_DOWN?1:-1);
        end
        frame_counter <= frame_counter + 1;
    end
end

// compute main_gfx
always @(*) begin
    case (vpos[9:3])
        0,1,2: main_gfx = score_gfx; // scoreboard
        3: main_gfx = 0;
        4: main_gfx = 1; // top border
        8,9,10,11,12,13,14,15: main_gfx = brick_gfx; // brick rows 1-8
        58: main_gfx = paddle_gfx | lr_border; // paddle
        59: main_gfx = hpos[0] ^ vpos[0]; // bottom border
        default: main_gfx = lr_border; // left/right borders
    endcase
end

// Set HDMI symbols
always @(*) begin 
    // First check if we're within active video range
    if (vc >= vbp && vc < vfp && hc >= hbp && hc < hfp) begin
        r = ball_gfx | paddle_gfx;
        g = main_gfx | ball_gfx;
        b = grid_gfx | ball_gfx | brick_present;
        c2_symbol = {r ? 2'b10 : 2'b01, 8'b11110000};
        c1_symbol = {g ? 2'b10 : 2'b01, 8'b11110000};
        c0_symbol = {b ? 2'b10 : 2'b01, 8'b11110000};
    end else begin // We're outside active horizontal or vertical range
        c2_symbol = 10'b1101010100; // red
        c1_symbol = 10'b1101010100; // green
        //---------------------------------------------
        // Channel 0 carries the blue pixels, and also
        // includes the HSYNC and VSYNCs during
        // the CTL (blanking) periods.
        //---------------------------------------------
        case ({vc < vpulse, hc < hpulse})
            2'b00   : c0_symbol = 10'b1101010100;
            2'b01   : c0_symbol = 10'b0010101011;
            2'b10   : c0_symbol = 10'b0101010100;
            default : c0_symbol = 10'b1010101011;
        endcase
    end
end

// red
defparam hdmip2.PIN_TYPE = 6'b010000;
defparam hdmip2.IO_STANDARD = "SB_LVCMOS";
SB_IO hdmip2 (
    .PACKAGE_PIN (hdmi_p[2]),
    .CLOCK_ENABLE (1'b1),
    .OUTPUT_CLK (clk_x5),
    .OUTPUT_ENABLE (1'b1),
    .D_OUT_0 (c2_output_bits[1]),
    .D_OUT_1 (c2_output_bits[0])
);

// green
defparam hdmip1.PIN_TYPE = 6'b010000;
defparam hdmip1.IO_STANDARD = "SB_LVCMOS";
SB_IO hdmip1 (
    .PACKAGE_PIN (hdmi_p[1]),
    .CLOCK_ENABLE (1'b1),
    .OUTPUT_CLK (clk_x5),
    .OUTPUT_ENABLE (1'b1),
    .D_OUT_0 (c1_output_bits[1]),
    .D_OUT_1 (c1_output_bits[0])
);

// blue
defparam hdmip0.PIN_TYPE = 6'b010000;
defparam hdmip0.IO_STANDARD = "SB_LVCMOS";
SB_IO hdmip0 (
    .PACKAGE_PIN (hdmi_p[0]),
    .CLOCK_ENABLE (1'b1),
    .OUTPUT_CLK (clk_x5),
    .OUTPUT_ENABLE (1'b1),
    .D_OUT_0 (c0_output_bits[1]),
    .D_OUT_1 (c0_output_bits[0])
);

// clock
defparam hdmip3.PIN_TYPE = 6'b010000;
defparam hdmip3.IO_STANDARD = "SB_LVCMOS";
SB_IO hdmip3 (
    .PACKAGE_PIN (hdmi_p[3]),
    .CLOCK_ENABLE (1'b1),
    .OUTPUT_CLK (clk_x5),
    .OUTPUT_ENABLE (1'b1),
    .D_OUT_0 (clk_output_bits[1]),
    .D_OUT_1 (clk_output_bits[0])
);
// D_OUT_0 and D_OUT_1 swapped?
// https://github.com/YosysHQ/yosys/issues/330

SB_PLL40_PAD #(
    .FEEDBACK_PATH ("SIMPLE"),
    .DIVR (4'b0000),
    .DIVF (7'b0001001),
    .DIVQ (3'b011),
    .FILTER_RANGE (3'b101)
) uut (
    .RESETB         (1'b1),
    .BYPASS         (1'b0),
    .PACKAGEPIN     (clk100),
    .PLLOUTGLOBAL   (clk_x5) // DVI clock 125MHz
);

endmodule
