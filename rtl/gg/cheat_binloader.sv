// SPDX-License-Identifier: GPL-2.0-or-later
//
// cheat_binloader - load a packed .chtbin file into both cheat mechanisms
//
// Structure taken from pocket-gba's src/fpga/core/cheat_binloader.sv,
// Copyright (c) 2026 kroy: the magic interlock, the byte counter, the shift
// register and the two-state sequencer are all its shape. See PROVENANCE.md.
// What is different here is that this machine has two consumers rather than
// one, and a single file feeds both.
//
// The parse is on the host, for the reason pocket-gba measured: its ASCII
// parser fitted at 441 ALMs but grew that design by 1,285 and cost 0.54 ns of
// setup, because a 64-bit token shift register feeding hex conversion and a
// wide decoder gets retimed as though it were on a critical path. So
// tools/cheats does the work and nothing here transforms a byte: no hex, no
// arithmetic on a code, no decision about what a code means. Notably the
// Game Genie XXX-XXX-XXX decode happens there, not here.
//
// ------------------------------------------------------------- the format --
//
// Little-endian throughout. A 16-byte header, then entry_count 16-byte
// entries, and nothing else.
//
//   header  0..3   magic "GGCH", bytes 47 47 43 48
//           4      version, 1
//           5      reserved
//           6..7   entry_count, uint16
//           8..15  reserved
//
//   entry   0..15  one 128-bit word, byte 0 in bits [7:0]
//
// The entry is upstream's CODES word unchanged, which is why it is stored
// whole rather than trimmed to the bits a consumer reads:
//
//   [7:0]     replace, the byte a Game Genie read returns, or the byte a
//             Pro Action Replay poke writes
//   [39:32]   compare, Game Genie only, meaningful when bit 96 is set
//   [79:64]   address, the Z80 address. A poke uses its low 13 bits, which
//             is the 8KB of work RAM at C000-DFFF
//   [96]      compare flag, read by CODES as code_comp_f
//   [127]     ours, not upstream's: 1 routes the entry to cheat_poker as a
//             Pro Action Replay poke, 0 clocks it into CODES as Game Genie
//
// Bit 127 sits in the flags word that CODES never reads past bit 96, so a
// poke entry is inert on the Game Genie side by construction rather than by
// this module remembering to withhold it.
//
// The magic is a safety interlock, not decoration. The file lives in a slot
// that also accepts a plain libretro .cht, so somebody dropping the wrong one
// in is not hypothetical, and shifting ASCII into a poke table would write
// arbitrary addresses in a running game once a frame. A header that does not
// match loads zero entries and the module stays quiet for the whole file: a
// wrong file behaves as no cheats, never as garbage cheats.
//
// ---------------------------------------------------------- the handshakes --
//
// CODES clocks a code in on the rising edge of bit 128 and holds an index it
// only ever increments, so `code_reset` fires once when a header is accepted,
// before any code reaches it. Without that a second file would append to the
// first until the 32 slots filled.
//
// cheat_poker needs no reset for the same reason it needs no enable bit per
// entry: `poke_total` is the only liveness test, so a new file simply
// overwrites from index zero and republishes the count.
//

