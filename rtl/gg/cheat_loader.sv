// SPDX-License-Identifier: GPL-2.0-or-later
//
// cheat_loader - parse a libretro .cht file into both cheat mechanisms
//
// The lexer and the deferred-push buffer are pocket-gba's
// src/fpga/core/cheat_loader.sv, Copyright (c) 2026 kroy, which in turn took
// its keyword matcher from the GB/GBC fork. The title streaming is
// pocket-pcengine's. See PROVENANCE.md. What is new here is the Game Gear
// tokeniser, because no sibling has this machine's two code formats.
//
// This is the second reader of a cheat file. cheat_binloader.sv takes the
// packed .chtbin that tools/cheats/gg2bin.py writes; this one takes the plain
// libretro .cht the user drops next to the ROM. core_top.v sniffs the first
// four bytes for the "GGCH" magic and muxes between them. Both are shipped for
// the reason pocket-gba shipped both: a .chtbin carries no names, and the
// overlay's list can only come from `cheatN_desc`.
//
// tools/cheats/gg2bin.py plus tools/cheats/ggcht.py are the executable model of
// this module, and tools/sim/run.py diffs the two over libretro's 818 Game Gear
// files. Keep them in step. The Python is what converts; this is the reference
// the Python is checked against, and the Game Genie decode below is checked in
// turn against real ROM bytes (docs/PLAN.md S4).
//
// ------------------------------------------------------------- what it takes --
//
// Two formats, both written as groups of hex digits joined by '-' or '+':
//
//   XXX-XXX-XXX   Game Genie, a ROM read override.  3,585 in the corpus
//   XXX-XXX       the same without the compare group.   10 in the corpus
//   xxAAAA-DD     Pro Action Replay, a work RAM poke. 3,058 in the corpus
//
// The corpus is not consistent about its separator: 924 codes write one
// nine-digit Game Genie code as `058+BA8+E66`, while 502 use '+' between whole
// codes. So both characters separate groups, and the code boundary comes from
// the group WIDTH instead: threes are Game Genie and take three groups to a
// code, fours are Pro Action Replay and take two.
//
// The width has to be consistent across the whole field. `010-75F-E6` is not a
// Game Genie code with a short tail, it is a field this module cannot regroup
// without guessing where a code ends, and a wrong guess writes an arbitrary
// address into a running game once a frame. So a field whose groups are not all
// three wide or all four wide contributes nothing, and neither does one
// carrying a character that is neither hex nor a placeholder: the letter O
// typed for a zero is most of the fourteen in the corpus, and correcting it is
// exactly the guess just ruled out.
//
// A code carrying X or ? is a modifier whose value the player was meant to
// choose. There is nothing to write, so it is skipped; the rest of the field
// still counts. That is a per-code verdict, unlike the two above, which
// condemn the whole field.
//
// ----------------------------------------------------------- the Game Genie --
//
// Nine digits d0..d8, dashes stripped:
//
//   replace = d0 d1
//   address = (d5 ^ 0xF) << 12 | d2 << 8 | d3 << 4 | d4
//   compare = ror2(d6 << 4 | d8) ^ 0xBA          and d7 is discarded
//
// d7 really is unused. That was settled empirically, not from a document: a
// Game Genie compare byte is the ORIGINAL byte at the patched address, so a
// correct decode predicts the ROM. Over the corpus this reads 230 of 242
// checkable codes correctly and 29 of 33 games cleanly, where the two
// alternative placements of d7 score 5 per cent and 0. docs/PLAN.md S4 has the
// evidence and tools/cheats/ggcht.py is the check.
//
// Pro Action Replay is `00AAAA-DD`: the leading pair is 00 in all 3,291 found,
// the address is C000-DFFF in 3,191 of the 3,195 that are not the placeholder
// 0000-0000, and cheat_poker takes its low thirteen bits. A poke outside work
// RAM is dropped.
//
// -------------------------------------------------- why a cheat is buffered --
//
// Which cheats are on comes from the file, via `cheatN_enable`, and libretro
// writes that key AFTER the codes it applies to. pocket-pcengine can commit a
// code optimistically and roll it back, because its poke table is an array and
// a count. system.vhd's CODES cannot: its index only ever increments and there
// is no way to withdraw a code once clocked in. So a cheat's entries are
// collected into a buffer and pushed only once its enable state is known, at
// its enable key, at the start of the next cheat, or at end of file. The buffer
// has two banks so the next cheat can be collected while the previous one is
// still going out.
//
// Unlike pocket-gba, a cheat here is NOT all or nothing. Its reason does not
// carry: a GBA compare entry suppresses the following table slot, so half a
// cheat could silence an unrelated one, while every entry here is independent.
// So the ceiling truncates mid-cheat, which is also what the host converter
// does, and the two agree entry for entry.
//

