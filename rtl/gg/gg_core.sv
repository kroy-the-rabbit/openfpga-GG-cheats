//
// gg_core.sv -- the Game Gear machine, wired for the Analogue Pocket.
//
// Copyright (c) 2026 kroy
//
// This file is the Pocket equivalent of MiSTer's SMS.sv: it holds the clock
// enable divider, the ROM store, the work and backup RAMs and the video timing
// generator around `system`, and presents them to core_top in flat terms.
// The machine itself is rtl/upstream/, unedited (docs/PROVENANCE.md).
//
// Everything here that is not Pocket glue is derived from SMS.sv in
// MiSTer-devel/SMS_MiSTer at 1fc3c121, Copyright (c) 2017 Sorgelig, itself a
// port of Ben's Sega Master System for the Papilio. The clock enable divider,
// the cart mask accumulator, the SDRAM write handshake and the work RAM clear
// are that file's, kept line for line so a future upstream sync is a diff.
//
// This source file is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 2 of the License, or (at your option)
// any later version.
//
// Game Gear only, for now. Master System and SG-1000 come out of the same
// `system` and are a scope decision, not a technical one: see docs/PLAN.md.
// The features a Game Gear does not have are tied off rather than cut out of
// `system`, so that rtl/upstream/ stays byte for byte MiSTer's and Quartus
// prunes what the constants make unreachable.
//