`default_nettype none

module cheat_binloader #(
    // CODES' MAX_CODES, fixed at 32 by system.vhd's component declaration,
    // which exposes only ADDR_WIDTH and DATA_WIDTH. The poke table is sized
    // to match. The readout ports are six bits, so neither may reach 64.
    parameter MAX_CODES = 32
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

    // Readout, for the menu.
    output reg   [5:0]  genie_count,  // entries clocked into CODES
    output reg   [5:0]  group_count,  // entries the header declared
    output reg  [19:0]  byte_count,   // bytes received, used or not
    output reg          overrun       // malformed: magic, version or length
);

  localparam [31:0] MAGIC   = 32'h48434747;  // "GGCH", byte 0 in the LSB
  localparam [7:0]  VERSION = 8'd1;

  // Every byte of every block is kept, header included. pocket-gba masks the
  // bytes its consumer does not read because that design ran at 97 per cent
  // occupancy; this one is at a third, and keeping the word whole is what
  // lets the format carry a field later without rewiring the register.
  reg [119:0] sr;   // bytes 0..14; the sixteenth never needs storing
  reg  [3:0]  pos;
  reg         hdr;
  reg  [5:0]  todo;

  wire done = (pos == 4'd15);
  wire pend = (todo != 6'd0);

  // The block completed by the byte arriving now. sr is always one byte
  // behind on the sixteenth strobe, so every field below reads the value
  // about to be latched rather than sr itself. pocket-gba avoids this by not
  // keeping its last three bytes; keeping all sixteen costs this wire.
  wire [127:0] word = {data, sr};

  // Header fields, valid on the sixteenth byte: byte 0 at [7:0].
  wire        hdr_ok  = (word[31:0] == MAGIC) && (word[39:32] == VERSION);
  wire        declmax = |word[63:54];        // declared count above 63
  wire [5:0]  decl    = declmax ? 6'h3F : word[53:48];

  // The entry, on the sixteenth byte.
  wire        is_poke = word[127];
  wire  [5:0] total   = genie_count + poke_total;
  wire        full    = (total == MAX_CODES);

  always @(posedge clk) begin
    if (reset) begin
      sr          <= 120'd0;
      pos         <= 4'd0;
      hdr         <= 1'b1;
      todo        <= 6'd0;
      gg_code     <= 129'd0;
      code_reset  <= 1'b0;
      poke_wr     <= 1'b0;
      poke_index  <= 5'd0;
      poke_addr   <= 13'd0;
      poke_data   <= 8'd0;
      poke_total  <= 6'd0;
      genie_count <= 6'd0;
      group_count <= 6'd0;
      byte_count  <= 20'd0;
      overrun     <= 1'b0;
    end else begin
      // All three are one cycle wide unless raised again below.
      gg_code[128] <= 1'b0;
      code_reset   <= 1'b0;
      poke_wr      <= 1'b0;

      if (wr) begin
        if (byte_count != {20{1'b1}}) byte_count <= byte_count + 20'd1;

        sr  <= {data, sr[119:8]};
        pos <= pos + 4'd1;

        if (done) begin
          if (hdr) begin
            // Whatever the verdict, the header is over. A bad one leaves todo
            // at zero, which is what makes the rest of the file inert: there
            // is no separate rejected state to fall out of sync.
            hdr <= 1'b0;
            if (hdr_ok) begin
              todo        <= decl;
              group_count <= decl;
              // Before any code reaches CODES, and the counts restart with it
              // so a second file replaces the first rather than appending.
              code_reset  <= 1'b1;
              genie_count <= 6'd0;
              poke_total  <= 6'd0;
            end else begin
              overrun <= 1'b1;
            end
          end else if (pend) begin
            todo <= todo - 6'd1;
            // Past the ceiling the entry is dropped, not wrapped: wrapping
            // would overwrite codes already loaded. The converter is meant to
            // enforce this, so reaching it means a malformed file.
            if (!full) begin
              if (is_poke) begin
                poke_wr    <= 1'b1;
                poke_index <= poke_total[4:0];
                poke_addr  <= word[76:64];
                poke_data  <= word[7:0];
                poke_total <= poke_total + 6'd1;
              end else begin
                gg_code[127:0] <= word;
                gg_code[128]   <= 1'b1;
                genie_count    <= genie_count + 6'd1;
              end
            end
          end
        end
      end else if (eof && (pos != 4'd0)) begin
        // The file's length was not a multiple of sixteen. The partial block
        // is discarded by never completing; this only records that it
        // happened. Guarded by the else so eof and wr racing over pos cannot
        // flag a good file: eof is the falling edge of the download, long
        // after data_loader's FIFO has drained.
        overrun <= 1'b1;
      end
    end
  end

endmodule

`default_nettype wire
