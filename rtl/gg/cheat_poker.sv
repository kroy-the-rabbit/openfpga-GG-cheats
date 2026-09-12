// SPDX-License-Identifier: GPL-3.0-or-later
//
// cheat_poker - write cheat values into Game Gear work RAM once a frame
//
// Ported from pocket-pcengine's rtl/pce/cheat_poker.sv, which is itself from
// the Game Boy fork. The logic is unchanged; only the comments and the work
// RAM it writes into are this machine's. See docs/PROVENANCE.md.
//
// This is Pro Action Replay, one of the two mechanisms this machine needs.
// The PC Engine fork found every code in its corpus was a RAM poke and cut the
// read override entirely; the Game Boy fork ranks the read override first.
// Game Gear is the one that needs both: of the first 25 libretro files, 94
// codes are Game Genie and 63 are Pro Action Replay (PLAN.md S4). So this
// module is half the feature and `system`'s GAMEGENIE instance is the other.
//
// A poke is what the cheat device actually did: write the value once a frame
// and let the game read it back. A PAR code XXXX-XXXX is an address and a
// byte, and the address lands in the 8KB work RAM at C000-DFFF, which is not
// banked, so there is no bank qualifier to check.
//
// Writes go out through port B of the work RAM dpram, which otherwise belongs
// to the cold-reset clear. The clear wins whenever it wants the port: it runs
// once per load, this runs once per frame, and a poke it swallows is simply
// reissued at the next vblank. `blocked` abandons the walk rather than
// stalling it, for the same reason.
//
// The code table is a small memory, not a register file, so a fresh
// scan_index costs one cycle before the entry is readable. That is what
// SETTLE is for. Keeping the table in block RAM also keeps the per-code
// lookup off any data path, which matters more here than it did on the PC
// Engine: this design's hold margin is its tightest yet (BASELINE.md).
//
// `code_total` is the loader's committed count and the only liveness test
// there is: a cheat the file disables is staged into the table and then never
// counted, so the next one overwrites it. That is why entries carry no enable
// bit and why loading a new file needs no clearing walk.
//

`default_nettype none

module cheat_poker #(
    parameter MAX_CODES = 32,
    parameter INDEX_W   = 5
) (
    input  wire                clk,
    input  wire                reset,
    input  wire                enable,    // master cheat switch
    input  wire                vblank,    // level from the VCE, edge detected here
    input  wire                blocked,   // cold-reset clear owns port B

    // Table load port, driven by cheat_loader.
    input  wire                code_wr,
    input  wire [INDEX_W-1:0]  code_index,
    input  wire [12:0]         code_addr,  // offset into the 8KB at C000-DFFF
    input  wire [7:0]          code_data,
    input  wire [INDEX_W:0]    code_total,

    // Work RAM write, in the dpram's port B clock domain.
    // Given explicit power-up values rather than left to the fitter: a poke_wr
    // that comes up asserted writes into work RAM before the cold-reset clear
    // has had a chance to run.
    output reg                 poke_wr   = 0,
    output reg  [12:0]         poke_addr = 0,
    output reg  [7:0]          poke_data = 0
);

  localparam ENTRY_W = 21;  // {addr[12:0], data[7:0]}

  localparam [2:0] IDLE = 3'd0, SETTLE = 3'd1, LOOK = 3'd2,
                   WRITE = 3'd3, NEXT = 3'd4;

  reg [ENTRY_W-1:0] tbl [0:MAX_CODES-1];
  reg [ENTRY_W-1:0] entry = 0;

  reg [INDEX_W-1:0] scan_index = 0;
  reg [2:0]         state = IDLE;
  reg               vblank_d = 0;

  wire vblank_rise = vblank & ~vblank_d;

  always @(posedge clk) begin
    if (code_wr) tbl[code_index] <= {code_addr, code_data};
    entry <= tbl[scan_index];
  end

  wire [12:0] entry_addr = entry[20:8];
  wire  [7:0] entry_data = entry[7:0];

  wire [INDEX_W:0] last_index = (code_total == 0) ? {(INDEX_W+1){1'b0}}
                                                  : code_total - 1'b1;

  always @(posedge clk) begin
    if (reset) begin
      state      <= IDLE;
      scan_index <= {INDEX_W{1'b0}};
      poke_wr    <= 1'b0;
      poke_addr  <= 13'd0;
      poke_data  <= 8'd0;
      vblank_d   <= 1'b0;
    end else begin
      vblank_d <= vblank;
      poke_wr  <= 1'b0;

      if (blocked || !enable || code_total == 0) begin
        // hand the port back at once; the walk restarts at the next vblank
        state <= IDLE;
      end else begin
        case (state)
          IDLE:
          if (vblank_rise) begin
            scan_index <= {INDEX_W{1'b0}};
            state      <= SETTLE;
          end

          SETTLE: state <= LOOK;

          LOOK: begin
            poke_addr <= entry_addr;
            poke_data <= entry_data;
            poke_wr   <= 1'b1;
            state     <= WRITE;
          end

          WRITE: state <= NEXT;

          NEXT:
          if ({1'b0, scan_index} >= last_index) begin
            state <= IDLE;
          end else begin
            scan_index <= scan_index + 1'b1;
            state      <= SETTLE;
          end

          default: state <= IDLE;
        endcase
      end
    end
  end

endmodule

`default_nettype wire
