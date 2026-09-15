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
//   3. 0000..7FFF read straight, which is banks 0 and 1 on every cartridge,
//      mapper or not, and is emitted. The CRC32 of bank 0 is kept.
//   4. Banks 2, 4, 8 and 16 read through slot 2 (FFFF=bank, 8000..BFFF),
//      not emitted, each compared by CRC32 with bank 0. The first match is
//      the mirror: a cartridge with fewer bank bits repeats from there, and
//      a cartridge with no mapper at all repeats bank 0 at bank 2. No match
//      means 32 banks, the largest Sega mapper image and the most the
//      whitelist lets FFFF select.
//   5. Banks 2 up to the size read through slot 2 and emitted.
// The header's size code is reported but not believed: Game Gear headers
// were never checked by a BIOS and many carry the wrong code (Sonic 2 says
// 256 KB and is 512). The size does matter: system.vhd recognises EEPROM
// cartridges by the CRC32 of the whole image, so a mirrored read of World
// Series Baseball is not World Series Baseball to it.
// The CRC32 of the stream comes out for the menu, to compare with the SD
// image's. At 2 us a byte a 512 KB cartridge takes about 1.2 s with the
// probes.
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
    output reg  [31:0] crc32,
    output reg  [3:0]  state
);

// Reflected IEEE CRC32, the zlib convention, as pocket-cartridge's dump does.
function [31:0] crc_byte(input [31:0] c_in, input [7:0] d);
    reg [31:0] c;
    integer k;
    begin
        c = c_in ^ {24'd0, d};
        for (k = 0; k < 8; k = k + 1)
            c = (c >> 1) ^ (32'hEDB88320 & {32{c[0]}});
        crc_byte = c;
    end
endfunction

localparam [3:0] ST_IDLE = 4'd0, ST_INIT_REQ = 4'd1, ST_INIT_WAIT = 4'd2,
                 ST_HDR_REQ = 4'd3, ST_HDR_WAIT = 4'd4, ST_HDR_JUDGE = 4'd5,
                 ST_BANK_REQ = 4'd6, ST_BANK_WAIT = 4'd7,
                 ST_READ_REQ = 4'd8, ST_READ_WAIT = 4'd9, ST_NEXT = 4'd10,
                 ST_DONE = 4'd11;
localparam [1:0] PH_LINEAR = 2'd0, PH_PROBE = 2'd1, PH_EMIT = 2'd2;

reg [1:0]  phase;
reg [1:0]  init_index;
reg [1:0]  candidate;      // 0: 7FF0  1: 3FF0  2: 1FF0
reg [3:0]  idx;
reg [7:0]  hdr [0:15];
reg [5:0]  bank;           // the slot 2 bank, or the probe bank
reg [5:0]  bank_count;
reg [15:0] offset;         // within the bank, or the linear address
reg [31:0] crc_reg;        // the whole stream
reg [31:0] crc_bank0;      // bank 0 alone, finished
reg [31:0] crc_probe;      // the bank under probe

function [15:0] header_base(input [1:0] c);
    header_base = c == 2'd0 ? 16'h7FF0 : c == 2'd1 ? 16'h3FF0 : 16'h1FF0;
endfunction

// TMR SEGA
wire signature = hdr[0] == 8'h54 && hdr[1] == 8'h4D && hdr[2] == 8'h52 && hdr[3] == 8'h20 &&
                 hdr[4] == 8'h53 && hdr[5] == 8'h45 && hdr[6] == 8'h47 && hdr[7] == 8'h41;

wire last_in_bank = offset[13:0] == 14'h3FFF;

always @(posedge clk) begin
    out_wr  <= 1'b0;
    bus_req <= 1'b0;
    if (reset) begin
        state      <= ST_IDLE;
        phase      <= PH_LINEAR;
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
        crc32      <= 32'd0;
        crc_reg    <= 32'hFFFFFFFF;
        crc_bank0  <= 32'd0;
        crc_probe  <= 32'hFFFFFFFF;
        init_index <= 2'd0;
        candidate  <= 2'd0;
        idx        <= 4'd0;
        bank       <= 6'd0;
        bank_count <= 6'd0;
        offset     <= 16'd0;
    end else begin
        case (state)
            ST_IDLE: if (start) begin
                busy       <= 1'b1;
                done       <= 1'b0;
                header_ok  <= 1'b0;
                crc_reg    <= 32'hFFFFFFFF;
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
                    header_ok <= 1'b1;
                    size_code <= hdr[15][3:0];
                end
                if (signature || candidate == 2'd2) begin
                    phase      <= PH_LINEAR;
                    crc_bank0  <= 32'hFFFFFFFF;
                    size_bytes <= 32'h00080000;
                    bank_count <= 6'd32;
                    bank       <= 6'd0;
                    offset     <= 16'd0;
                    state      <= ST_READ_REQ;
                end else begin
                    candidate <= candidate + 1'b1;
                    state     <= ST_HDR_REQ;
                end
            end

            // Slot 2 select, for a probe or an emitted bank.
            ST_BANK_REQ: if (!bus_busy) begin
                bus_req   <= 1'b1;
                bus_wr    <= 1'b1;
                bus_addr  <= 16'hFFFF;
                bus_wdata <= {2'd0, bank};
                offset    <= 16'd0;
                crc_probe <= 32'hFFFFFFFF;
                state     <= ST_BANK_WAIT;
            end
            ST_BANK_WAIT: if (bus_done) state <= ST_READ_REQ;

            ST_READ_REQ: if (!bus_busy) begin
                bus_req  <= 1'b1;
                bus_wr   <= 1'b0;
                bus_addr <= phase == PH_LINEAR ? offset : {2'b10, offset[13:0]};
                state    <= ST_READ_WAIT;
            end
            ST_READ_WAIT: if (bus_done) begin
                if (phase == PH_PROBE) begin
                    crc_probe <= crc_byte(crc_probe, bus_rdata);
                end else begin
                    out_wr   <= 1'b1;
                    out_data <= bus_rdata;
                    out_addr <= phase == PH_LINEAR ? {9'd0, offset} : {5'd0, bank, offset[13:0]};
                    crc_reg  <= crc_byte(crc_reg, bus_rdata);
                    if (phase == PH_LINEAR && offset < 16'h4000)
                        crc_bank0 <= crc_byte(crc_bank0, bus_rdata);
                end
                state <= ST_NEXT;
            end
            ST_NEXT: begin
                case (phase)
                    PH_LINEAR: begin
                        if (offset != 16'h7FFF) begin
                            offset <= offset + 1'b1;
                            state  <= ST_READ_REQ;
                        end else begin
                            phase <= PH_PROBE;
                            bank  <= 6'd2;
                            state <= ST_BANK_REQ;
                        end
                    end
                    PH_PROBE: begin
                        if (!last_in_bank) begin
                            offset <= offset + 1'b1;
                            state  <= ST_READ_REQ;
                        end else if (crc_probe == crc_bank0) begin
                            // This bank repeats bank 0: the cartridge ends here.
                            bank_count <= bank;
                            size_bytes <= {12'd0, bank, 14'd0};
                            if (bank == 6'd2) state <= ST_DONE;
                            else begin
                                phase <= PH_EMIT;
                                bank  <= 6'd2;
                                state <= ST_BANK_REQ;
                            end
                        end else if (bank != 6'd16) begin
                            bank  <= {bank[4:0], 1'b0};      // 2, 4, 8, 16
                            state <= ST_BANK_REQ;
                        end else begin
                            phase <= PH_EMIT;
                            bank  <= 6'd2;
                            state <= ST_BANK_REQ;
                        end
                    end
                    default: begin   // PH_EMIT
                        if (!last_in_bank) begin
                            offset <= offset + 1'b1;
                            state  <= ST_READ_REQ;
                        end else if (bank + 6'd1 == bank_count) state <= ST_DONE;
                        else begin
                            bank  <= bank + 1'b1;
                            state <= ST_BANK_REQ;
                        end
                    end
                endcase
            end

            ST_DONE: begin
                busy  <= 1'b0;
                done  <= 1'b1;
                crc32 <= ~crc_reg;
            end
            default: state <= ST_IDLE;
        endcase
    end
end

endmodule
`default_nettype wire
