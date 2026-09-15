//
// savestate_apf.sv -- APF savestates on top of MiSTer's savestates.sv.
//
// Copyright (c) 2026 kroy
//
// This source file is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 2 of the License, or (at your option)
// any later version.
//
// Upstream's engine writes a state as 64-bit words over the DDRAM bus MiSTer's
// sys/ddram.sv provides. The Pocket has no DDRAM, so this module is the far
// side of that bus: a 64 KB block RAM that answers every transaction the
// engine makes, and that the APF host reads and writes through the
// 0x4xxxxxxx bridge window as 32-bit words. Between the two sits the
// start/load handshake core_bridge_cmd.v expects.
//
// The engine's protocol, read out of savestates.sv: ADDR is a 64-bit word
// address, BURSTCNT is always 1, WE and RD are one-cycle strobes, BUSY is
// back-pressure the engine honours on every transaction, and after RD it
// waits for DOUT_READY and consumes DOUT the cycle after latching it. A word
// address is the slot base 0x07C00000 plus an offset below 0x2000, so the low
// thirteen bits index the buffer.
//
// The engine has no busy, ok or err outputs. What it has is ss_freeze, high
// for the whole transaction, a header word at offset 0 written last on a
// save, and the z80_set strobe a load ends with. So: hold the request until
// ss_freeze rises, then wait for it to fall, and report ok when the header
// was written (save) or the Z80 was restored (load), err otherwise.
//
// The bridge window is read the way the APF host reads it: the address
// free-runs, the host samples bridge_rd_data a few clocks after presenting
// the address, so the data here comes straight out of the RAM two clocks
// after bridge_addr with no strobe in the path.
//

