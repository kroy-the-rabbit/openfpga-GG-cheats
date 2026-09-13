// SPDX-License-Identifier: GPL-3.0-or-later
//
// Draws the names of the loaded cheats over the game picture.
//
// The Pocket menu cannot do this. APF fixes every label in interact.json at
// build time and gives a core no way to put a string on screen, which is why a
// menu can only ever say "Cheat 1", "Cheat 2". The core does own every pixel of
// the game picture, though, so the list goes there instead.
//
//     3 CHEATS 6 CODES
//     INFINITE RINGS
//     KEEP SHIELD
//     ALL EMERALDS
//
// Ported from pocket-gbc's src/gb/cheat_osd.sv, Copyright (c) 2026 kroy, which
// is the right one of the three siblings to start from: a Game Gear draws
// 160x144, the same raster the Game Boy does, so the geometry carries over
// unchanged and one pixel is one clk_vid edge. See PROVENANCE.md.
//
// docs/HANDOFF.md said to take pocket-pcengine's copy for its COL0/ROW0 inset.
// That was wrong and the note is corrected: 26 cells of 6 pixels is 156 of the
// 160 across, and 18 rows of 8 is 144 exactly, so the panel already fills the
// screen and there is nowhere to inset it to. The inset exists there because a
// PC Engine raster is at least 256x224.
//
// Two things came out with the port. There is no display list: pocket-gbc walks
// a 32-bit enable mask every vertical blank to find the nth enabled cheat,
// because its loader stores every cheat and filters later, while
// cheat_loader.sv here pushes a cheat only once it knows the cheat is on, so
// titles 0 to title_count-1 are all live and already in order. That is
// pocket-pcengine's simplification. And there is no second header row naming
// where the game came from, because this core loads from the SD card only;
// PLAN.md's cartridge adapter would bring that row back.
//
// One thing is still computed ahead of the pixels that need it. Each text row
// needs 26 glyph bytes and each takes a RAM read plus a font lookup; doing that
// per pixel would put a memory on the video path. The line is built during the
// horizontal blanking before it, which is far longer than the 29 cycles needed.
//
// 17 lines of list at 144 pixels tall, against the 32 cheats CODES can hold. A
// file with more than 17 enabled cheats draws the first 17 and the header says
// how many there are, which is the only honest thing to do with this raster.

