`ifndef SCOREBOARD_H
`define SCOREBOARD_H

`include "digits10.v"

/*
player_stats - Holds two-digit score and one-digit lives counter.
scoreboard_generator - Outputs video signal with score/lives digits.
*/

module player_stats(reset, score0, score1, lives, incscore, declives);

  input reset;
  output reg [3:0] score0;
  output reg [3:0] score1;
  input incscore;
  output reg [3:0] lives;
  input declives;

  always @(posedge incscore or posedge reset)
    begin
      if (reset) begin
        score0 <= 0;
        score1 <= 0;
      end else if (score0 == 9) begin
        score0 <= 0;
        score1 <= score1 + 1;
      end else begin
        score0 <= score0 + 1;
      end
    end

  always @(posedge declives or posedge reset)
    begin
      if (reset)
        lives <= 3;
      else if (lives != 0)
        lives <= lives - 1;
    end

endmodule

module scoreboard_generator(score0, score1, lives, vpos, hpos, board_gfx);

  input [3:0] score0;
  input [3:0] score1;
  input [3:0] lives;
  input [9:0] vpos;
  input [9:0] hpos;
  output board_gfx;

  reg [3:0] score_digit;
  reg [4:0] score_bits;

  always @(*)
    begin
      if (hpos>=204 && hpos<224) score_digit = score1;
      else if (hpos>=236 && hpos<256) score_digit = score0;
      else if (hpos>=364 && hpos<384) score_digit = lives;
      else score_digit = 15; // no digit
    end

  digits10_case digits(
    .digit(score_digit),
    .yofs(vpos[4:2]),
    .bits(score_bits)
  );

  assign board_gfx = score_bits[hpos[4:2] ^ 3'b111];

endmodule

`endif