`default_nettype none

module savestate_apf (
    input  wire        clk_74a,
    input  wire        clk_sys,
    input  wire        reset_n,               // clk_sys

    // ---- APF handshake, clk_74a --------------------------------------------
    input  wire        savestate_start,
    output wire        savestate_start_ack,
    output wire        savestate_start_busy,
    output wire        savestate_start_ok,
    output wire        savestate_start_err,
    input  wire        savestate_load,
    output wire        savestate_load_ack,
    output wire        savestate_load_busy,
    output wire        savestate_load_ok,
    output wire        savestate_load_err,

    // ---- bridge window 0x4xxxxxxx, clk_74a --------------------------------
    input  wire        bridge_wr,
    input  wire        bridge_endian_little,
    input  wire [31:0] bridge_addr,
    input  wire [31:0] bridge_wr_data,
    output reg  [31:0] bridge_rd_data,

    // ---- the engine, clk_sys ---------------------------------------------
    output reg         ss_save,
    output reg         ss_load,
    input  wire        ss_freeze,
    input  wire        ss_restored,           // z80_set: a load reached the end

    input  wire [28:0] ddram_addr,
    input  wire [63:0] ddram_din,
    input  wire        ddram_we,
    input  wire        ddram_rd,
    output reg  [63:0] ddram_dout,
    output reg         ddram_dout_ready,
    output wire        ddram_busy
);

// ---------------------------------------------------------------------------
// The buffer: two 32-bit halves so that the engine's port is 64 bits wide
// and the bridge's is 32, with no mixed-width megafunction. Port A is the
// engine's, port B the bridge's.
// ---------------------------------------------------------------------------
wire [12:0] a_addr = ddram_addr[12:0];
wire [31:0] a_q_lo, a_q_hi;

wire [12:0] b_addr = bridge_addr[15:3];
wire        b_hi   = bridge_addr[2];
wire        b_sel  = bridge_addr[31:28] == 4'h4;
wire [31:0] b_din  = bridge_endian_little ? bridge_wr_data :
                     {bridge_wr_data[7:0], bridge_wr_data[15:8],
                      bridge_wr_data[23:16], bridge_wr_data[31:24]};
wire [31:0] b_q_lo, b_q_hi;

dpram #(.widthad_a(13), .width_a(32)) buf_lo (
    .clock_a  (clk_sys),
    .address_a(a_addr),
    .wren_a   (ddram_we),
    .data_a   (ddram_din[31:0]),
    .q_a      (a_q_lo),
    .clock_b  (clk_74a),
    .address_b(b_addr),
    .wren_b   (bridge_wr & b_sel & ~b_hi),
    .data_b   (b_din),
    .q_b      (b_q_lo)
);

dpram #(.widthad_a(13), .width_a(32)) buf_hi (
    .clock_a  (clk_sys),
    .address_a(a_addr),
    .wren_a   (ddram_we),
    .data_a   (ddram_din[63:32]),
    .q_a      (a_q_hi),
    .clock_b  (clk_74a),
    .address_b(b_addr),
    .wren_b   (bridge_wr & b_sel & b_hi),
    .data_b   (b_din),
    .q_b      (b_q_hi)
);

// ---------------------------------------------------------------------------
// The engine's side of the bus. The RAM presents q the clock after the
// address, so a read is answered two clocks after RD. Nothing here ever
// needs to refuse a transaction.
// ---------------------------------------------------------------------------
assign ddram_busy = 1'b0;

reg rd_d = 0;
always @(posedge clk_sys) begin
    rd_d             <= ddram_rd;
    ddram_dout_ready <= rd_d;
    if (rd_d) ddram_dout <= {a_q_hi, a_q_lo};
end

// ---------------------------------------------------------------------------
// The bridge's side. Reads: address in, word out two clocks later, byte
// order as the host asked for it, the same convention data_unloader.sv
// uses. Writes went in above.
// ---------------------------------------------------------------------------
reg b_hi_d = 0;
always @(posedge clk_74a) begin
    b_hi_d <= b_hi;
    bridge_rd_data <= bridge_endian_little
        ? (b_hi_d ? b_q_hi : b_q_lo)
        : (b_hi_d ? {b_q_hi[7:0], b_q_hi[15:8], b_q_hi[23:16], b_q_hi[31:24]}
                  : {b_q_lo[7:0], b_q_lo[15:8], b_q_lo[23:16], b_q_lo[31:24]});
end

// ---------------------------------------------------------------------------
// The handshake, run in clk_sys next to the engine and synchronised both
// ways. Ack is held for as long as the host holds its request: the bridge
// command machine stalls until it sees ack and drops the request on its way
// back to idle, so a level, not a pulse, is what survives the crossing.
// ---------------------------------------------------------------------------
wire start_s, load_s;
synch_3 s_start (savestate_start, start_s, clk_sys);
synch_3 s_load  (savestate_load,  load_s,  clk_sys);

reg start_d = 0, load_d = 0;
wire start_rise = start_s & ~start_d;
wire load_rise  = load_s  & ~load_d;

reg s_ack = 0, s_busy = 0, s_ok = 0, s_err = 0;
reg l_ack = 0, l_busy = 0, l_ok = 0, l_err = 0;

wire [7:0] reply_s;
synch_3 #(.WIDTH(8)) s_reply ({s_ack, s_busy, s_ok, s_err, l_ack, l_busy, l_ok, l_err},
                              reply_s, clk_74a);
assign {savestate_start_ack, savestate_start_busy, savestate_start_ok, savestate_start_err,
        savestate_load_ack,  savestate_load_busy,  savestate_load_ok,  savestate_load_err} = reply_s;

// A request the engine will not take (it sits out a 500 ms cooldown after
// each operation, and a reset) has to end somewhere: five seconds, then err.
localparam [27:0] ARM_LIMIT = 28'd268435455;

localparam [2:0] IDLE   = 3'd0,
                 S_ARM  = 3'd1,   // asked to save, waiting for the freeze
                 S_RUN  = 3'd2,   // frozen, the engine is writing
                 L_ARM  = 3'd3,
                 L_RUN  = 3'd4;
reg  [2:0] state = IDLE;
reg [27:0] arm_count = 0;
reg        header_seen = 0;       // word 0 written during this save
reg        restored_seen = 0;     // z80_set pulsed during this load

// Word 0 is the header and the engine writes it last, so its arrival is
// the save completing. The slot base has zeros in these bits.
wire header_wr = ddram_we & (ddram_addr[12:0] == 13'd0);

always @(posedge clk_sys) begin
    start_d <= start_s;
    load_d  <= load_s;

    // Ack follows the host's request line down.
    if (~start_s) s_ack <= 0;
    if (~load_s)  l_ack <= 0;

    if (header_wr)   header_seen   <= 1;
    if (ss_restored) restored_seen <= 1;

    if (!reset_n) begin
        state   <= IDLE;
        ss_save <= 0;
        ss_load <= 0;
        s_busy  <= 0; s_ok <= 0; s_err <= 0;
        l_busy  <= 0; l_ok <= 0; l_err <= 0;
    end else case (state)
        IDLE: begin
            if (start_rise) begin
                s_ack <= 1; s_busy <= 1; s_ok <= 0; s_err <= 0;
                header_seen <= 0;
                ss_save   <= 1;
                arm_count <= 0;
                state     <= S_ARM;
            end else if (load_rise) begin
                l_ack <= 1; l_busy <= 1; l_ok <= 0; l_err <= 0;
                restored_seen <= 0;
                ss_load   <= 1;
                arm_count <= 0;
                state     <= L_ARM;
            end
        end

        S_ARM: begin
            arm_count <= arm_count + 1'd1;
            if (ss_freeze) begin
                ss_save <= 0;
                state   <= S_RUN;
            end else if (arm_count == ARM_LIMIT) begin
                ss_save <= 0;
                s_busy  <= 0; s_err <= 1;
                state   <= IDLE;
            end
        end

        S_RUN: if (~ss_freeze) begin
            s_busy <= 0;
            s_ok   <= header_seen;
            s_err  <= ~header_seen;
            state  <= IDLE;
        end

        L_ARM: begin
            arm_count <= arm_count + 1'd1;
            if (ss_freeze) begin
                ss_load <= 0;
                state   <= L_RUN;
            end else if (arm_count == ARM_LIMIT) begin
                ss_load <= 0;
                l_busy  <= 0; l_err <= 1;
                state   <= IDLE;
            end
        end

        L_RUN: if (~ss_freeze) begin
            l_busy <= 0;
            l_ok   <= restored_seen;
            l_err  <= ~restored_seen;
            state  <= IDLE;
        end

        default: state <= IDLE;
    endcase
end

endmodule

`default_nettype wire
