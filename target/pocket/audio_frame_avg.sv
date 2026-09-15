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
// A boxcar over the first 1,024 clk_sys cycles of each output frame (the
// frame is about 1,119 cycles) has its nulls at 52.4 kHz and its multiples,
// which puts the sample-and-hold images of the FM stream at 49.7 kHz and
// 99.4 kHz 25 dB down, and costs 4 dB at 24 kHz. The frame tick is generated
// here from clk_sys with a fractional accumulator, so it drifts against the
// i2s frame in clk_74a and the i2s still drops or repeats a value now and
// then, but a value that is already an average, not a raw step.
//
// A power-of-two window because the divide is then a shift. The first cut
// averaged the whole frame and scaled by a constant, and Quartus packed the
// sum register into the DSP multiplier's input stage, whose clock arrives
// 0.65 ns after the fabric flops feeding it: a 20 ps hold violation at the
// slow cold corner on every seed. No multiplier, no DSP block, no such path.

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

  // 1,024 samples of 16 bits fit in 26 bits; the window counter's carry
  // closes it.
  reg signed [26:0] acc_l = 0, acc_r = 0;
  reg        [10:0] n = 11'd1024;   // bit 10 set: window closed

  always @(posedge clk) begin
    frac <= tick ? (frac + RATE_HZ - CLK_HZ) : (frac + RATE_HZ);
    if (tick) begin
      out_l <= acc_l[25:10];
      out_r <= acc_r[25:10];
      acc_l <= 27'sd0;
      acc_r <= 27'sd0;
      n     <= 11'd0;
    end else if (!n[10]) begin
      acc_l <= acc_l + in_l;
      acc_r <= acc_r + in_r;
      n     <= n + 1'b1;
    end
  end

endmodule
