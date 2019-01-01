`default_nettype none // disable implicit definitions by Verilog
//-----------------------------------------------------------------
// minimalDVID_encoder.vhd : A quick and dirty DVI-D implementation
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

module top(
    input clk100, 
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

reg r, g, b;
wire [9:0] hac = hc - hbp; // Horizontal active area counter

always @(*) begin 
    // First check if we're within active video range
    if (vc >= vbp && vc < vfp && hc >= hbp && hc < hfp) begin
        // Display 80 pixel 100% saturation colour bars
        r = (hac < 160 || (hac >= 320 && hac < 480));
        g = (hac < 320);
        b = (hac < 80 || 
             (hac >= 160 && hac < 240) ||
             (hac >= 320 && hac < 400) ||
             (hac >= 480 && hac < 560));
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
