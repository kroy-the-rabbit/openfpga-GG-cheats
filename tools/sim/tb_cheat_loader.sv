// SPDX-License-Identifier: GPL-2.0-or-later
//
// tb_cheat_loader - feed a real .cht file to rtl/gg/cheat_loader.sv and print
// every entry it pushes, in push order.
//
// tools/sim/run.py drives this and diffs the output against
// tools/cheats/gg2bin.py over libretro's Game Gear corpus. The RTL is the
// reference and the Python is what ships, so this is the only independent check
// on the thing that writes every .chtbin.
//
//   +f=<path>    the file to read
//   +gap=<n>     idle cycles between bytes, default 4
//   +eof=<0|1>   pulse eof after the last byte, default 1. With 0 the idle
//                timer has to notice, which is what IDLE_BITS shortens.

`timescale 1ns / 1ps
`default_nettype none

`ifndef IDLE_BITS
`define IDLE_BITS 20
`endif

module tb_cheat_loader;

  reg        clk = 0;
  reg        reset = 1;
  reg        wr = 0;
  reg  [7:0] data = 8'd0;
  reg        eof = 0;

  wire [128:0] gg_code;
  wire         code_reset;
  wire         poke_wr;
  wire   [4:0] poke_index;
  wire  [12:0] poke_addr;
  wire   [7:0] poke_data;
  wire   [5:0] poke_total;
  wire   [5:0] genie_count, group_count;
  wire  [19:0] byte_count;
  wire         overrun;
  wire         desc_wr, desc_end;
  wire   [4:0] desc_group, desc_col;
  wire   [5:0] desc_char;

  cheat_loader #(
      .MAX_CODES      (32),
      .IDLE_FLUSH_BITS(`IDLE_BITS)
  ) dut (
      .clk  (clk),
      .reset(reset),
      .wr   (wr),
      .data (data),
      .eof  (eof),

      .gg_code   (gg_code),
      .code_reset(code_reset),

      .poke_wr   (poke_wr),
      .poke_index(poke_index),
      .poke_addr (poke_addr),
      .poke_data (poke_data),
      .poke_total(poke_total),

      .genie_count(genie_count),
      .group_count(group_count),
      .byte_count (byte_count),
      .overrun    (overrun),

      .desc_wr   (desc_wr),
      .desc_group(desc_group),
      .desc_col  (desc_col),
      .desc_char (desc_char),
      .desc_end  (desc_end)
  );

  always #5 clk = ~clk;

  // Exactly CODES' own edge detector, so what is printed is what it latches.
  reg code_change = 0;
  always @(posedge clk) begin
    if (!reset) begin
      if (gg_code[128] && !code_change)
        $display("PUSH G %04x %02x %02x %0d",
                 gg_code[79:64], gg_code[7:0], gg_code[39:32], gg_code[96]);
      if (poke_wr)    $display("PUSH P %04x %02x %0d", poke_addr, poke_data, poke_index);
      if (desc_wr)    $display("DESC %0d %0d %0d", desc_group, desc_col, desc_char);
      if (desc_end)   $display("DESCEND %0d %0d", desc_group, desc_col);
      if (code_reset) $display("CODERESET");
    end
    code_change <= gg_code[128];
  end

  integer fd, c, gap, use_eof, i, drain;
  reg [8*512:1] fname;

  initial begin
    if (!$value$plusargs("gap=%d", gap)) gap = 4;
    if (!$value$plusargs("eof=%d", use_eof)) use_eof = 1;
    if (!$value$plusargs("f=%s", fname)) begin
      $display("FAIL no +f=<path>");
      $finish;
    end

    fd = $fopen(fname, "rb");
    if (fd == 0) begin
      $display("FAIL cannot open %0s", fname);
      $finish;
    end

    repeat (4) @(posedge clk);
    reset <= 1'b0;
    repeat (2) @(posedge clk);

    c = $fgetc(fd);
    while (c != -1) begin
      @(posedge clk);
      wr   <= 1'b1;
      data <= c[7:0];
      @(posedge clk);
      wr <= 1'b0;
      for (i = 0; i < gap; i = i + 1) @(posedge clk);
      c = $fgetc(fd);
    end
    $fclose(fd);

    repeat (8) @(posedge clk);
    if (use_eof != 0) begin
      eof <= 1'b1;
      @(posedge clk);
      eof <= 1'b0;
      drain = 4096;
    end else begin
      // The idle timer has to run out before the last cheat is resolved.
      drain = (1 << `IDLE_BITS) + 4096;
    end
    repeat (drain) @(posedge clk);

    $display("TOTAL bytes=%0d cheats=%0d genie=%0d pokes=%0d overrun=%0d",
             byte_count, group_count, genie_count, poke_total, overrun);
    $finish;
  end

endmodule

`default_nettype wire
