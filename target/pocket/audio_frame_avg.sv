// SPDX-License-Identifier: GPL-3.0-or-later
//
// Average the mixer output over the first 1,024 clk_sys cycles of each 48 kHz
// output frame, before sound_i2s samples it. The YM2413 is a 49.7 kHz sample
// stream; sampled raw at 48 kHz it drops one sample in thirty, a 1.7 kHz
// buzz. The window's nulls sit at 52.4 kHz multiples, 25 dB down at 49.7 kHz,
// 4 dB down at 24 kHz. Power of two so the divide is a shift and there is no
// multiplier: a DSP-block multiply here failed hold by 20 ps on every seed.

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

  // 1,024 samples of 16 bits fit in 26 bits.
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
