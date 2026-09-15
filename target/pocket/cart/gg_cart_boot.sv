// SPDX-License-Identifier: GPL-3.0-or-later
`default_nettype none

// Read a Game Gear cartridge through the official adapter into the ROM
// stream, once, at boot. The core then runs it exactly as it runs an SD
// image: the cartridge's own mapper is used only to get the bytes out, and
// system.vhd's mapper, EEPROM and RAM emulation take over from there. That
// keeps the Z80 off the connector, where a 3.58 MHz memory cycle through two
// level translators and an adapter would be its own project.
//
// Sequence, all through gg_cart_bus and its write whitelist:
//   1. Sega mapper to its reset state: FFFC=00 (RAM and EEPROM off), FFFD=00,
//      FFFE=01, FFFF=02.
//   2. The 16-byte header at 7FF0, then 3FF0, then 1FF0, until one starts
//      with "TMR SEGA". Its last byte's low nibble is the size code.
//   3. Up to 48 KB: a linear read of 0000 up to the size. Larger: for every
//      16 KB bank, FFFF=bank and a read of 8000..BFFF, bank 0 included, so
//      the fixed first kilobyte of slot 0 is never trusted.
// No header means 512 KB through the mapper, the largest Sega mapper image.
// A size code above 512 KB is capped there: the whitelist allows FFFF<=1F.
//
// out_wr/out_addr/out_data have the shape of an APF data_loader's output, so
// core_top.v merges them into the cartridge slot's stream. At 2 us a byte a
// 512 KB cartridge takes about a second.
module gg_cart_boot (
    input  wire        clk,
    input  wire        reset,       // high: no cartridge session, everything idle
    input  wire        start,       // one pulse per session

    output reg         bus_req,
    output reg         bus_wr,
    output reg  [15:0] bus_addr,
    output reg  [7:0]  bus_wdata,
    input  wire [7:0]  bus_rdata,
    input  wire        bus_done,
    input  wire        bus_busy,

    output reg         out_wr,
    output reg  [24:0] out_addr,
    output reg  [7:0]  out_data,

    output reg         busy,
    output reg         done,        // held from the last byte until reset
    output reg         header_ok,
    output reg  [3:0]  size_code,
    output reg  [31:0] size_bytes,
    output reg  [3:0]  state
);

localparam [3:0] ST_IDLE = 4'd0, ST_INIT_REQ = 4'd1, ST_INIT_WAIT = 4'd2,
                 ST_HDR_REQ = 4'd3, ST_HDR_WAIT = 4'd4, ST_HDR_JUDGE = 4'd5,
                 ST_BANK_REQ = 4'd6, ST_BANK_WAIT = 4'd7,
                 ST_READ_REQ = 4'd8, ST_READ_WAIT = 4'd9, ST_NEXT = 4'd10,
                 ST_DONE = 4'd11;

reg [1:0]  init_index;
reg [1:0]  candidate;      // 0: 7FF0  1: 3FF0  2: 1FF0
reg [3:0]  idx;
reg [7:0]  hdr [0:15];
reg        banked;
reg [4:0]  bank;
reg [5:0]  bank_count;
reg [15:0] offset;         // within the bank, or the linear address

function [15:0] header_base(input [1:0] c);
    header_base = c == 2'd0 ? 16'h7FF0 : c == 2'd1 ? 16'h3FF0 : 16'h1FF0;
endfunction

// TMR SEGA
wire signature = hdr[0] == 8'h54 && hdr[1] == 8'h4D && hdr[2] == 8'h52 && hdr[3] == 8'h20 &&
                 hdr[4] == 8'h53 && hdr[5] == 8'h45 && hdr[6] == 8'h47 && hdr[7] == 8'h41;

function [31:0] code_bytes(input [3:0] c);
    case (c)
        4'hA:    code_bytes = 32'h00002000;
        4'hB:    code_bytes = 32'h00004000;
        4'hC:    code_bytes = 32'h00008000;
        4'hD:    code_bytes = 32'h0000C000;
        4'hE:    code_bytes = 32'h00010000;
        4'hF:    code_bytes = 32'h00020000;
        4'h0:    code_bytes = 32'h00040000;
        default: code_bytes = 32'h00080000;   // 1: 512 KB; 2 and unknown: capped
    endcase
endfunction

integer i;
always @(posedge clk) begin
    out_wr  <= 1'b0;
    bus_req <= 1'b0;
    if (reset) begin
        state      <= ST_IDLE;
        busy       <= 1'b0;
        done       <= 1'b0;
        header_ok  <= 1'b0;
        size_code  <= 4'd0;
        size_bytes <= 32'd0;
        bus_wr     <= 1'b0;
        bus_addr   <= 16'd0;
        bus_wdata  <= 8'd0;
        out_addr   <= 25'd0;
        out_data   <= 8'd0;
        init_index <= 2'd0;
        candidate  <= 2'd0;
        idx        <= 4'd0;
        banked     <= 1'b0;
        bank       <= 5'd0;
        bank_count <= 6'd0;
        offset     <= 16'd0;
    end else begin
        case (state)
            ST_IDLE: if (start) begin
                busy       <= 1'b1;
                done       <= 1'b0;
                header_ok  <= 1'b0;
                init_index <= 2'd0;
                candidate  <= 2'd0;
                idx        <= 4'd0;
                state      <= ST_INIT_REQ;
            end

            ST_INIT_REQ: if (!bus_busy) begin
                bus_req   <= 1'b1;
                bus_wr    <= 1'b1;
                bus_addr  <= 16'hFFFC + {14'd0, init_index};
                bus_wdata <= init_index == 2'd2 ? 8'h01 : init_index == 2'd3 ? 8'h02 : 8'h00;
                state     <= ST_INIT_WAIT;
            end
            ST_INIT_WAIT: if (bus_done) begin
                if (init_index == 2'd3) state <= ST_HDR_REQ;
                else begin
                    init_index <= init_index + 1'b1;
                    state      <= ST_INIT_REQ;
                end
            end

            ST_HDR_REQ: if (!bus_busy) begin
                bus_req  <= 1'b1;
                bus_wr   <= 1'b0;
                bus_addr <= header_base(candidate) + {12'd0, idx};
                state    <= ST_HDR_WAIT;
            end
            ST_HDR_WAIT: if (bus_done) begin
                hdr[idx] <= bus_rdata;
                if (idx != 4'd15) begin
                    idx   <= idx + 1'b1;
                    state <= ST_HDR_REQ;
                end else begin
                    idx   <= 4'd0;
                    state <= ST_HDR_JUDGE;
                end
            end
            ST_HDR_JUDGE: begin
                if (signature) begin
                    header_ok  <= 1'b1;
                    size_code  <= hdr[15][3:0];
                    size_bytes <= code_bytes(hdr[15][3:0]);
                    banked     <= code_bytes(hdr[15][3:0]) > 32'h0000C000;
                    bank_count <= code_bytes(hdr[15][3:0]) >> 14;
                    bank       <= 5'd0;
                    offset     <= 16'd0;
                    state      <= code_bytes(hdr[15][3:0]) > 32'h0000C000 ? ST_BANK_REQ : ST_READ_REQ;
                end else if (candidate != 2'd2) begin
                    candidate <= candidate + 1'b1;
                    state     <= ST_HDR_REQ;
                end else begin
                    header_ok  <= 1'b0;
                    size_code  <= 4'd1;
                    size_bytes <= 32'h00080000;
                    banked     <= 1'b1;
                    bank_count <= 6'd32;
                    bank       <= 5'd0;
                    offset     <= 16'd0;
                    state      <= ST_BANK_REQ;
                end
            end

            ST_BANK_REQ: if (!bus_busy) begin
                bus_req   <= 1'b1;
                bus_wr    <= 1'b1;
                bus_addr  <= 16'hFFFF;
                bus_wdata <= {3'd0, bank};
                state     <= ST_BANK_WAIT;
            end
            ST_BANK_WAIT: if (bus_done) state <= ST_READ_REQ;

            ST_READ_REQ: if (!bus_busy) begin
                bus_req  <= 1'b1;
                bus_wr   <= 1'b0;
                bus_addr <= banked ? {2'b10, offset[13:0]} : offset;
                state    <= ST_READ_WAIT;
            end
            ST_READ_WAIT: if (bus_done) begin
                out_wr   <= 1'b1;
                out_data <= bus_rdata;
                out_addr <= banked ? {6'd0, bank, offset[13:0]} : {9'd0, offset};
                state    <= ST_NEXT;
            end
            ST_NEXT: begin
                if (banked) begin
                    if (offset[13:0] != 14'h3FFF) begin
                        offset <= offset + 1'b1;
                        state  <= ST_READ_REQ;
                    end else begin
                        offset <= 16'd0;
                        if ({1'b0, bank} + 6'd1 == bank_count) state <= ST_DONE;
                        else begin
                            bank  <= bank + 1'b1;
                            state <= ST_BANK_REQ;
                        end
                    end
                end else begin
                    if ({16'd0, offset} + 32'd1 == size_bytes) state <= ST_DONE;
                    else begin
                        offset <= offset + 1'b1;
                        state  <= ST_READ_REQ;
                    end
                end
            end

            ST_DONE: begin
                busy <= 1'b0;
                done <= 1'b1;
            end
            default: state <= ST_IDLE;
        endcase
    end
end

endmodule
`default_nettype wire