`default_nettype none

module cheat_osd #(
    // The glyph is 5 wide in an 8 wide byte, so a 6 pixel cell still leaves a
    // clear column between letters and fits 26 of them across a 160 pixel
    // screen instead of 20. Rows stay at 8: the gap under a glyph is what keeps
    // lines apart.
    parameter CELL = 6,
    parameter COLS = 26,             // 160 / 6, rounded down
    parameter ROWS = 18              // 144 / 8
) (
    input  wire        clk,          // clk_vid, one edge per pixel
    input  wire        reset,

    input  wire        show,         // menu toggle, already on this clock
    input  wire        de,           // active picture: not h or v blanked
    input  wire        v_blank,

    // Cheats that carried a name, and entries live in the two mechanisms. A
    // .chtbin has no names, so title_count is zero there while code_count is
    // not, and the header says so rather than drawing a list of blanks.
    input  wire [5:0]  title_count,
    input  wire [5:0]  code_count,

    output reg  [4:0]  title_group,  // to cheat_titles
    output reg  [4:0]  title_col,
    input  wire [5:0]  title_char,
    input  wire [4:0]  title_len,

    output wire [5:0]  font_ch,      // to cheat_font
    output wire [2:0]  font_row,
    input  wire [7:0]  font_bits,

    output wire        active,       // this pixel belongs to the overlay
    output wire        ink           // and it is part of a letter
);

  localparam HDR_ROWS  = 1;          // the counts, and nothing else to say
  localparam MAX_LINES = ROWS - HDR_ROWS;

  // ------------------------------------------------------------- pixels ----
  reg [7:0] px = 0;
  reg [7:0] py = 0;
  reg       de_d = 0;
  wire      line_end = de_d & ~de;

  always @(posedge clk) begin
    de_d <= de;
    if (reset || v_blank) begin
      px <= 8'd0;
      py <= 8'd0;
    end else begin
      px <= de ? px + 8'd1 : 8'd0;
      // py names the line about to be drawn, so the line buffer can be filled
      // during the blanking that precedes it.
      if (line_end) py <= py + 8'd1;
    end
  end

  wire [4:0] text_row  = py[7:3];
  wire [2:0] glyph_row = py[2:0];

  // 6 does not divide a bit slice, so the column is counted rather than sliced
  // out of px. Both follow px exactly: reset while blanking, one step per
  // active pixel, so they name the pixel being computed just as px does.
  //
  // 5 bits is enough here and is not elsewhere. It wraps at 32, which at a 6
  // pixel cell is pixel 192, and a Game Gear line ends at 160; pocket-pcengine
  // needed 7 because its narrowest mode is 256 wide and a 5 bit counter
  // restarted mid-line and drew the panel a second time.
  reg [4:0] text_col = 0;
  reg [2:0] pixel_col = 0;

  always @(posedge clk) begin
    if (reset || !de) begin
      text_col  <= 5'd0;
      pixel_col <= 3'd0;
    end else if (pixel_col == CELL[2:0] - 3'd1) begin
      pixel_col <= 3'd0;
      text_col  <= text_col + 5'd1;
    end else begin
      pixel_col <= pixel_col + 3'd1;
    end
  end

  // ------------------------------------------------------------- header ----
  // Font indices are ASCII - 32. Spelled out so the header needs no string ROM.
  localparam [5:0] SP = 6'd0,  A = 6'd33, C = 6'd35, D = 6'd36, E = 6'd37,
                   H = 6'd40, L = 6'd44, M = 6'd45, N = 6'd46, O = 6'd47,
                   S = 6'd51, T = 6'd52;

  function automatic [5:0] digit(input [5:0] v, input tens);
    reg [5:0] t;
    begin
      t = (v >= 6'd60) ? 6'd6 : (v >= 6'd50) ? 6'd5 : (v >= 6'd40) ? 6'd4 :
          (v >= 6'd30) ? 6'd3 : (v >= 6'd20) ? 6'd2 : (v >= 6'd10) ? 6'd1 : 6'd0;
      // A leading zero on a count of four cheats reads as a mistake, so the
      // tens column is blank below ten.
      digit = tens ? (t == 6'd0 ? SP : (6'h10 + t))   // '0' is font index 16
                   : (6'h10 + (v - (t * 6'd10)));
    end
  endfunction

  function automatic [5:0] header_char(input [4:0] col);
    begin
      if (code_count == 6'd0) begin
        // "NO CHEATS LOADED"
        case (col)
          5'd0:  header_char = N;  5'd1:  header_char = O;
          5'd3:  header_char = C;  5'd4:  header_char = H;
          5'd5:  header_char = E;  5'd6:  header_char = A;
          5'd7:  header_char = T;  5'd8:  header_char = S;
          5'd10: header_char = L;  5'd11: header_char = O;
          5'd12: header_char = A;  5'd13: header_char = D;
          5'd14: header_char = E;  5'd15: header_char = D;
          default: header_char = SP;
        endcase
      end else if (title_count == 6'd0) begin
        // "NN CODES NO NAMES": a .chtbin loaded, and it carries none. Said
        // plainly rather than drawn as a list of empty rows.
        case (col)
          5'd0:  header_char = digit(code_count, 1'b1);
          5'd1:  header_char = digit(code_count, 1'b0);
          5'd3:  header_char = C;  5'd4:  header_char = O;
          5'd5:  header_char = D;  5'd6:  header_char = E;
          5'd7:  header_char = S;
          5'd9:  header_char = N;  5'd10: header_char = O;
          5'd12: header_char = N;  5'd13: header_char = A;
          5'd14: header_char = M;  5'd15: header_char = E;
          5'd16: header_char = S;
          default: header_char = SP;
        endcase
      end else begin
        // "NN CHEATS MM CODES"
        case (col)
          5'd0:  header_char = digit(title_count, 1'b1);
          5'd1:  header_char = digit(title_count, 1'b0);
          5'd3:  header_char = C;  5'd4:  header_char = H;
          5'd5:  header_char = E;  5'd6:  header_char = A;
          5'd7:  header_char = T;  5'd8:  header_char = S;
          5'd10: header_char = digit(code_count, 1'b1);
          5'd11: header_char = digit(code_count, 1'b0);
          5'd13: header_char = C;  5'd14: header_char = O;
          5'd15: header_char = D;  5'd16: header_char = E;
          5'd17: header_char = S;
          default: header_char = SP;
        endcase
      end
    end
  endfunction

  // --------------------------------------------------------- line buffer ---
  // Filled during the blanking before the line it belongs to.
  reg [7:0] line_bits [0:COLS-1];
  reg [5:0] fill = 0;                // 0..COLS+2, past the end to drain
  reg       filling = 0;

  // Two stages: address, then write. cheat_titles registers its read once, so
  // title_char/title_len for the column presented at the address stage are
  // valid one cycle later, in step with fill_col_d2 below; nothing here has to
  // wait a further cycle for them the way the sibling cores' comment suggests
  // their own cheat_titles does. The header path carries an unneeded extra
  // register only because it used to match a three-stage version of this
  // pipeline; it is harmless to keep at two, since header_char() has no real
  // latency to wait for.
  reg [4:0] fill_col_d1 = 0, fill_col_d2 = 0;
  reg       fill_hdr_d1 = 0, fill_hdr_d2 = 0;
  reg [5:0] hdr_char_d1 = 0, hdr_char_d2 = 0;

  wire       in_header = (text_row < HDR_ROWS[4:0]);
  wire [4:0] row_index = text_row - HDR_ROWS[4:0];
  // Every title from 0 to title_count-1 is live: cheat_loader pushes a cheat
  // only once it knows the cheat is on, so there is nothing to filter here.
  wire       row_used  = in_header
                      || (row_index < MAX_LINES[4:0]
                          && {1'b0, row_index} < title_count);

  // Valid once fill_col_d2/fill_hdr_d2 name the column being written: title_char
  // and title_len are cheat_titles' answer for that same column, one cycle
  // after title_col/title_group asked for it. A version of this compared
  // against a column one stage further downstream instead, which wrote a
  // column from the NEXT column's data and leaked uninitialised RAM into the
  // last visible character of every title; found by tracing title_char
  // against fill_col_d1/d2 cycle by cycle in simulation.
  wire beyond = !fill_hdr_d2 && (fill_col_d2 >= title_len);

  always @(posedge clk) begin
    if (reset) begin
      filling <= 1'b0;
      fill    <= 6'd0;
    end else if (line_end || (v_blank && !filling && py == 8'd0)) begin
      filling <= 1'b1;
      fill    <= 6'd0;
    end else if (filling) begin
      if (fill > COLS + 2) filling <= 1'b0;
      else                 fill <= fill + 6'd1;
    end

    // Address stage: ask the title RAM and the font for column `fill`.
    title_group <= (row_used && !in_header) ? row_index : 5'd0;
    title_col   <= fill[4:0];
    fill_col_d1 <= fill[4:0];
    fill_hdr_d1 <= in_header;
    hdr_char_d1 <= header_char(fill[4:0]);

    // Write stage: the RAM is answering, so font_ch/font_bits below are valid
    // for this column now.
    fill_col_d2 <= fill_col_d1;
    fill_hdr_d2 <= fill_hdr_d1;
    hdr_char_d2 <= hdr_char_d1;
    if (filling && fill >= 6'd2 && fill_col_d2 < COLS[4:0])
      line_bits[fill_col_d2] <= row_used ? font_bits : 8'd0;
  end

  assign font_ch  = fill_hdr_d2 ? hdr_char_d2 : (beyond ? SP : title_char);
  assign font_row = glyph_row;

  // ------------------------------------------------------------- output ----
  // The sixth pixel of a cell reads bit 2, which is below the 5 wide glyph and
  // therefore always clear: the gap between letters needs no special case.
  wire [7:0] bits = line_bits[text_col];
  assign active = show && de && row_used && (text_col < COLS[4:0]);
  assign ink    = active && bits[3'd7 - pixel_col];

endmodule

`default_nettype wire