`default_nettype none

module gg_core (
    input  wire        clk_sys,        // 53.693181 MHz
    input  wire        pll_locked,

    input  wire        reset,          // active high, synchronous to clk_sys

    // ---- ROM in, from the APF cartridge slot, clk_sys domain --------------
    input  wire        cart_download,  // high for the whole transfer
    input  wire        ioctl_wr,
    input  wire [24:0] ioctl_addr,
    input  wire  [7:0] ioctl_dout,

    // ---- controls, active high, MiSTer bit order --------------------------
    // [0] right [1] left [2] down [3] up [4] button 1 [5] button 2 [6] start
    input  wire  [6:0] joy1,

    // ---- settings ---------------------------------------------------------
    input  wire        ggres,          // 1 = the 160x144 Game Gear window
    input  wire        region_jp,      // 0 = export, 1 = Japan
    input  wire        sp64,           // lift the 8-sprites-per-line limit

    // ---- video, clk_sys domain --------------------------------------------
    output wire        ce_pix,
    output wire [11:0] color,          // {B,G,R} 4 bits each, as the VDP has it
    output wire        hsync,
    output wire        vsync,
    output wire        hblank,
    output wire        vblank,

    // ---- audio ------------------------------------------------------------
    output wire signed [15:0] audio_l,
    output wire signed [15:0] audio_r,

    // ---- cheats, P2 -------------------------------------------------------
    // One master switch feeds both mechanisms. The Game Genie word is shifted
    // in by core_top's loader, bit 128 clocking each code into `system`'s
    // GAMEGENIE; the Pro Action Replay table is written entry by entry and
    // `poke_code_total` is what makes an entry live.
    input  wire        cheats_en,
    input  wire [128:0] gg_code,
    input  wire        gg_code_reset,  // pulse before shifting a new set in
    output wire        gg_avail,

    input  wire        poke_code_wr,
    input  wire  [4:0] poke_code_index,
    input  wire [12:0] poke_code_addr,
    input  wire  [7:0] poke_code_data,
    input  wire  [5:0] poke_code_total,

    // ---- diagnostics ------------------------------------------------------
    output wire        rom_overrun,    // sticky: the ROM queue was overrun

    // ---- backup RAM, second port, driven by the save slot ------------------
    input  wire [14:0] bram_addr,
    input  wire  [7:0] bram_din,
    input  wire        bram_wr,
    output wire  [7:0] bram_dout,

    // ---- SDRAM ------------------------------------------------------------
    output wire [12:0] dram_a,
    output wire  [1:0] dram_ba,
    inout  wire [15:0] dram_dq,
    output wire  [1:0] dram_dqm,
    output wire        dram_clk,
    output wire        dram_cke,
    output wire        dram_ras_n,
    output wire        dram_cas_n,
    output wire        dram_we_n
);

// ---------------------------------------------------------------------------
// Clock enables. SMS.sv's divider, unchanged: clk_sys / 5, / 10 and / 15 give
// the VDP, pixel and Z80 rates. At 53.693181 MHz that is 10.738636 MHz VDP,
// 5.369318 MHz pixel and 3.579545 MHz CPU, which is NTSC Game Gear.
// ---------------------------------------------------------------------------
reg  [4:0] clkd = 0;
reg        ce_cpu = 0;
reg        ce_vdp = 0;
reg        ce_pix_r = 0;
reg        ce_sp = 0;

always @(negedge clk_sys) begin
    ce_sp    <= clkd[0];
    ce_vdp   <= 0; // div5
    ce_pix_r <= 0; // div10
    ce_cpu   <= 0; // div15
    clkd     <= clkd + 1'd1;
    if (clkd == 29) begin
        clkd     <= 0;
        ce_vdp   <= 1;
        ce_pix_r <= 1;
    end else if (clkd == 24) begin
        ce_cpu <= 1; // CPU phase as VDPTEST's HCounter test wants it
        ce_vdp <= 1;
    end else if (clkd == 19) begin
        ce_vdp   <= 1;
        ce_pix_r <= 1;
    end else if (clkd == 14) begin
        ce_vdp <= 1;
    end else if (clkd == 9) begin
        ce_cpu   <= 1;
        ce_vdp   <= 1;
        ce_pix_r <= 1;
    end else if (clkd == 4) begin
        ce_vdp <= 1;
    end
end

assign ce_pix = ce_pix_r;

// ---------------------------------------------------------------------------
// Reset. The work RAM is cleared on every reset before the Z80 is released,
// as SMS.sv does, so a game never reads the previous game's RAM.
// ---------------------------------------------------------------------------
wire raw_reset = reset | cart_download | rom_writing;

reg [13:0] ram_clr_addr;
reg        ram_clr_run = 1'b1;

always_ff @(posedge clk_sys) begin
    if (raw_reset) begin
        ram_clr_addr <= 0;
        ram_clr_run  <= 1'b1;
    end else if (ram_clr_run) begin
        ram_clr_addr <= ram_clr_addr + 1'd1;
        if (ram_clr_addr == 14'h3FFF) ram_clr_run <= 1'b0;
    end
end

wire reset_active = raw_reset | ram_clr_run | ~pll_locked;

// ---------------------------------------------------------------------------
// ROM in SDRAM.
//
// cart_mask is the OR of every address written, which for a power-of-two image
// is size-1 and for a headered dump is the next power of two minus one; the
// 512-byte header case is handled the way SMS.sv handles it, by offsetting the
// read rather than moving the image.
// ---------------------------------------------------------------------------
reg  [21:0] cart_mask;
reg  [21:0] cart_mask512;
reg         cart_sz512;

always @(posedge clk_sys) begin
    if (ioctl_wr & cart_download) begin
        cart_mask    <= cart_mask    | ioctl_addr[21:0];
        cart_mask512 <= cart_mask512 | (ioctl_addr[21:0] - 10'd512);
        if (!ioctl_addr)         cart_mask    <= 0;
        if (ioctl_addr == 512)   cart_mask512 <= 0;
    end
    if (old_download & ~cart_download) begin
        // A headered dump is N*1024 + 512 bytes, so the last byte address has
        // 10'h1FF in its low ten bits.
        cart_sz512 <= (ioctl_addr[9:0] == 10'h1FF);
    end
end

// The APF data loader has no backpressure: MiSTer throttles the ARM with
// ioctl_wait and there is no equivalent here, so the bytes have to be caught.
// APF delivers a 32-bit word about every 75 cycles of the 74.25 MHz bridge
// clock, which is four bytes in bursts at roughly 4 MB/s average; the writer
// below sustains one byte per eight clk_sys, which is 6.7 MB/s. It is the burst
// and not the average that overruns, so a short queue between them is enough.
localparam ROMQ_BITS = 6;   // 64 entries

reg  [32:0] romq [0:(1<<ROMQ_BITS)-1];
reg  [ROMQ_BITS-1:0] romq_wp = 0;
reg  [ROMQ_BITS-1:0] romq_rp = 0;
wire        romq_empty = (romq_wp == romq_rp);
wire [ROMQ_BITS-1:0] romq_wp_next = romq_wp + 1'd1;

// Sticky, and reported over the bridge. An overrun is silent corruption
// otherwise: the ROM simply has holes in it and the game fails oddly.
reg         rom_overrun_r = 0;

reg         old_download = 0;
always @(posedge clk_sys) old_download <= cart_download;
wire        download_start = ~old_download & cart_download;

always @(posedge clk_sys) begin
    if (download_start) begin
        romq_wp       <= 0;
        rom_overrun_r <= 0;
    end else if (ioctl_wr & cart_download) begin
        if (romq_wp_next == romq_rp) rom_overrun_r <= 1;
        else begin
            romq[romq_wp] <= {ioctl_addr[24:0], ioctl_dout};
            romq_wp       <= romq_wp_next;
        end
    end
end

assign rom_overrun = rom_overrun_r;

// SDRAM write handshake, SMS.sv's: we toggles per byte and the controller
// answers on we_ack. The address is presented a cycle before the toggle so the
// controller cannot sample it mid-update.
reg         rom_wr = 0;
reg  [24:0] romwr_a = 0;
reg   [7:0] romwr_d = 0;
reg   [1:0] wstate = 0;
wire        sd_wrack;

always @(posedge clk_sys) begin
    if (download_start) begin
        romq_rp <= 0;
        wstate  <= 0;
    end else begin
        case (wstate)
            2'd0: if (!romq_empty) begin
                      {romwr_a, romwr_d} <= romq[romq_rp];
                      romq_rp <= romq_rp + 1'd1;
                      wstate  <= 2'd1;
                  end
            2'd1: begin
                      rom_wr <= ~rom_wr;
                      wstate <= 2'd2;
                  end
            2'd2: if (rom_wr == sd_wrack) wstate <= 2'd0;
            default: wstate <= 2'd0;
        endcase
    end
end

wire rom_writing = (wstate != 2'd0) | ~romq_empty;

// The controller runs one transaction per rising edge of clkref. During play
// that is the CPU rate, which is one ROM read per Z80 cycle and all the machine
// can ask for. While the ROM is being written the Z80 is held in reset and
// nothing reads, so a free-running divide-by-eight is used instead: it is the
// fastest the eight-state controller can be driven. The mux only ever changes
// while the machine is in reset.
reg [2:0] dlclk_d = 0;
reg       dlclk = 0;
always @(posedge clk_sys) begin
    dlclk_d <= dlclk_d + 1'd1;
    dlclk   <= (dlclk_d == 3'd0);
end

wire clkref = (cart_download | rom_writing) ? dlclk : ce_cpu;

wire [21:0] rom_a;
wire        rom_rd;
wire  [7:0] rom_do;

wire [21:0] rom_a_masked = cart_sz512 ? ((rom_a + 22'd512) & cart_mask512)
                                      : (rom_a & cart_mask);

// rtl/upstream/sdram.sv is Sorgelig's controller for the MT48LC16M16 on the
// DE10-nano. The Pocket carries the same kind of part on the same kind of bus,
// so it is instantiated unedited; the board has no chip select pin, which is
// safe here because every command the controller issues except CMD_INHIBIT
// drives nCS low, and CMD_INHIBIT with the pin tied low is a NOP.
sdram ram (
    .init      (~pll_locked),
    .clk       (clk_sys),
    .clkref    (clkref),

    .waddr     (romwr_a),
    .din       (romwr_d),
    .we        (rom_wr),
    .we_ack    (sd_wrack),

    .raddr     ({3'b000, rom_a_masked}),
    .dout      (rom_do),
    .rd        (rom_rd),
    .rd_rdy    (),

    .SDRAM_DQ  (dram_dq),
    .SDRAM_A   (dram_a),
    .SDRAM_DQML(dram_dqm[0]),
    .SDRAM_DQMH(dram_dqm[1]),
    .SDRAM_BA  (dram_ba),
    .SDRAM_nCS (),
    .SDRAM_nWE (dram_we_n),
    .SDRAM_nRAS(dram_ras_n),
    .SDRAM_nCAS(dram_cas_n),
    .SDRAM_CKE (dram_cke)
);

// The SDRAM clock leaves through a DDR output register rather than a wire, so
// the pin sees the clock with the IO cell's delay and not the core's routing.
pin_ddio_clk sdram_clk_out (
    .datain_h(1'b0),
    .datain_l(1'b1),
    .outclock(clk_sys),
    .dataout (dram_clk)
);

// ---------------------------------------------------------------------------
// Video timing. `system` paints a colour for the x,y it is handed; `video`
// generates them. With gg and ggres set the active window is x 48..207 and
// y 24..167, which is 160x144.
// ---------------------------------------------------------------------------
wire [8:0] x, y;
wire [7:0] vcounter_cpu;
wire       mask_column;
wire       smode_M1, smode_M2, smode_M3, smode_M4;

video video_inst (
    .clk            (clk_sys),
    .ce_pix         (ce_pix_r),
    .pal            (1'b0),
    .ggres          (ggres),
    .border         (1'b0),
    .mask_column    (mask_column),
    .cut_mask       (1'b0),
    .smode_M1       (smode_M1),
    .smode_M2       (smode_M2),
    .smode_M3       (smode_M3),
    .smode_M4       (smode_M4),
    .video_state_out(),
    .video_state_in (22'd0),
    .video_state_set(1'b0),
    .x              (x),
    .y              (y),
    .vcounter_cpu   (vcounter_cpu),
    .hsync          (hsync),
    .vsync          (vsync),
    .hblank         (hblank),
    .vblank         (vblank)
);

// ---------------------------------------------------------------------------
// Work RAM and backup RAM.
// ---------------------------------------------------------------------------
wire [13:0] ram_a;
wire  [7:0] ram_d;
wire        ram_we;
wire  [7:0] ram_q;

// Port A is the Z80's. Port B carries the cold-reset clear and, once the
// machine is running, cheat_poker's once-a-frame writes; the clear owns the
// port while it runs and the poker stands down (`blocked`) rather than
// stalling. This was an spram with the clear muxed onto the one port until P2
// needed a second writer.
wire [12:0] poke_addr;
wire  [7:0] poke_data;
wire        poke_wr;

wire [13:0] ram_b_addr = ram_clr_run ? ram_clr_addr : {1'b0, poke_addr};
wire  [7:0] ram_b_data = ram_clr_run ? 8'h00       : poke_data;
wire        ram_b_wren = ram_clr_run | poke_wr;

dpram #(.widthad_a(14)) ram_inst (
    .clock_a  (clk_sys),
    .address_a({1'b0, ram_a[12:0]}),
    .wren_a   (ram_we),
    .data_a   (ram_d),
    .q_a      (ram_q),

    .clock_b  (clk_sys),
    .address_b(ram_b_addr),
    .wren_b   (ram_b_wren),
    .data_b   (ram_b_data),
    .q_b      ()
);

cheat_poker poker (
    .clk       (clk_sys),
    .reset     (reset_active),
    .enable    (cheats_en),
    .vblank    (vblank),
    .blocked   (ram_clr_run),

    .code_wr   (poke_code_wr),
    .code_index(poke_code_index),
    .code_addr (poke_code_addr),
    .code_data (poke_code_data),
    .code_total(poke_code_total),

    .poke_wr   (poke_wr),
    .poke_addr (poke_addr),
    .poke_data (poke_data)
);

// CODES clears its table on reset, so it fires on the first byte of a
// cartridge load, matching upstream's `ioctl_download & ioctl_wr & !addr`,
// and again whenever core_top is about to shift a new set of codes in.
wire gg_reset = (cart_download & ioctl_wr & ~|ioctl_addr) | gg_code_reset;

wire [14:0] nvram_a;
wire  [7:0] nvram_d;
wire        nvram_we;
wire  [7:0] nvram_q;

// Port B is the save slot's: core_top.v loads it in at boot and reads it back
// out when the core exits. Cart RAM and the 93C46 EEPROM share this one
// block (system.vhd muxes nvram_a between them), so one save slot covers
// both without this file caring which a cartridge uses. The init file is
// upstream's, which fills cart RAM with FF the way an unwritten chip reads.
dpram #(.widthad_a(15), .init_file("rtl/nvram_ff.mif")) nvram_inst (
    .clock_a  (clk_sys),
    .address_a(nvram_a),
    .wren_a   (nvram_we),
    .data_a   (nvram_d),
    .q_a      (nvram_q),
    .clock_b  (clk_sys),
    .address_b(bram_addr),
    .wren_b   (bram_wr),
    .data_b   (bram_din),
    .q_b      (bram_dout)
);

// ---------------------------------------------------------------------------
// Controls. `system` reads the pad active low, and on a Game Gear the Start
// button is the Pause line: it is read back through port $00 bit 7 rather than
// raising an interrupt.
// ---------------------------------------------------------------------------
wire [6:0] joy1_n = ~joy1;

// ---------------------------------------------------------------------------
// The machine.
//
// Everything a Game Gear does not have is a constant here. Quartus propagates
// them, so the System E second VDP and PSG, the MC8123 decryptor, the SG-1000
// and SC-3000 paths, the SK1100 keyboard, the paddle and pedal, the light gun
// and the YM2413 all fall out of the fitted design without rtl/upstream being
// touched. What that is worth is recorded in docs/BASELINE.md.
// ---------------------------------------------------------------------------
system #(63) system_inst (
    .clk_sys            (clk_sys),
    .ce_cpu             (ce_cpu),
    .ce_vdp             (ce_vdp),
    .ce_pix             (ce_pix_r),
    .ce_sp              (ce_sp),
    .turbo              (1'b0),

    .gg                 (1'b1),
    .ggres              (ggres),
    .systeme            (1'b0),

    .bios_en            (1'b0),
    .ext_bios_sel       (1'b0),
    .ext_bios_loaded    (1'b0),
    .gg_bios_en         (1'b0),
    .ext_gg_bios_loaded (1'b0),
    .GG_BIOSWEN         (1'b0),

    // The enable is active low inside `system`, so cheats_en is inverted
    // here: the read override leaves the CPU data path entirely when the
    // master switch is off.
    .GG_EN              (~cheats_en),
    .GG_CODE            (gg_code),
    .GG_RESET           (gg_reset),
    .GG_AVAIL           (gg_avail),

    .gg_link_en         (1'b0),
    .gg_link_in         (7'b1111111),
    .gg_link_out        (),

    .RESET_n            (~reset_active),

    .rom_rd             (rom_rd),
    .rom_a              (rom_a),
    .rom_do             (rom_do),

    .j1_up              (joy1_n[3]),
    .j1_down            (joy1_n[2]),
    .j1_left            (joy1_n[1]),
    .j1_right           (joy1_n[0]),
    .j1_tl              (joy1_n[4]),
    .j1_tr              (joy1_n[5]),
    .j1_th              (1'b1),
    .j1_start           (joy1_n[6]),
    .j1_coin            (1'b1),
    .j1_a3              (1'b1),

    .j2_up              (1'b1),
    .j2_down            (1'b1),
    .j2_left            (1'b1),
    .j2_right           (1'b1),
    .j2_tl              (1'b1),
    .j2_tr              (1'b1),
    .j2_th              (1'b1),
    .j2_start           (1'b1),
    .j2_coin            (1'b1),
    .j2_a3              (1'b1),

    .pause              (joy1_n[6]),
    .se_pause           (1'b0),
    .soft_reset         (1'b0),

    .j1_tr_out          (),
    .j1_th_out          (),
    .j2_tr_out          (),
    .j2_th_out          (),

    .E0Type             (2'b00),
    .E1Use              (1'b0),
    .E2Use              (1'b0),
    .E0                 (8'h00),
    .F2                 (8'h00),
    .F3                 (8'h00),

    .has_paddle         (1'b0),
    .has_pedal          (1'b0),
    .paddle             (8'h00),
    .paddle2            (8'h00),
    .pedal              (8'h00),
    .sc3000_en          (1'b0),
    .sc_multicart_en    (1'b0),
    .sc_megacart_en     (1'b0),
    .sc_cart_ram        (2'b00),
    .sk1100_en          (1'b0),
    .sk1100_row_sel     (),
    .sk1100_row_data    (12'hFFF),

    .x                  (x),
    .y                  (y),
    .vcounter_cpu       (vcounter_cpu),
    .color              (color),
    .palettemode        (1'b0),
    .mask_column        (mask_column),
    .black_column       (1'b0),
    .smode_M1           (smode_M1),
    .smode_M2           (smode_M2),
    .smode_M3           (smode_M3),
    .smode_M4           (smode_M4),
    .ysj_quirk          (1'b0),
    .pal                (1'b0),
    .region             (region_jp),

    .mapper_lock            (1'b0),
    .mapper_codies_force    (1'b0),
    .mapper_dahjee_a_force  (1'b0),
    .mapper_linear_force    (1'b0),
    .mapper_zemina_force    (1'b0),
    .mapper_eeprom_out      (),

    .vdp_enables        (2'b00),
    .psg_enables        (2'b00),

    .audioL             (audio_l),
    .audioR             (audio_r),
    .fm_ena             (1'b0),   // a Game Gear has no YM2413

    .dbr                (1'b1),   // a cartridge is present
    .sp64               (sp64),

    .ram_a              (ram_a),
    .ram_d              (ram_d),
    .ram_we             (ram_we),
    .ram_q              (ram_q),

    .nvram_a            (nvram_a),
    .nvram_d            (nvram_d),
    .nvram_we           (nvram_we),
    .nvram_q            (nvram_q),

    .encrypt            (2'b00),
    .key_a              (),
    .key_d              (8'h00),

    .ROMCL              (clk_sys),
    .ROMAD              (25'd0),
    .ROMDT              (8'h00),
    .ROMEN              (1'b0),
    .BIOSWEN            (1'b0),

    // Savestates are MiSTer's and are not carried: the Pocket has its own
    // mechanism through APF. Tied off rather than cut so system.vhd is
    // unedited; see docs/PLAN.md §9.4.
    .z80_reg_out        (),
    .z80_dir            (230'd0),
    .z80_set            (1'b0),
    .vdp_regs_out       (),
    .vdp_regs_in        (128'd0),
    .vdp_regs_set       (1'b0),
    .vdp_cram_out       (),
    .ss_cram_wr         (1'b0),
    .ss_cram_A          (5'd0),
    .ss_cram_D          (12'd0),
    .ss_vram_en         (1'b0),
    .ss_vram_A          (15'd0),
    .ss_vram_D          (),
    .ss_vram_WE         (1'b0),
    .ss_vram_WA         (15'd0),
    .ss_vram_WD         (8'd0),
    .psg_out            (),
    .psg_in             (56'd0),
    .psg_set            (1'b0),
    .mapper_out         (),
    .mapper_in          (64'd0),
    .mapper_set         (1'b0),
    .eeprom_ss_out      (),
    .eeprom_ss_in       (64'd0),
    .eeprom_ss_set      (1'b0),
    .z80_m1_n           (),
    .z80_mreq_n         (),
    .z80_iset           (),
    .vdp2_regs_out      (),
    .vdp2_regs_in       (128'd0),
    .vdp2_regs_set      (1'b0),
    .vdp2_cram_out      (),
    .ss_cram2_wr        (1'b0),
    .ss_cram2_A         (5'd0),
    .ss_cram2_D         (12'd0),
    .ss_vram2_en        (1'b0),
    .ss_vram2_A         (15'd0),
    .ss_vram2_D         (),
    .ss_vram2_WE        (1'b0),
    .ss_vram2_WA        (15'd0),
    .ss_vram2_WD        (8'd0),
    .psg2_out           (),
    .psg2_in            (56'd0),
    .psg2_set           (1'b0),
    .io_state_out       (),
    .io_state_in        (32'd0),
    .io_state_set       (1'b0),
    .ss_freeze          (1'b0)
);

endmodule

`default_nettype wire
