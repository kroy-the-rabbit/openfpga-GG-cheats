// SPDX-License-Identifier: GPL-3.0-or-later
//
// Average the machine's audio over each 48 kHz output frame.
//
// The mixer in gg_core is a level that changes whenever the PSG or the YM2413
// does, and sound_i2s takes whatever it finds when its 48 kHz frame comes
// round. The PSG is a stepped wave with few edges, so that is fine. The
// YM2413 is a sample stream at 49.7 kHz (a Z80 clock over 72), and taking a
// 49.7 kHz stream at 48 kHz drops one sample in every thirty: a buzz at the
// difference of the two rates, over every FM note.
//
// A boxcar over one output frame (about 1,119 clk_sys cycles) has its nulls
// at 48 kHz and its multiples, which is where the sample-and-hold images of
// the FM stream sit, and costs 4 dB at 24 kHz. The frame tick is generated
// here from clk_sys with a fractional accumulator, so it drifts against the
// i2s frame in clk_74a and the i2s still drops or repeats a value now and
// then, but a value that is already an average, not a raw step.
//
// The sum of up to 1,120 signed 16-bit samples fits in 27 bits. Dividing by
// the count is a multiply by 14990 / 2^24, which is 1 / 1119.2; the count
// alternates between 1,118 and 1,119, so the gain sits between 0.999 and
// 1.000 and a full-scale input cannot wrap the 16-bit slice.

`default_nettype none

module audio_frame_avg #(
    parameter CLK_HZ  = 53_693_181,
    parameter RATE_HZ = 48_000
) (
    input  wire               clk,
    input  wire signed [15:0] in_l,
    input  wire signed [15:0] in_r,
    output reg  signed [15:0] out_l = 0,
    output reg  signed [15:0] out_r = 0
);

  reg [26:0] frac = 0;
  wire tick = (frac + RATE_HZ) >= CLK_HZ;

  reg signed [26:0] acc_l = 0, acc_r = 0;
  reg signed [26:0] sum_l = 0, sum_r = 0;
  reg               dump = 0;

  always @(posedge clk) begin
    frac <= tick ? (frac + RATE_HZ - CLK_HZ) : (frac + RATE_HZ);
    dump <= tick;
    if (tick) begin
      sum_l <= acc_l + in_l;
      sum_r <= acc_r + in_r;
      acc_l <= 0;
      acc_r <= 0;
    end else begin
      acc_l <= acc_l + in_l;
      acc_r <= acc_r + in_r;
    end
  end

  wire signed [42:0] scaled_l = sum_l * 16'sd14990;
  wire signed [42:0] scaled_r = sum_r * 16'sd14990;

  always @(posedge clk) begin
    if (dump) begin
      out_l <= scaled_l[39:24];
      out_r <= scaled_r[39:24];
    end
  end

endmodule