`default_nettype none

module cheat_loader #(
    // CODES' MAX_CODES, fixed at 32 by system.vhd's component declaration. The
    // poke table is sized to match and the ceiling is on the two together, so
    // one buffer bank of this depth can never be the binding limit.
    parameter MAX_CODES = 32,
    // Bytes must stop arriving for this many clk cycles before end of file is
    // assumed. APF delivers a 32-bit word about every microsecond, roughly a
    // hundred cycles of clk_sys, so 2^20 cannot fire inside a transfer.
    parameter IDLE_FLUSH_BITS = 20
) (
    input  wire         clk,
    input  wire         reset,

    input  wire         wr,          // byte strobe from data_loader
    input  wire  [7:0]  data,
    input  wire         eof,         // falling edge of the cheats download

    // To system.vhd's GAMEGENIE, through gg_core.
    output reg  [128:0] gg_code,
    output reg          code_reset,

    // To cheat_poker's table load port.
    output reg          poke_wr,
    output reg   [4:0]  poke_index,
    output reg  [12:0]  poke_addr,
    output reg   [7:0]  poke_data,
    output reg   [5:0]  poke_total,

    // Readout, for the menu. Same four as cheat_binloader so core_top can mux
    // the two loaders onto one set of registers, but group_count means cheats
    // accepted here where the binary loader means entries declared.
    output reg   [5:0]  genie_count,
    output reg   [5:0]  group_count,
    output reg  [19:0]  byte_count,
    output reg          overrun,

    // The text of `cheatN_desc`, streamed to cheat_titles for the overlay, into
    // the slot the next accepted cheat will take. A cheat that is dropped or
    // disabled does not advance the slot, so the next name overwrites it.
    //
    // The slot is read at the description's opening quote, and the cheat before
    // it is handed over at the following `_code` key, so a file with no enable
    // keys at all puts two names in one slot. libretro writes an enable key for
    // every cheat in all 818 files, which resolves the previous cheat first.
    // pocket-gba has the same hole and the same reason for leaving it.
    output reg          desc_wr,
    output reg   [4:0]  desc_group,
    output reg   [4:0]  desc_col,
    output reg   [5:0]  desc_char,   // ASCII - 32, uppercased
    output reg          desc_end     // desc_col is now the length
);

  localparam AW      = $clog2(MAX_CODES);   // 5 for 32
  localparam CW      = AW + 1;              // counts, so 0..MAX_CODES fits
  localparam TITLE_W = 26;                  // cheat_titles is 26 wide

  // ---------------------------------------------------------------- lexing --
  // A keyword only counts as a key once '=' follows it: `_code` is a substring
  // of `notes_codecs`, and a comment reading `# _code means "Facade"` would
  // otherwise emit a patch out of the description after it. Free text is never
  // tokenised.
  localparam [39:0] KEY_CODE   = "_code";
  localparam [39:0] KEY_DESC   = "_desc";
  localparam [55:0] KEY_ENABLE = "_enable";

  reg [55:0] hist;
  reg        pend_code, pend_desc, pend_enable;
  reg        armed_code, armed_desc, armed_enable;
  reg        in_str;      // skipping an uninteresting quoted string
  reg        capturing;   // inside the quoted value of a _desc key
  reg  [4:0] desc_n;      // characters captured so far
  reg        collecting;  // inside the quoted value of a _code key
  reg        started;     // a byte of this file has been seen

  wire [7:0] ch       = data;
  wire       is_quote = (ch == 8'h22);
  wire       is_nl    = (ch == 8'h0A) || (ch == 8'h0D);
  wire       is_space = (ch == " ") || (ch == 8'h09);
  wire       is_dig   = (ch >= "0") && (ch <= "9");
  wire       is_up    = (ch >= "A") && (ch <= "F");
  wire       is_lo    = (ch >= "a") && (ch <= "f");
  wire       is_hex   = is_dig | is_up | is_lo;
  wire       is_alpha = ((ch >= "A") && (ch <= "Z")) || ((ch >= "a") && (ch <= "z"));
  wire       is_alnum = is_alpha | is_dig;
  wire       says_on  = (ch == "t") || (ch == "T") || (ch == "1");
  wire       is_ph    = (ch == "X") || (ch == "x") || (ch == "?");
  wire       is_sep   = (ch == "+") || (ch == "-");
  wire [3:0] nibble   = is_dig ? (ch - "0")
                      : is_up  ? (ch - "A" + 8'd10)
                               : (ch - "a" + 8'd10);

  function automatic [5:0] font_index(input [7:0] c);
    reg [7:0] up;
    begin
      up = (c >= "a" && c <= "z") ? (c - 8'd32) : c;
      font_index = (up >= 8'd32 && up <= 8'd95) ? (up - 8'd32) : 6'd0;
    end
  endfunction

  // ------------------------------------------------------------ tokenising --
  // Digits are kept individually rather than shifted into one word, because
  // both decodes are permutations: the Game Genie address takes d5 inverted,
  // then d2, d3, d4, and the compare takes d6 and d8 and throws d7 away.
  reg  [3:0] dg [0:8];
  reg  [3:0] ndig;      // digits in the code under construction, 0..9
  reg  [2:0] gw;        // digits in the group under construction
  reg  [2:0] step_w;    // the field's group width, 0 until the first group ends
  reg  [1:0] ngrp;      // groups closed into this code
  reg        ph;        // this code carries an X or a ?
  reg        fld_bad;   // the whole field is unusable, see the header
  reg        sp_seen;   // whitespace since the last digit

  // The model strips the field before splitting it, so whitespace before the
  // first digit and after the last is allowed and whitespace in between is not.
  // The trailing case needs no lookahead: the flag is simply never read again.
  wire ws_lead = (ndig == 4'd0) & (ngrp == 2'd0) & (gw == 3'd0);

  reg [IDLE_FLUSH_BITS-1:0] idle;
  wire idle_done = (idle == {IDLE_FLUSH_BITS{1'b1}});
  reg  eof_seen;
  wire at_eof = eof_seen | idle_done;

  // The field ends at its closing quote, at a newline inside it, or when the
  // file stops with the quote still open. Everything the emit below reads is a
  // register, so the end-of-file case needs no byte to have arrived.
  wire fld_end = collecting & ((wr & (is_quote | is_nl)) | (~wr & at_eof));
  wire sep_now = collecting & wr & ~fld_bad & is_sep;

  // A group closes on this byte. A separator with no digits behind it closes
  // nothing, which is how `058--BA8` and a trailing `-` come out the same as
  // the model's split-and-drop-empties.
  wire       close_v = (sep_now | fld_end) & (gw != 3'd0) & ~fld_bad;
  wire [2:0] w_ref   = (step_w != 3'd0) ? step_w : gw;
  wire       w_ok    = (step_w != 3'd0) ? (gw == step_w)
                                        : ((gw == 3'd3) | (gw == 3'd4));
  wire       w_fail  = close_v & ~w_ok;
  wire [1:0] ngrp_n  = ngrp + {1'b0, close_v};
  wire [1:0] step_n  = (w_ref == 3'd3) ? 2'd3 : 2'd2;

  // A code is complete after step_n groups, and whatever is left when the field
  // ends is a code too: the model's chunking leaves a short final chunk, which
  // is the only way the six-digit Game Genie form ever appears.
  wire complete = close_v & w_ok & (ngrp_n == step_n);
  wire emit     = ~fld_bad & ~w_fail
                & (fld_end ? (ndig != 4'd0) : complete);

  // ------------------------------------------------------------- decoding --
  wire [15:0] genie_addr = {(dg[5] ^ 4'hF), dg[2], dg[3], dg[4]};
  wire  [7:0] genie_repl = {dg[0], dg[1]};
  wire  [7:0] genie_raw  = {dg[6], dg[8]};            // d7 discarded
  wire  [7:0] genie_cmp  = {genie_raw[1:0], genie_raw[7:2]} ^ 8'hBA;
  wire [15:0] par_addr   = {dg[2], dg[3], dg[4], dg[5]};
  wire  [7:0] par_val    = {dg[6], dg[7]};

  wire em_g9 = (ndig == 4'd9);
  wire em_g6 = (ndig == 4'd6);
  wire em_p8 = (ndig == 4'd8)
             & (par_addr >= 16'hC000) & (par_addr <= 16'hDFFF);
  wire em_ok = emit & ~ph & (em_g9 | em_g6 | em_p8);

  // {is_poke, compare valid, compare, address, replace or poke value}
  localparam EW = 34;
  wire [EW-1:0] em_word =
      em_p8 ? {1'b1, 1'b0, 8'd0,      par_addr,   par_val}
    : em_g9 ? {1'b0, 1'b1, genie_cmp, genie_addr, genie_repl}
            : {1'b0, 1'b0, 8'd0,      genie_addr, genie_repl};

  // ------------------------------------------------------------ the buffer --
  reg [EW-1:0]  gbuf [0:2*MAX_CODES-1];
  reg           bank;
  reg [CW-1:0]  buf_len;

  // Past the buffer the entry is dropped rather than wrapped. The ceiling below
  // would have cut it anyway, so this is not a second policy.
  wire          buf_wr    = em_ok & (buf_len != MAX_CODES[CW-1:0]);
  wire [CW-1:0] nx_len    = buf_len + {{(CW-1){1'b0}}, buf_wr};

  // ------------------------------------ the cheat waiting on its enable key --
  reg          pend_valid, pend_bank, pend_bad;
  reg [CW-1:0] pend_len;

  // The end-of-file flush, held one cycle. Every other push takes its length
  // from pend_len, a register; this one alone would take nx_len and drag the
  // token decode through an adder into the push. pocket-gba measured that as
  // the worst path in its design, so the flush latches and pushes on the next
  // clock. No more bytes are coming, so the cycle costs nothing.
  reg          eof_flush, eof_bank, eof_bad;
  reg [CW-1:0] eof_len;

  // ------------------------------------------------------------ the pusher --
  reg [CW-1:0] fl_idx, fl_len;
  reg          fl_bank;
  reg  [1:0]   fl_state;   // 0 idle, 1 read the buffer, 2 hand the entry over
  reg [EW-1:0] fl_q;

  // One queued request, so a cheat can be handed over while the previous one is
  // still going out. A cheat is at least a dozen bytes of text apart from the
  // next and a push is two cycles an entry, so two deep is not needed.
  reg          req_valid, req_bank;
  reg [CW-1:0] req_len;

  // The ceiling is on the two mechanisms together, exactly as the converter's
  // single entry list is.
  wire [6:0]   total = {1'b0, genie_count} + {1'b0, poke_total};
  wire [CW-1:0] room = MAX_CODES[CW-1:0] - total[CW-1:0];

  // Named once because a cheat is handed to the pusher from three places. Set
  // and read inside the one always block, so blocking, and nothing continuous
  // may be derived from them.
  reg          push_go, push_bank, push_bad;
  reg [CW-1:0] push_len;

  integer i;

  always @(posedge clk) begin
    if (reset) begin
      hist        <= 56'd0;
      pend_code   <= 1'b0;  pend_desc  <= 1'b0;  pend_enable  <= 1'b0;
      armed_code  <= 1'b0;  armed_desc <= 1'b0;  armed_enable <= 1'b0;
      in_str      <= 1'b0;  capturing  <= 1'b0;  collecting   <= 1'b0;
      desc_n      <= 5'd0;  started    <= 1'b0;
      desc_wr     <= 1'b0;  desc_end   <= 1'b0;  desc_group   <= 5'd0;
      desc_col    <= 5'd0;  desc_char  <= 6'd0;
      for (i = 0; i < 9; i = i + 1) dg[i] <= 4'd0;
      ndig        <= 4'd0;  gw         <= 3'd0;  step_w       <= 3'd0;
      ngrp        <= 2'd0;  ph         <= 1'b0;  fld_bad      <= 1'b0;
      sp_seen     <= 1'b0;
      bank        <= 1'b0;  buf_len    <= 0;
      pend_valid  <= 1'b0;  pend_bank  <= 1'b0;  pend_len     <= 0;
      pend_bad    <= 1'b0;
      eof_flush   <= 1'b0;  eof_bank   <= 1'b0;  eof_len      <= 0;
      eof_bad     <= 1'b0;
      req_valid   <= 1'b0;  req_bank   <= 1'b0;  req_len      <= 0;
      fl_idx      <= 0;     fl_len     <= 0;     fl_bank      <= 1'b0;
      fl_state    <= 2'd0;  fl_q       <= 0;
      gg_code     <= 129'd0;
      code_reset  <= 1'b0;
      poke_wr     <= 1'b0;  poke_index <= 5'd0;  poke_addr    <= 13'd0;
      poke_data   <= 8'd0;  poke_total <= 6'd0;
      genie_count <= 6'd0;  group_count <= 6'd0; byte_count   <= 20'd0;
      overrun     <= 1'b0;
      eof_seen    <= 1'b0;  idle       <= 0;
    end else begin
      push_go   = 1'b0;
      push_bank = 1'b0;
      push_len  = 0;
      push_bad  = 1'b0;

      // All four are one cycle wide unless raised again below.
      gg_code[128] <= 1'b0;
      code_reset   <= 1'b0;
      poke_wr      <= 1'b0;
      desc_wr      <= 1'b0;
      desc_end     <= 1'b0;

      // ---------------------------------------------------- push sequencer --
      // CODES latches on the rising edge of code[128] with the word already
      // presented, so state 2 assigns both together and the default above
      // drops the bit again on the next cycle. State 1 exists so the buffer is
      // read synchronously, which is what lets it infer as block RAM rather
      // than a wall of LUT RAM.
      case (fl_state)
        2'd1: begin
          fl_q     <= gbuf[{fl_bank, fl_idx[AW-1:0]}];
          fl_state <= 2'd2;
        end
        2'd2: begin
          if (total[CW-1:0] == MAX_CODES[CW-1:0]) begin
            // The ceiling, reached inside a cheat. The rest of it is dropped,
            // which is what the converter's list truncation does.
            fl_state <= 2'd0;
          end else begin
            if (fl_q[33]) begin
              poke_wr    <= 1'b1;
              poke_index <= poke_total[AW-1:0];
              poke_addr  <= fl_q[20:8];
              poke_data  <= fl_q[7:0];
              poke_total <= poke_total + 6'd1;
            end else begin
              gg_code[127:0] <= {31'd0, fl_q[32],     // compare valid, bit 96
                                 16'd0, fl_q[23:8],   // address at 79:64
                                 24'd0, fl_q[31:24],  // compare at 39:32
                                 24'd0, fl_q[7:0]};   // replace at 7:0
              gg_code[128]   <= 1'b1;
              genie_count    <= genie_count + 6'd1;
            end
            if (fl_idx + 1'b1 == fl_len) fl_state <= 2'd0;
            else begin
              fl_idx   <= fl_idx + 1'b1;
              fl_state <= 2'd1;
            end
          end
        end
        default: begin
          if (req_valid) begin
            req_valid <= 1'b0;
            fl_bank   <= req_bank;
            fl_len    <= req_len;
            fl_idx    <= 0;
            fl_state  <= 2'd1;
          end
        end
      endcase

      // -------------------------------------------------------- idle timer --
      // Only runs while there is something an end of file would resolve.
      if (eof) eof_seen <= 1'b1;
      if (wr) idle <= 0;
      else if (!idle_done && (pend_valid || collecting)) idle <= idle + 1'b1;

      // ------------------------------------------------------ byte arrival --
      if (wr) begin
        if (byte_count != {20{1'b1}}) byte_count <= byte_count + 20'd1;

        // CODES holds an index it only ever increments, so its table is cleared
        // once at the head of the file, well before any code reaches it.
        // Without this a second file would append to the first.
        if (!started) begin
          started     <= 1'b1;
          code_reset  <= 1'b1;
          genie_count <= 6'd0;
          poke_total  <= 6'd0;
        end

        if (collecting) begin
          if (buf_wr) gbuf[{bank, buf_len[AW-1:0]}] <= em_word;
          if (emit) begin
            buf_len <= nx_len;
            ndig    <= 4'd0;
            ngrp    <= 2'd0;
            gw      <= 3'd0;
            ph      <= 1'b0;
          end

          if (is_quote || is_nl) begin
            // The field is over. Park this cheat until its enable is known.
            collecting <= 1'b0;
            ndig       <= 4'd0;  gw      <= 3'd0;  ngrp    <= 2'd0;
            ph         <= 1'b0;  step_w  <= 3'd0;  sp_seen <= 1'b0;
            fld_bad    <= 1'b0;  buf_len <= 0;
            if (nx_len != 0) begin
              // Structurally nothing can be parked here: the opening quote of
              // this cheat handed the previous one over. Raised rather than
              // silently overwritten so the invariant is checkable in
              // simulation instead of assumed.
              if (pend_valid) overrun <= 1'b1;
              pend_valid <= 1'b1;
              pend_bank  <= bank;
              pend_len   <= nx_len;
              pend_bad   <= fld_bad | w_fail;
              bank       <= ~bank;
            end
          end else if (fld_bad) begin
            // Swallow the rest of the field. The verdict is already recorded
            // and cannot be revoked.
          end else if (is_hex || is_ph) begin
            if (sp_seen) fld_bad <= 1'b1;
            else begin
              if (ndig < 4'd9) dg[ndig] <= is_ph ? 4'd0 : nibble;
              ndig <= ndig + 4'd1;
              gw   <= gw + 3'd1;
              if (is_ph) ph <= 1'b1;
              // Only three and four are code shapes, so a wider group is the
              // whole field's problem, not this code's.
              if ((gw + 3'd1) > ((step_w != 3'd0) ? step_w : 3'd4))
                fld_bad <= 1'b1;
            end
          end else if (is_sep) begin
            if (sp_seen) fld_bad <= 1'b1;
            else if (gw != 3'd0) begin
              if (!w_ok) fld_bad <= 1'b1;
              else begin
                if (step_w == 3'd0) step_w <= gw;
                if (!complete) ngrp <= ngrp_n;
                gw <= 3'd0;
              end
            end
          end else if (is_space) begin
            if (!ws_lead) sp_seen <= 1'b1;
          end else begin
            fld_bad <= 1'b1;
          end
        end else if (in_str) begin
          if (is_quote) begin
            in_str    <= 1'b0;
            capturing <= 1'b0;
            if (capturing) begin
              desc_end <= 1'b1;
              desc_col <= desc_n;             // the length
            end
          end else if (capturing && desc_n < TITLE_W[4:0]) begin
            // desc_col names the column of this character, on the same clock as
            // the strobe; the running count is kept apart from it.
            desc_wr   <= 1'b1;
            desc_char <= font_index(ch);
            desc_col  <= desc_n;
            desc_n    <= desc_n + 5'd1;
          end
        end else if (armed_enable && is_alnum) begin
          // The value of a cheatN_enable key: the first word after it. "true"
          // and "1" mean on, anything else means off and the cheat is dropped.
          if (pend_valid) begin
            pend_valid <= 1'b0;
            if (says_on) begin
              push_go   = 1'b1;
              push_bank = pend_bank;
              push_len  = pend_len;
              push_bad  = pend_bad;
            end
          end
          armed_enable <= 1'b0;
          pend_code    <= 1'b0; pend_desc <= 1'b0; pend_enable <= 1'b0;
          hist         <= 56'd0;
        end else if (is_quote) begin
          armed_code <= 1'b0; armed_desc <= 1'b0; armed_enable <= 1'b0;
          pend_code  <= 1'b0; pend_desc  <= 1'b0; pend_enable  <= 1'b0;
          hist       <= 56'd0;
          if (armed_code) begin
            // A new cheat starts. Whatever is parked had no enable key at all,
            // which means on, so a hand-written file of nothing but codes works.
            if (pend_valid) begin
              pend_valid <= 1'b0;
              push_go    = 1'b1;
              push_bank  = pend_bank;
              push_len   = pend_len;
              push_bad   = pend_bad;
            end
            collecting <= 1'b1;
            ndig       <= 4'd0;  gw      <= 3'd0;  ngrp    <= 2'd0;
            ph         <= 1'b0;  step_w  <= 3'd0;  sp_seen <= 1'b0;
            fld_bad    <= 1'b0;  buf_len <= 0;
          end else begin
            in_str <= 1'b1;
            if (armed_desc) begin
              capturing  <= 1'b1;
              desc_group <= group_count[4:0];
              desc_n     <= 5'd0;
            end
          end
        end else begin
          hist <= {hist[47:0], ch};
          if ({hist[47:0], ch} == KEY_ENABLE) begin
            pend_enable <= 1'b1;  pend_code  <= 1'b0;  pend_desc    <= 1'b0;
            armed_code  <= 1'b0;  armed_desc <= 1'b0;  armed_enable <= 1'b0;
          end else if ({hist[31:0], ch} == KEY_CODE) begin
            pend_code   <= 1'b1;  pend_desc  <= 1'b0;  pend_enable  <= 1'b0;
            armed_code  <= 1'b0;  armed_desc <= 1'b0;  armed_enable <= 1'b0;
          end else if ({hist[31:0], ch} == KEY_DESC) begin
            pend_desc   <= 1'b1;  pend_code  <= 1'b0;  pend_enable  <= 1'b0;
            armed_code  <= 1'b0;  armed_desc <= 1'b0;  armed_enable <= 1'b0;
          end else if (ch == "=") begin
            // Only now is it a key. Whatever was pending becomes armed.
            armed_code   <= pend_code;
            armed_desc   <= pend_desc;
            armed_enable <= pend_enable;
            pend_code    <= 1'b0;  pend_desc <= 1'b0;  pend_enable <= 1'b0;
          end else if (!is_space) begin
            // Anything else between the keyword and '=' means it was not a key,
            // just those characters inside a longer word or a comment.
            pend_code    <= 1'b0;  pend_desc <= 1'b0;  pend_enable <= 1'b0;
          end
        end
      end else if (at_eof && (pend_valid || collecting)) begin
        // Nothing more is coming. An unterminated field ends here, and whatever
        // is parked goes out with no enable key, which means on.
        idle       <= 0;
        eof_seen   <= 1'b0;
        collecting <= 1'b0;
        ndig       <= 4'd0;  gw      <= 3'd0;  ngrp    <= 2'd0;
        ph         <= 1'b0;  step_w  <= 3'd0;  sp_seen <= 1'b0;
        fld_bad    <= 1'b0;
        // Digits left when the file ended still count, exactly as the closing
        // quote would have counted them.
        if (buf_wr) gbuf[{bank, buf_len[AW-1:0]}] <= em_word;
        buf_len <= 0;
        if (pend_valid) begin
          pend_valid <= 1'b0;
          eof_flush  <= 1'b1;
          eof_bank   <= pend_bank;
          eof_len    <= pend_len;
          eof_bad    <= pend_bad;
        end else if (nx_len != 0) begin
          bank      <= ~bank;
          eof_flush <= 1'b1;
          eof_bank  <= bank;
          eof_len   <= nx_len;
          eof_bad   <= fld_bad | w_fail;
        end
      end else if (eof_flush) begin
        // The cycle after: everything the push needs is now a register.
        eof_flush <= 1'b0;
        push_go   = 1'b1;
        push_bank = eof_bank;
        push_len  = eof_len;
        push_bad  = eof_bad;
      end

      // ------------------------------------------------- hand over a cheat --
      if (push_go) begin
        if (push_bad || push_len == 0) begin
          // Nothing to push, or a field this module refused whole.
        end else if (req_valid) begin
          // Unreachable with a real file: a cheat is at least a dozen bytes of
          // text apart from the next and a push is two cycles an entry. Raised
          // rather than silently dropped so it shows in the readout.
          overrun <= 1'b1;
        end else if (room != 0) begin
          req_valid   <= 1'b1;
          req_bank    <= push_bank;
          req_len     <= push_len;
          group_count <= group_count + 6'd1;
        end
      end
    end
  end

endmodule

`default_nettype wire
