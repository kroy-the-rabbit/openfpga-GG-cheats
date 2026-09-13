// SPDX-License-Identifier: GPL-2.0-or-later
//
// tb_cheat_osd - parse a .cht, then render a frame of the overlay as text.
//
// Everything runs on one clock here, which the real core does not do: the parser
// is on clk_sys and the overlay on clk_vid, with cheat_titles as the dual clock
// RAM between them. What this checks is the composition and the geometry, which
// are clock-independent: that the header reads correctly, that the names land on
// the rows and columns they should, and that nothing falls off the 160 pixel
// line. tools/sim/run_osd.py reads the picture back and asserts on it.
//
//   +f=<path>   the .cht to load first

`timescale 1ns / 1ps
`default_nettype none

module tb_cheat_osd;

  localparam W = 160;   // active pixels per line
  localparam H = 144;   // active lines
  localparam HB = 40;   // horizontal blanking, only has to exceed the 29 fill
  localparam VB = 3;    // vertical blanking lines

  reg clk = 0;
  reg reset = 1;
  reg wr = 0;
  reg [7:0] data = 8'd0;
  reg eof = 0;
  reg de = 0;
  reg v_blank = 1;
  reg show = 1;

  wire [128:0] gg_code;
  wire code_reset, poke_wr;
  wire  [4:0] poke_index;
  wire [12:0] poke_addr;
  wire  [7:0] poke_data;
  wire  [5:0] poke_total, genie_count, group_count;
  wire [19:0] byte_count;
  wire        overrun;
  wire        desc_wr, desc_end;
  wire  [4:0] desc_group, desc_col;
  wire  [5:0] desc_char;

  cheat_loader ldr (
      .clk(clk), .reset(reset), .wr(wr), .data(data), .eof(eof),
      .gg_code(gg_code), .code_reset(code_reset),
      .poke_wr(poke_wr), .poke_index(poke_index), .poke_addr(poke_addr),
      .poke_data(poke_data), .poke_total(poke_total),
      .genie_count(genie_count), .group_count(group_count),
      .byte_count(byte_count), .overrun(overrun),
      .desc_wr(desc_wr), .desc_group(desc_group), .desc_col(desc_col),
      .desc_char(desc_char), .desc_end(desc_end)
  );

  wire [4:0] osd_group, osd_col, osd_len;
  wire [5:0] osd_char, font_ch;
  wire [2:0] font_row;
  wire [7:0] font_bits;
  wire       active, ink;

  cheat_titles titles (
      .wr_clk(clk), .wr_reset(reset),
      .wr_en(desc_wr), .wr_group(desc_group), .wr_col(desc_col),
      .wr_char(desc_char), .wr_end(desc_end),
      .rd_clk(clk), .rd_group(osd_group), .rd_col(osd_col),
      .rd_char(osd_char), .rd_len(osd_len)
  );

  cheat_font font (.ch(font_ch), .row(font_row), .bits(font_bits));

  // The counts the core feeds it: cheats that carried a name, and entries live
  // in the two mechanisms together.
  wire [6:0] codes = {1'b0, genie_count} + {1'b0, poke_total};

  cheat_osd osd (
      .clk(clk), .reset(reset),
      .show(show), .de(de), .v_blank(v_blank),
      .title_count(group_count), .code_count(codes[5:0]),
      .title_group(osd_group), .title_col(osd_col),
      .title_char(osd_char), .title_len(osd_len),
      .font_ch(font_ch), .font_row(font_row), .font_bits(font_bits),
      .active(active), .ink(ink)
  );

  always #5 clk = ~clk;

  integer fd, c, i, x, y;
  reg [8*512:1] fname;
  // Exactly W characters. An earlier W+1 left one uninitialised character at
  // the top of the vector that %0s still prints, which read as a garbage
  // glyph glued to the front of every decoded row.
  reg [8*W:1] row;

  initial begin
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

    // The file, then end of file, then long enough for every push to drain.
    c = $fgetc(fd);
    while (c != -1) begin
      @(posedge clk);
      wr <= 1'b1; data <= c[7:0];
      @(posedge clk);
      wr <= 1'b0;
      repeat (4) @(posedge clk);
      c = $fgetc(fd);
    end
    $fclose(fd);
    repeat (8) @(posedge clk);
    eof <= 1'b1; @(posedge clk); eof <= 1'b0;
    repeat (4096) @(posedge clk);

    $display("COUNTS cheats=%0d codes=%0d", group_count, codes);

    // A frame. Vertical blanking first, which is when the overlay fills the
    // buffer for line zero.
    v_blank <= 1'b1;
    de      <= 1'b0;
    repeat (VB * (W + HB)) @(posedge clk);
    v_blank <= 1'b0;

    for (y = 0; y < H; y = y + 1) begin
      for (x = 1; x <= W; x = x + 1) row[8*x-:8] = " ";
      de <= 1'b1;
      #1;
      // Pixel 0 is sampled here, before any clock edge: de was raised this
      // same instant, so pixel_col/text_col are still whatever blanking left
      // them at (0), which is the state a real display would show for the
      // first active pixel. Sampling after a posedge instead, for every pixel
      // including this one, reads the state one pixel_col tick too far: the
      // first edge under de=1 already advances the counters past 0, so every
      // column read back one pixel of the next.
      row[8*W-:8] = active === 1'bx || ink === 1'bx ? "X"
                  : active ? (ink ? "#" : ".") : " ";
      for (x = 1; x < W; x = x + 1) begin
        @(posedge clk);
        #1;
        // Left to right, so column 0 is the leftmost character of the string.
        // X spelled out rather than left to propagate through a ternary, so an
        // uninitialised cell of the line buffer is visible instead of printing
        // as some bitwise mixture of the two glyph characters.
        if (active === 1'bx || ink === 1'bx) row[8*(W-x)-:8] = "X";
        else row[8*(W-x)-:8] = active ? (ink ? "#" : ".") : " ";
      end
      @(posedge clk);
      de <= 1'b0;
      repeat (HB - 1) @(posedge clk);
      $display("ROW %0d |%0s|", y, row);
    end

    $display("DONE");
    $finish;
  end

endmodule

`default_nettype wire
