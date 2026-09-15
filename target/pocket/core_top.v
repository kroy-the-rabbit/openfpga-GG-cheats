//
// User core top-level for the Pocket Game Gear core.
//
// Instantiated by the real top-level, platform/pocket/apf_top.v, as `ic`.
//
// The APF port list, the pin tie-offs and the host command handler below are
// Analogue's openFPGA template as it reached this tree through
// pocket-pcengine/target/pocket/core_top.v. What is this core's is the bridge
// decode, the ROM slot, the controls, the video output stage and gg_core.
//
// Copyright (c) 2026 kroy
// Copyright (c) 2022 Analogue Enterprises Limited (the APF template)
//
// SPDX-License-Identifier: GPL-2.0-or-later
//

`default_nettype none

module core_top (

    //
    // physical connections
    //

    ///////////////////////////////////////////////////
    // clock inputs 74.25mhz. not phase aligned, so treat these domains as asynchronous

    input wire clk_74a,  // mainclk1
    input wire clk_74b,  // mainclk1 

    ///////////////////////////////////////////////////
    // cartridge interface
    // switches between 3.3v and 5v mechanically
    // output enable for multibit translators controlled by pic32

    // GBA AD[15:8]
    inout  wire [7:0] cart_tran_bank2,
    output wire       cart_tran_bank2_dir,

    // GBA AD[7:0]
    inout  wire [7:0] cart_tran_bank3,
    output wire       cart_tran_bank3_dir,

    // GBA A[23:16]
    inout  wire [7:0] cart_tran_bank1,
    output wire       cart_tran_bank1_dir,

    // GBA [7] PHI#
    // GBA [6] WR#
    // GBA [5] RD#
    // GBA [4] CS1#/CS#
    //     [3:0] unwired
    inout  wire [7:4] cart_tran_bank0,
    output wire       cart_tran_bank0_dir,

    // GBA CS2#/RES#
    inout  wire cart_tran_pin30,
    output wire cart_tran_pin30_dir,
    // when GBC cart is inserted, this signal when low or weak will pull GBC /RES low with a special circuit
    // the goal is that when unconfigured, the FPGA weak pullups won't interfere.
    // thus, if GBC cart is inserted, FPGA must drive this high in order to let the level translators
    // and general IO drive this pin.
    output wire cart_pin30_pwroff_reset,

    // GBA IRQ/DRQ
    inout  wire cart_tran_pin31,
    output wire cart_tran_pin31_dir,

    // infrared
    input  wire port_ir_rx,
    output wire port_ir_tx,
    output wire port_ir_rx_disable,

    // GBA link port
    inout  wire port_tran_si,
    output wire port_tran_si_dir,
    inout  wire port_tran_so,
    output wire port_tran_so_dir,
    inout  wire port_tran_sck,
    output wire port_tran_sck_dir,
    inout  wire port_tran_sd,
    output wire port_tran_sd_dir,

    ///////////////////////////////////////////////////
    // cellular psram 0 and 1, two chips (64mbit x2 dual die per chip)

    output wire [21:16] cram0_a,
    inout  wire [ 15:0] cram0_dq,
    input  wire         cram0_wait,
    output wire         cram0_clk,
    output wire         cram0_adv_n,
    output wire         cram0_cre,
    output wire         cram0_ce0_n,
    output wire         cram0_ce1_n,
    output wire         cram0_oe_n,
    output wire         cram0_we_n,
    output wire         cram0_ub_n,
    output wire         cram0_lb_n,

    output wire [21:16] cram1_a,
    inout  wire [ 15:0] cram1_dq,
    input  wire         cram1_wait,
    output wire         cram1_clk,
    output wire         cram1_adv_n,
    output wire         cram1_cre,
    output wire         cram1_ce0_n,
    output wire         cram1_ce1_n,
    output wire         cram1_oe_n,
    output wire         cram1_we_n,
    output wire         cram1_ub_n,
    output wire         cram1_lb_n,

    ///////////////////////////////////////////////////
    // sdram, 512mbit 16bit

    output wire [12:0] dram_a,
    output wire [ 1:0] dram_ba,
    inout  wire [15:0] dram_dq,
    output wire [ 1:0] dram_dqm,
    output wire        dram_clk,
    output wire        dram_cke,
    output wire        dram_ras_n,
    output wire        dram_cas_n,
    output wire        dram_we_n,

    ///////////////////////////////////////////////////
    // sram, 1mbit 16bit

    output wire [16:0] sram_a,
    inout  wire [15:0] sram_dq,
    output wire        sram_oe_n,
    output wire        sram_we_n,
    output wire        sram_ub_n,
    output wire        sram_lb_n,

    ///////////////////////////////////////////////////
    // vblank driven by dock for sync in a certain mode

    input wire vblank,

    ///////////////////////////////////////////////////
    // i/o to 6515D breakout usb uart

    output wire dbg_tx,
    input  wire dbg_rx,

    ///////////////////////////////////////////////////
    // i/o pads near jtag connector user can solder to

    output wire user1,
    input  wire user2,

    ///////////////////////////////////////////////////
    // RFU internal i2c bus 

    inout  wire aux_sda,
    output wire aux_scl,

    ///////////////////////////////////////////////////
    // RFU, do not use
    output wire vpll_feed,


    //
    // logical connections
    //

    ///////////////////////////////////////////////////
    // video, audio output to scaler
    output wire [23:0] video_rgb,
    output wire        video_rgb_clock,
    output wire        video_rgb_clock_90,
    output wire        video_de,
    output wire        video_skip,
    output wire        video_vs,
    output wire        video_hs,

    output wire audio_mclk,
    input  wire audio_adc,
    output wire audio_dac,
    output wire audio_lrck,

    ///////////////////////////////////////////////////
    // bridge bus connection
    // synchronous to clk_74a
    output wire        bridge_endian_little,
    input  wire [31:0] bridge_addr,
    input  wire        bridge_rd,
    output reg  [31:0] bridge_rd_data,
    input  wire        bridge_wr,
    input  wire [31:0] bridge_wr_data,

    ///////////////////////////////////////////////////
    // controller data
    // 
    // key bitmap:
    //   [0]    dpad_up
    //   [1]    dpad_down
    //   [2]    dpad_left
    //   [3]    dpad_right
    //   [4]    face_a
    //   [5]    face_b
    //   [6]    face_x
    //   [7]    face_y
    //   [8]    trig_l1
    //   [9]    trig_r1
    //   [10]   trig_l2
    //   [11]   trig_r2
    //   [12]   trig_l3
    //   [13]   trig_r3
    //   [14]   face_select
    //   [15]   face_start
    // joy values - unsigned
    //   [ 7: 0] lstick_x
    //   [15: 8] lstick_y
    //   [23:16] rstick_x
    //   [31:24] rstick_y
    // trigger values - unsigned
    //   [ 7: 0] ltrig
    //   [15: 8] rtrig
    //
    input wire [15:0] cont1_key,
    input wire [15:0] cont2_key,
    input wire [15:0] cont3_key,
    input wire [15:0] cont4_key,
    input wire [31:0] cont1_joy,
    input wire [31:0] cont2_joy,
    input wire [31:0] cont3_joy,
    input wire [31:0] cont4_joy,
    input wire [15:0] cont1_trig,
    input wire [15:0] cont2_trig,
    input wire [15:0] cont3_trig,
    input wire [15:0] cont4_trig

);

  // not using the IR port, so turn off both the LED, and
  // disable the receive circuit to save power
  assign port_ir_tx              = 0;
  assign port_ir_rx_disable      = 1;

  // bridge endianness
  assign bridge_endian_little    = 0;

  // The cartridge connector is cart_pins's, below.

  // link port is input only
  assign port_tran_so            = 1'bz;
  assign port_tran_so_dir        = 1'b0;  // SO is output only
  assign port_tran_si            = 1'bz;
  assign port_tran_si_dir        = 1'b0;  // SI is input only
  assign port_tran_sck           = 1'bz;
  assign port_tran_sck_dir       = 1'b0;  // clock direction can change
  assign port_tran_sd            = 1'bz;
  assign port_tran_sd_dir        = 1'b0;  // SD is input and not used

  // tie off the rest of the pins we are not using
  assign cram0_a                 = 'h0;
  assign cram0_dq                = {16{1'bZ}};
  assign cram0_clk               = 0;
  assign cram0_adv_n             = 1;
  assign cram0_cre               = 0;
  assign cram0_ce0_n             = 1;
  assign cram0_ce1_n             = 1;
  assign cram0_oe_n              = 1;
  assign cram0_we_n              = 1;
  assign cram0_ub_n              = 1;
  assign cram0_lb_n              = 1;

  assign cram1_a                 = 'h0;
  assign cram1_dq                = {16{1'bZ}};
  assign cram1_clk               = 0;
  assign cram1_adv_n             = 1;
  assign cram1_cre               = 0;
  assign cram1_ce0_n             = 1;
  assign cram1_ce1_n             = 1;
  assign cram1_oe_n              = 1;
  assign cram1_we_n              = 1;
  assign cram1_ub_n              = 1;
  assign cram1_lb_n              = 1;

  // assign dram_a                  = 'h0;
  // assign dram_ba                 = 'h0;
  // assign dram_dq                 = {16{1'bZ}};
  // assign dram_dqm                = 'h0;
  // assign dram_clk                = 'h0;
  // assign dram_cke                = 'h0;
  // assign dram_ras_n              = 'h1;
  // assign dram_cas_n              = 'h1;
  // assign dram_we_n               = 'h1;

  assign sram_a                  = 'h0;
  assign sram_dq                 = {16{1'bZ}};
  assign sram_oe_n               = 1;
  assign sram_we_n               = 1;
  assign sram_ub_n               = 1;
  assign sram_lb_n               = 1;

  assign dbg_tx                  = 1'bZ;
  assign user1                   = 1'bZ;
  assign aux_scl                 = 1'bZ;
  assign vpll_feed               = 1'bZ;


  // ==========================================================================
  // Bridge read mux
  // ==========================================================================
  always @(*) begin
    casex (bridge_addr)
      default: begin
        bridge_rd_data <= 0;
      end
      32'h2xxxxxxx: begin
        bridge_rd_data <= save_rd_data;
      end
      32'h4xxxxxxx: begin
        bridge_rd_data <= ss_rd_data;
      end
      32'hF0xxxxxx: begin
        bridge_rd_data <= settings_rd_data;
      end
      32'hF8xxxxxx: begin
        bridge_rd_data <= cmd_bridge_rd_data;
      end
    endcase
  end

  // ==========================================================================
  // Settings, written by interact.json, read back for the menu
  // ==========================================================================
  reg [31:0] reset_delay = 0;

  // The upstream "Extended" option that opens a Game Gear picture out to the
  // whole 256x192 field is not offered; the four scaler modes video.json
  // declares are the machines' own windows, chosen below by the slot word.
  reg region_jp = 0;  // 0 = export, 1 = Japan
  reg sp64 = 0;  // lift the 8-sprites-per-line limit

  // Cheats. Both start off and neither is persisted (interact.json declares
  // persist false), which is the contract every sibling holds: a cheat is
  // never on because it was on last time. Which cheats are on comes from the
  // file, not from here; this is only the master switch and the overlay.
  reg cheats_en = 0;
  // The overlay is P2 stage 2 and has no menu entry yet: interact.json does
  // not offer a switch that does nothing. The address is claimed here so the
  // one it eventually gets is the one this already answers.
  reg cheats_osd = 0;
  // YM2413, on by default as on MiSTer; a game still asks through port $F2.
  reg fm_en = 1;

  reg [31:0] settings_rd_data = 0;

  always @(posedge clk_74a) begin
    if (reset_delay > 0) begin
      reset_delay <= reset_delay - 1;
    end

    if (bridge_wr) begin
      casex (bridge_addr)
        32'hF0000000: begin
          reset_delay <= 32'h100000;
        end
        32'hF0000100: begin
          region_jp <= bridge_wr_data[0];
        end
        32'hF0000104: begin
          sp64 <= bridge_wr_data[0];
        end
        32'hF0000108: begin
          cheats_en <= bridge_wr_data[0];
        end
        32'hF000010C: begin
          cheats_osd <= bridge_wr_data[0];
        end
        32'hF0000110: begin
          fm_en <= bridge_wr_data[0];
        end
      endcase
    end

    if (bridge_rd) begin
      casex (bridge_addr)
        32'hF0000100: settings_rd_data <= {31'd0, region_jp};
        32'hF0000104: settings_rd_data <= {31'd0, sp64};
        32'hF0000108: settings_rd_data <= {31'd0, cheats_en};
        32'hF000010C: settings_rd_data <= {31'd0, cheats_osd};
        32'hF0000110: settings_rd_data <= {31'd0, fm_en};
        // Diagnostics. The Pocket menu is the only console this core has, so
        // the one thing that can go wrong silently is reported as a number:
        // a non-zero value here means bytes were dropped on the way into
        // SDRAM and the loaded ROM has holes in it.
        32'hF0000200: settings_rd_data <= {31'd0, rom_overrun_74};
        // Cheats, same idea: a file that loaded nothing and a file that never
        // arrived look identical on a handheld with no console. CC: is what
        // reached the Game Genie table, CD: cheats taken from a .cht or entries
        // declared by a .chtbin header, CB: bytes seen. CF: which reader
        // claimed the file, and CT: the first character and the length of the
        // first cheat's name, which is the only view of the title store until
        // the overlay exists.
        32'hF0000204: settings_rd_data <= {26'd0, cheat_count_74};
        32'hF0000208: settings_rd_data <= {26'd0, cheat_decl_74};
        32'hF000020C: settings_rd_data <= {12'd0, cheat_bytes_74};
        32'hF0000210: settings_rd_data <= {31'd0, cheat_overrun_74};
        32'hF0000214: settings_rd_data <= {31'd0, cheat_is_bin_74};
        32'hF0000218: settings_rd_data <= {20'd0, osd_codes_74, osd_titles_74};
        32'hF0000220: settings_rd_data <= cart_report_74;
        32'hF0000224: settings_rd_data <= cart_diag_74;
        32'hF0000228: settings_rd_data <= cart_crc_74;
        default: settings_rd_data <= 32'd0;
      endcase
    end
  end

  // ==========================================================================
  // Host/target command handler
  // ==========================================================================
  wire reset_n;  // driven by host commands, can be used as core-wide reset
  wire [31:0] cmd_bridge_rd_data;

  wire status_boot_done = pll_core_locked;
  wire status_setup_done = pll_core_locked;
  wire status_running = reset_n;

  wire dataslot_requestread;
  wire [15:0] dataslot_requestread_id;
  wire dataslot_requestread_ack = 1;
  wire dataslot_requestread_ok = 1;

  wire dataslot_requestwrite;
  wire [15:0] dataslot_requestwrite_id;
  wire dataslot_requestwrite_ack = 1;
  wire dataslot_requestwrite_ok = 1;

  wire dataslot_allcomplete;
  wire [31:0] cart_report_74;
  wire cart_report_valid_74;

  // Savestates: MiSTer's engine inside gg_core, the memory and the APF
  // handshake in savestate_apf. The window is the whole 64 KB buffer; the
  // state itself ends below 60 KB and the rest reads back as whatever the
  // block RAM held.
  wire savestate_supported = 1;
  wire [31:0] savestate_addr = 32'h40000000;
  wire [31:0] savestate_size = 32'd65536;
  wire [31:0] savestate_maxloadsize = 32'd65536;

  wire savestate_start;
  wire savestate_start_ack;
  wire savestate_start_busy;
  wire savestate_start_ok;
  wire savestate_start_err;

  wire savestate_load;
  wire savestate_load_ack;
  wire savestate_load_busy;
  wire savestate_load_ok;
  wire savestate_load_err;

  wire osnotify_inmenu;

  // The target command path is unused here. dataslot_path and dataslot_probe
  // exist for a core that has to open a file the user never picked, which the
  // PC Engine needs for a disc image and this does not.
  wire tcmd_req = 0;
  wire [15:0] tcmd = 0;
  wire [31:0] tcmd_p0 = 0;
  wire [31:0] tcmd_p1 = 0;
  wire [31:0] tcmd_p2 = 0;
  wire [31:0] tcmd_p3 = 0;
  wire tcmd_ack;
  wire tcmd_done;
  wire [15:0] tcmd_result;

  reg [9:0] datatable_addr;
  reg datatable_wren;
  reg [31:0] datatable_data;
  wire [31:0] datatable_q;

  core_bridge_cmd icb (

      .clk    (clk_74a),
      .reset_n(reset_n),

      .bridge_endian_little(bridge_endian_little),
      .bridge_addr         (bridge_addr),
      .bridge_rd           (bridge_rd),
      .bridge_rd_data      (cmd_bridge_rd_data),
      .bridge_wr           (bridge_wr),
      .bridge_wr_data      (bridge_wr_data),

      .status_boot_done (status_boot_done),
      .status_setup_done(status_setup_done),
      .status_running   (status_running),

      .dataslot_requestread    (dataslot_requestread),
      .dataslot_requestread_id (dataslot_requestread_id),
      .dataslot_requestread_ack(dataslot_requestread_ack),
      .dataslot_requestread_ok (dataslot_requestread_ok),

      .dataslot_requestwrite    (dataslot_requestwrite),
      .dataslot_requestwrite_id (dataslot_requestwrite_id),
      .dataslot_requestwrite_ack(dataslot_requestwrite_ack),
      .dataslot_requestwrite_ok (dataslot_requestwrite_ok),

      .dataslot_allcomplete(dataslot_allcomplete),

      .cart_report      (cart_report_74),
      .cart_report_valid(cart_report_valid_74),

      .target_cmd_req   (tcmd_req),
      .target_cmd       (tcmd),
      .target_cmd_p0    (tcmd_p0),
      .target_cmd_p1    (tcmd_p1),
      .target_cmd_p2    (tcmd_p2),
      .target_cmd_p3    (tcmd_p3),
      .target_cmd_ack   (tcmd_ack),
      .target_cmd_done  (tcmd_done),
      .target_cmd_result(tcmd_result),

      .savestate_supported  (savestate_supported),
      .savestate_addr       (savestate_addr),
      .savestate_size       (savestate_size),
      .savestate_maxloadsize(savestate_maxloadsize),

      .savestate_start     (savestate_start),
      .savestate_start_ack (savestate_start_ack),
      .savestate_start_busy(savestate_start_busy),
      .savestate_start_ok  (savestate_start_ok),
      .savestate_start_err (savestate_start_err),

      .savestate_load     (savestate_load),
      .savestate_load_ack (savestate_load_ack),
      .savestate_load_busy(savestate_load_busy),
      .savestate_load_ok  (savestate_load_ok),
      .savestate_load_err (savestate_load_err),

      .osnotify_inmenu(osnotify_inmenu),

      .datatable_addr(datatable_addr),
      .datatable_wren(datatable_wren),
      .datatable_data(datatable_data),
      .datatable_q   (datatable_q)
  );

  // The core ships no chip32 program, so APF loads every slot data.json
  // declares and the dataslot handshake is what says which one is streaming.
  reg any_download = 0;
  always @(posedge clk_74a) begin
    if (dataslot_requestwrite) any_download <= 1;
    else if (dataslot_allcomplete) any_download <= 0;
  end

  // Three ROM slots, one per machine; which one APF is streaming is what
  // sets the machine. The loaders below each answer their own address nibble
  // and the strobes are merged, since only one slot ever streams at a time.
  wire gg_download_74  = any_download && dataslot_requestwrite_id == 16'd1;
  wire sms_download_74 = any_download && dataslot_requestwrite_id == 16'd4;
  wire sg_download_74  = any_download && dataslot_requestwrite_id == 16'd5;
  wire cart_download_74 = gg_download_74 | sms_download_74 | sg_download_74;

  // 0: Game Gear  1: Master System  2: SG-1000. Latched when a slot write
  // starts, so it is settled before the first byte reaches gg_core.
  reg [1:0] sys_mode_74 = 2'd0;
  always @(posedge clk_74a) begin
    if (dataslot_requestwrite) begin
      case (dataslot_requestwrite_id)
        16'd4:   sys_mode_74 <= 2'd1;
        16'd5:   sys_mode_74 <= 2'd2;
        16'd1:   sys_mode_74 <= 2'd0;
        default: ;
      endcase
    end
  end
  wire save_download_74 = any_download && dataslot_requestwrite_id == 16'd2;
  wire cheat_download_74 = any_download && dataslot_requestwrite_id == 16'd3;

  // The datatable is where a core tells APF how many bytes of a nonvolatile
  // slot to write back when the core exits. data.json's Save slot is the
  // second entry (index 1), and the table addresses each slot at index*2+1;
  // the size is fixed at the nvram_inst dpram's whole 32 KB, cart RAM and the
  // 93C46 EEPROM's 128 bytes both, since both live in the one block and a
  // game only ever drives one of them.
  always @(posedge clk_74a or negedge pll_core_locked) begin
    if (~pll_core_locked) begin
      datatable_addr <= 10'd0;
      datatable_data <= 32'd0;
      datatable_wren <= 1'b0;
    end else begin
      datatable_addr <= 1 * 2 + 1;
      datatable_data <= 32'h8000;
      datatable_wren <= 1'b1;
    end
  end

  // ==========================================================================
  // Clocks
  // ==========================================================================
  wire clk_sys;  // 53.693181 MHz, the whole machine
  wire clk_vid;  // 5.369318 MHz, one edge per output pixel
  wire clk_vid_90;
  wire pll_core_locked;

  mf_pllbase mp1 (
      .refclk(clk_74a),
      .rst   (0),

      .outclk_0(clk_sys),
      .outclk_1(clk_vid),
      .outclk_2(clk_vid_90),

      .locked(pll_core_locked)
  );

  // ==========================================================================
  // Clock domain crossings into clk_sys
  // ==========================================================================
  wire pll_core_locked_s;
  wire reset_n_s;
  wire cart_download_s;
  wire save_download_s;
  wire [15:0] cont1_key_s;
  wire cheat_download_s;
  wire region_jp_s, sp64_s, fm_en_s;
  wire cheats_en_s, cheats_osd_s;
  wire reset_delay_s;

  synch_3 s_locked (pll_core_locked, pll_core_locked_s, clk_sys);
  synch_3 s_resetn (reset_n, reset_n_s, clk_sys);
  synch_3 s_dl (cart_download_74, cart_download_s, clk_sys);

  wire [1:0] sys_mode_s;
  synch_3 #(.WIDTH(2)) s_mode (sys_mode_74, sys_mode_s, clk_sys);
  wire sys_gg_s = sys_mode_s == 2'd0;
  wire sys_sg_s = sys_mode_s == 2'd2;
  synch_3 s_svdl (save_download_74, save_download_s, clk_sys);
  synch_3 s_chdl (cheat_download_74, cheat_download_s, clk_sys);
  synch_3 s_rstd (reset_delay > 0, reset_delay_s, clk_sys);
  synch_3 #(16) s_cont1 (cont1_key, cont1_key_s, clk_sys);
  synch_3 #(3) s_set ({region_jp, sp64, fm_en}, {region_jp_s, sp64_s, fm_en_s}, clk_sys);
  synch_3 #(2) s_cht ({cheats_en, cheats_osd}, {cheats_en_s, cheats_osd_s}, clk_sys);

  wire cart_hold;  // Play Cartridge selected and the image not yet in; below
  wire core_reset = ~reset_n_s | reset_delay_s | cart_hold;

  // The overrun flag the other way, for the menu readout.
  wire rom_overrun;
  wire rom_overrun_74;
  synch_3 s_ovr (rom_overrun, rom_overrun_74, clk_74a);
  wire [31:0] cart_diag_74, cart_crc_74;
  synch_3 #(32) s_cdiag (cart_diag, cart_diag_74, clk_74a);
  synch_3 #(32) s_ccrc (cb_crc32, cart_crc_74, clk_74a);

  wire [5:0] cheat_count, cheat_decl;
  wire [19:0] cheat_bytes;
  wire cheat_overrun;
  wire [5:0] cheat_count_74, cheat_decl_74;
  wire [19:0] cheat_bytes_74;
  wire cheat_overrun_74;
  synch_3 #(6) s_cc (cheat_count, cheat_count_74, clk_74a);
  synch_3 #(6) s_cd (cheat_decl, cheat_decl_74, clk_74a);
  synch_3 #(20) s_cb (cheat_bytes, cheat_bytes_74, clk_74a);
  synch_3 s_co (cheat_overrun, cheat_overrun_74, clk_74a);

  wire cheat_is_bin;
  wire cheat_is_bin_74;
  wire [5:0] osd_titles_74, osd_codes_74;
  synch_3 s_cf (cheat_is_bin, cheat_is_bin_74, clk_74a);

  // The overlay lives on clk_vid, so what it reads crosses into that domain
  // here. de and v_blank do not: they are the same clk_sys signals the video
  // stage below already samples on clk_vid, statically timed inside one clock
  // group by core_constraints.sdc, and proven on hardware since P0.
  wire reset_n_v, cheats_osd_v;
  wire [5:0] osd_titles_v, osd_codes_v;
  synch_3 s_resetv (reset_n, reset_n_v, clk_vid);
  synch_3 s_osdv (cheats_osd, cheats_osd_v, clk_vid);
  synch_3 #(6) s_ot (osd_titles, osd_titles_v, clk_vid);
  synch_3 #(6) s_oc (osd_codes, osd_codes_v, clk_vid);
  synch_3 #(6) s_ot74 (osd_titles, osd_titles_74, clk_74a);
  synch_3 #(6) s_oc74 (osd_codes, osd_codes_74, clk_74a);

  // ==========================================================================
  // ROM in
  // ==========================================================================
  wire ioctl_wr;
  wire [24:0] ioctl_addr;
  wire [7:0] ioctl_dout;

  wire        gg_wr, sms_wr, sg_wr;
  wire [24:0] gg_addr, sms_addr, sg_addr;
  wire  [7:0] gg_dout, sms_dout, sg_dout;

  data_loader #(
      .ADDRESS_MASK_UPPER_4 (4'h1),
      .ADDRESS_SIZE         (25),
      .OUTPUT_WORD_SIZE     (1),
      .WRITE_MEM_CLOCK_DELAY(4)
  ) gg_loader (
      .clk_74a   (clk_74a),
      .clk_memory(clk_sys),

      .bridge_wr           (bridge_wr),
      .bridge_endian_little(bridge_endian_little),
      .bridge_addr         (bridge_addr),
      .bridge_wr_data      (bridge_wr_data),

      .write_en  (gg_wr),
      .write_addr(gg_addr),
      .write_data(gg_dout)
  );

  data_loader #(
      .ADDRESS_MASK_UPPER_4 (4'h3),
      .ADDRESS_SIZE         (25),
      .OUTPUT_WORD_SIZE     (1),
      .WRITE_MEM_CLOCK_DELAY(4)
  ) sms_loader (
      .clk_74a   (clk_74a),
      .clk_memory(clk_sys),

      .bridge_wr           (bridge_wr),
      .bridge_endian_little(bridge_endian_little),
      .bridge_addr         (bridge_addr),
      .bridge_wr_data      (bridge_wr_data),

      .write_en  (sms_wr),
      .write_addr(sms_addr),
      .write_data(sms_dout)
  );

  data_loader #(
      .ADDRESS_MASK_UPPER_4 (4'h6),
      .ADDRESS_SIZE         (25),
      .OUTPUT_WORD_SIZE     (1),
      .WRITE_MEM_CLOCK_DELAY(4)
  ) sg_loader (
      .clk_74a   (clk_74a),
      .clk_memory(clk_sys),

      .bridge_wr           (bridge_wr),
      .bridge_endian_little(bridge_endian_little),
      .bridge_addr         (bridge_addr),
      .bridge_wr_data      (bridge_wr_data),

      .write_en  (sg_wr),
      .write_addr(sg_addr),
      .write_data(sg_dout)
  );

  // gg_core looks at ioctl_addr once more after the stream ends, to tell a
  // headered dump from a plain one, so the merged address holds the last
  // strobed value rather than falling back to an idle loader's.
  // The fourth source is the cartridge, gg_cart_boot below.
  wire        cb_wr, cb_busy, cb_done, cb_header_ok, cart_pins_ready;
  wire [24:0] cb_addr;
  wire [7:0]  cb_data;
  wire [3:0]  cb_size_code, cb_state;
  wire [31:0] cb_size_bytes, cb_crc32;
  wire [24:0] sel_addr = gg_wr ? gg_addr : sms_wr ? sms_addr : sg_wr ? sg_addr : cb_addr;
  reg  [24:0] held_addr = 0;
  always @(posedge clk_sys) if (gg_wr | sms_wr | sg_wr | cb_wr) held_addr <= sel_addr;

  assign ioctl_wr   = gg_wr | sms_wr | sg_wr | cb_wr;
  assign ioctl_addr = ioctl_wr ? sel_addr : held_addr;
  assign ioctl_dout = gg_wr ? gg_dout : sms_wr ? sms_dout : sg_wr ? sg_dout : cb_data;

  // ==========================================================================
  // Cartridge. Only kroy.GG's core.json turns the slot on (bit 24, Play
  // Cartridge). Session: report 0x00B1 says Play Cartridge, power on and the
  // Game Gear adapter ID, and the host has left reset. cart_pins owns the
  // connector, gg_cart_bus the cycles, gg_cart_boot reads the image into the
  // ROM stream. Reset held from Play Cartridge until the last byte. First
  // read 2.5 s after admission (pocket-cartridge's slot supply settling).
  // ==========================================================================
  localparam [7:0] GG_ADAPTER_ID = 8'h01;

  wire [31:0] cart_report_s;
  wire        cart_report_valid_s;
  cart_adapter_state adapter_state (
      .clk_host   (clk_74a),
      .reset_host (~pll_core_locked),
      .report_host(cart_report_74),
      .valid_host (cart_report_valid_74),
      .clk_sys    (clk_sys),
      .reset_sys  (~pll_core_locked_s),
      .report     (cart_report_s),
      .valid      (cart_report_valid_s),
      .changed    (),
      .report_seq ()
  );

  wire cart_play_s    = cart_report_valid_s && cart_report_s[24];
  wire cart_powered_s = cart_play_s && cart_report_s[16] && cart_report_s[7:0] == GG_ADAPTER_ID;

  reg cart_session = 0;
  always @(posedge clk_sys) begin
    if (!cart_powered_s)  cart_session <= 1'b0;
    else if (reset_n_s)   cart_session <= 1'b1;
  end

  reg [27:0] cart_settle  = 0;
  reg        cart_started = 0;
  wire       cart_start   = cart_session && cart_pins_ready && !cart_started && cart_settle[27];
  always @(posedge clk_sys) begin
    if (!cart_session) begin
      cart_settle  <= 0;
      cart_started <= 1'b0;
    end else begin
      if (!cart_settle[27]) cart_settle <= cart_settle + 1'b1;
      if (cart_start) cart_started <= 1'b1;
    end
  end

  wire [15:0] cb_e_ad_out;
  wire        cb_e_ad_oe, cb_e_hi_oe, cb_e_p30_out, cb_e_p30_oe;
  wire [7:0]  cb_e_hi_out, cb_e_hi_in;
  wire [3:0]  cb_e_ctl_out;

  cart_pins cart_pins (
      .clk  (clk_sys),
      .reset(~pll_core_locked_s),
      .mode (cart_session ? 2'b11 : 2'b00),
      .mode_ready(cart_pins_ready),

      .gba_ad_out(16'd0), .gba_ad_oe(1'b0), .gba_hi_out(8'd0), .gba_hi_oe(1'b0),
      .gba_ctl_out(4'hF), .gba_p30_out(1'b0), .gba_p30_oe(1'b0), .gba_ad_in(), .gba_hi_in(),
      .gb_ad_out(16'd0), .gb_ad_oe(1'b0), .gb_hi_out(8'd0), .gb_hi_oe(1'b0),
      .gb_ctl_out(4'hF), .gb_p30_out(1'b0), .gb_p30_oe(1'b0), .gb_ad_in(), .gb_hi_in(),

      .gg_ad_out (cb_e_ad_out),
      .gg_ad_oe  (cb_e_ad_oe),
      .gg_hi_out (cb_e_hi_out),
      .gg_hi_oe  (cb_e_hi_oe),
      .gg_ctl_out(cb_e_ctl_out),
      .gg_p30_out(cb_e_p30_out),
      .gg_p30_oe (cb_e_p30_oe),
      .gg_hi_in  (cb_e_hi_in),

      .cart_tran_bank2(cart_tran_bank2), .cart_tran_bank2_dir(cart_tran_bank2_dir),
      .cart_tran_bank3(cart_tran_bank3), .cart_tran_bank3_dir(cart_tran_bank3_dir),
      .cart_tran_bank1(cart_tran_bank1), .cart_tran_bank1_dir(cart_tran_bank1_dir),
      .cart_tran_bank0(cart_tran_bank0), .cart_tran_bank0_dir(cart_tran_bank0_dir),
      .cart_tran_pin30(cart_tran_pin30), .cart_tran_pin30_dir(cart_tran_pin30_dir),
      .cart_pin30_pwroff_reset(cart_pin30_pwroff_reset),
      .cart_tran_pin31(cart_tran_pin31), .cart_tran_pin31_dir(cart_tran_pin31_dir)
  );

  wire        cb_bus_req, cb_bus_wr, cb_bus_done, cb_bus_busy;
  wire [15:0] cb_bus_addr;
  wire [7:0]  cb_bus_wdata, cb_bus_rdata;

  // 0.5 us setup, 1 us strobe, 0.5 us recovery: pocket-cartridge's profile.
  gg_cart_bus #(
      .ADDR_SETUP_CYCLES(27),
      .STROBE_CYCLES    (54),
      .HOLD_CYCLES      (27)
  ) gg_cart_bus (
      .clk    (clk_sys),
      .reset  (~pll_core_locked_s),
      .gg_mode(cart_pins_ready),
      .req    (cb_bus_req),
      .wr     (cb_bus_wr),
      .addr   (cb_bus_addr),
      .wdata  (cb_bus_wdata),
      .rdata  (cb_bus_rdata),
      .done   (cb_bus_done),
      .busy   (cb_bus_busy),
      .write_active(),
      .rejected(),

      .e_ad_out (cb_e_ad_out),
      .e_ad_oe  (cb_e_ad_oe),
      .e_hi_out (cb_e_hi_out),
      .e_hi_oe  (cb_e_hi_oe),
      .e_hi_in  (cb_e_hi_in),
      .e_ctl_out(cb_e_ctl_out),
      .e_p30_out(cb_e_p30_out),
      .e_p30_oe (cb_e_p30_oe)
  );

  gg_cart_boot gg_cart_boot (
      .clk  (clk_sys),
      .reset(!cart_session),
      .start(cart_start),

      .bus_req  (cb_bus_req),
      .bus_wr   (cb_bus_wr),
      .bus_addr (cb_bus_addr),
      .bus_wdata(cb_bus_wdata),
      .bus_rdata(cb_bus_rdata),
      .bus_done (cb_bus_done),
      .bus_busy (cb_bus_busy),

      .out_wr  (cb_wr),
      .out_addr(cb_addr),
      .out_data(cb_data),

      .busy      (cb_busy),
      .done      (cb_done),
      .header_ok (cb_header_ok),
      .size_code (cb_size_code),
      .size_bytes(cb_size_bytes),
      .crc32     (cb_crc32),
      .state     (cb_state)
  );

  // A wrong or missing adapter keeps the reset held; CG: says why.
  assign cart_hold = cart_play_s && !cb_done;

  // CS: readout.
  wire [31:0] cart_diag = {4'd0, cb_state, 3'd0, cb_header_ok, cb_size_code, 3'd0, cb_busy, 3'd0, cb_done,
                           1'b0, cart_start, cart_started, cart_session, 3'd0, cart_pins_ready};

  // ==========================================================================
  // Cheats in
  //
  // One slot, two readers, both mechanisms. The slot takes a plain libretro
  // .cht or the packed .chtbin that tools/cheats/gg2bin.py writes, and the
  // first four bytes decide which reader owns the file. Either way an entry
  // bound for work RAM goes to cheat_poker's table inside gg_core and every
  // other entry is a Game Genie code clocked into system.vhd's CODES.
  //
  // Both are shipped for the reason pocket-gba ships both: a .chtbin is small
  // and needs no parser, but it carries no names, and the overlay's list can
  // only come from a .cht's `cheatN_desc` keys. See rtl/gg/cheat_loader.sv and
  // rtl/gg/cheat_binloader.sv.
  // ==========================================================================
  wire cheat_wr;
  wire [7:0] cheat_dout;

  data_loader #(
      .ADDRESS_MASK_UPPER_4 (4'h5),
      .ADDRESS_SIZE         (20),
      .OUTPUT_WORD_SIZE     (1),
      .WRITE_MEM_CLOCK_DELAY(4)
  ) cheat_data_loader (
      .clk_74a   (clk_74a),
      .clk_memory(clk_sys),

      .bridge_wr           (bridge_wr),
      .bridge_endian_little(bridge_endian_little),
      .bridge_addr         (bridge_addr),
      .bridge_wr_data      (bridge_wr_data),

      .write_en  (cheat_wr),
      .write_addr(),
      .write_data(cheat_dout)
  );

  // The download's edges. The rising one restarts both readers, which is what
  // lets a second file replace the first: the binary reader arms its header
  // check there and the text reader clears its parser and its table. The
  // falling one is end of file, which the text reader needs because the last
  // cheat in a .cht has nothing after it to resolve its enable key.
  reg cheat_download_d = 0;
  always @(posedge clk_sys) cheat_download_d <= cheat_download_s;
  wire cheat_start = ~cheat_download_d & cheat_download_s;
  wire cheat_eof   = cheat_download_d & ~cheat_download_s;
  wire cheat_reset = core_reset | cheat_start;
  wire cheat_byte  = cheat_wr & cheat_download_s;

  // Which reader gets the file, decided on its first four bytes. Both are fed
  // every byte and only their outputs are muxed, which is safe because the
  // verdict is settled at byte four and neither reader can emit before then:
  // the binary one frames on sixteen bytes and the text one needs `_code = "`.
  reg [31:0] cheat_sniff = 0;
  reg  [2:0] cheat_sniff_n = 0;
  reg        cheat_bin = 0;
  always @(posedge clk_sys) begin
    if (cheat_reset) begin
      cheat_sniff_n <= 3'd0;
      cheat_bin     <= 1'b0;
    end else if (cheat_byte && cheat_sniff_n != 3'd4) begin
      cheat_sniff   <= {cheat_dout, cheat_sniff[31:8]};
      cheat_sniff_n <= cheat_sniff_n + 3'd1;
      // "GGCH", byte 0 in the LSB, the same constant cheat_binloader checks.
      if (cheat_sniff_n == 3'd3)
        cheat_bin <= ({cheat_dout, cheat_sniff[31:8]} == 32'h48434747);
    end
  end
  assign cheat_is_bin = cheat_bin;

  wire [128:0] bin_code, asc_code;
  wire bin_code_reset, asc_code_reset;
  wire bin_poke_wr, asc_poke_wr;
  wire [4:0] bin_poke_index, asc_poke_index;
  wire [12:0] bin_poke_addr, asc_poke_addr;
  wire [7:0] bin_poke_data, asc_poke_data;
  wire [5:0] bin_poke_total, asc_poke_total;
  wire [5:0] bin_count, asc_count, bin_decl, asc_decl;
  wire [19:0] bin_bytes, asc_bytes;
  wire bin_overrun, asc_overrun;

  wire [128:0] gg_code = cheat_bin ? bin_code : asc_code;
  // Both clear CODES' table at the head of a file and neither can do so after
  // a code has gone in, so this one is an or rather than a mux: the text
  // reader raises it on byte zero, before the verdict above is known.
  wire gg_code_reset = bin_code_reset | asc_code_reset;
  wire poke_code_wr = cheat_bin ? bin_poke_wr : asc_poke_wr;
  wire [4:0] poke_code_index = cheat_bin ? bin_poke_index : asc_poke_index;
  wire [12:0] poke_code_addr = cheat_bin ? bin_poke_addr : asc_poke_addr;
  wire [7:0] poke_code_data = cheat_bin ? bin_poke_data : asc_poke_data;
  wire [5:0] poke_code_total = cheat_bin ? bin_poke_total : asc_poke_total;

  assign cheat_count   = cheat_bin ? bin_count : asc_count;
  assign cheat_decl    = cheat_bin ? bin_decl : asc_decl;
  assign cheat_bytes   = cheat_bin ? bin_bytes : asc_bytes;
  assign cheat_overrun = cheat_bin ? bin_overrun : asc_overrun;

  // What the overlay draws its header from. Cheats only have names when a .cht
  // was read, so a .chtbin reports none and the header says so instead of
  // drawing blank rows. Codes are the two mechanisms together, which is also
  // what the 32 slot ceiling counts.
  wire [5:0] osd_titles = cheat_bin ? 6'd0 : asc_decl;
  wire [6:0] osd_sum    = {1'b0, cheat_count} + {1'b0, poke_code_total};
  wire [5:0] osd_codes  = osd_sum[5:0];

  cheat_binloader chtbin (
      .clk  (clk_sys),
      .reset(cheat_reset),

      .wr  (cheat_byte),
      .data(cheat_dout),
      .eof (cheat_eof),

      .gg_code   (bin_code),
      .code_reset(bin_code_reset),

      .poke_wr   (bin_poke_wr),
      .poke_index(bin_poke_index),
      .poke_addr (bin_poke_addr),
      .poke_data (bin_poke_data),
      .poke_total(bin_poke_total),

      .genie_count(bin_count),
      .group_count(bin_decl),
      .byte_count (bin_bytes),
      .overrun    (bin_overrun)
  );

  wire cht_desc_wr, cht_desc_end;
  wire [4:0] cht_desc_group, cht_desc_col;
  wire [5:0] cht_desc_char;

  cheat_loader cht (
      .clk  (clk_sys),
      .reset(cheat_reset),

      .wr  (cheat_byte),
      .data(cheat_dout),
      .eof (cheat_eof),

      .gg_code   (asc_code),
      .code_reset(asc_code_reset),

      .poke_wr   (asc_poke_wr),
      .poke_index(asc_poke_index),
      .poke_addr (asc_poke_addr),
      .poke_data (asc_poke_data),
      .poke_total(asc_poke_total),

      .genie_count(asc_count),
      .group_count(asc_decl),
      .byte_count (asc_bytes),
      .overrun    (asc_overrun),

      .desc_wr   (cht_desc_wr),
      .desc_group(cht_desc_group),
      .desc_col  (cht_desc_col),
      .desc_char (cht_desc_char),
      .desc_end  (cht_desc_end)
  );

  // The names. Written by the parser on clk_sys and read by the overlay on
  // clk_vid, which is what cheat_titles is a dual clock RAM for.
  wire [4:0] osd_group, osd_col;
  wire [5:0] osd_char, osd_font_ch;
  wire [4:0] osd_len;
  wire [2:0] osd_font_row;
  wire [7:0] osd_font_bits;
  wire       osd_active, osd_ink;

  cheat_titles titles (
      .wr_clk  (clk_sys),
      .wr_reset(cheat_reset),

      .wr_en   (cht_desc_wr),
      .wr_group(cht_desc_group),
      .wr_col  (cht_desc_col),
      .wr_char (cht_desc_char),
      .wr_end  (cht_desc_end),

      .rd_clk  (clk_vid),
      .rd_group(osd_group),
      .rd_col  (osd_col),
      .rd_char (osd_char),
      .rd_len  (osd_len)
  );

  cheat_font font (
      .ch  (osd_font_ch),
      .row (osd_font_row),
      .bits(osd_font_bits)
  );

  // One pixel per clk_vid edge, so de alone paces it and there is no ce_pix to
  // hand over. The panel is 156x144 of the 160x144 raster: it fills the screen.
  cheat_osd osd (
      .clk    (clk_vid),
      .reset  (~reset_n_v),

      .show   (cheats_osd_v),
      .de     (osd_de),
      .v_blank(core_vbl),

      .title_count(osd_titles_v),
      .code_count (osd_codes_v),

      .title_group(osd_group),
      .title_col  (osd_col),
      .title_char (osd_char),
      .title_len  (osd_len),

      .font_ch  (osd_font_ch),
      .font_row (osd_font_row),
      .font_bits(osd_font_bits),

      .active(osd_active),
      .ink   (osd_ink)
  );

  // ==========================================================================
  // Save RAM, in and out
  //
  // gg_core's nvram_inst is one 32 KB dpram behind cart RAM and the 93C46
  // EEPROM alike (system.vhd muxes the two onto the same bus), so one loader
  // and one unloader on the whole block covers both save kinds without this
  // file knowing which one a given cartridge uses.
  //
  // The two never run at once: the loader only drives the bus while APF is
  // still streaming the save slot in at boot (save_download_s), and the
  // unloader only reads it back out when the core exits. save_download_s
  // picks which one owns bram_addr.
  // ==========================================================================
  wire [31:0] save_rd_data;

  wire save_ld_wr;
  wire [14:0] save_ld_addr;
  wire [7:0] save_ld_data;

  wire save_ul_rd;
  wire [14:0] save_ul_addr;

  data_loader #(
      .ADDRESS_MASK_UPPER_4 (4'h2),
      .ADDRESS_SIZE         (15),
      .OUTPUT_WORD_SIZE     (1),
      .WRITE_MEM_CLOCK_DELAY(4)
  ) save_data_loader (
      .clk_74a   (clk_74a),
      .clk_memory(clk_sys),

      .bridge_wr           (bridge_wr),
      .bridge_endian_little(bridge_endian_little),
      .bridge_addr         (bridge_addr),
      .bridge_wr_data      (bridge_wr_data),

      .write_en  (save_ld_wr),
      .write_addr(save_ld_addr),
      .write_data(save_ld_data)
  );

  data_unloader #(
      .ADDRESS_MASK_UPPER_4(4'h2),
      .ADDRESS_SIZE        (15),
      .INPUT_WORD_SIZE     (1),
      .READ_MEM_CLOCK_DELAY(4)
  ) save_data_unloader (
      .clk_74a   (clk_74a),
      .clk_memory(clk_sys),

      .bridge_rd           (bridge_rd),
      .bridge_endian_little(bridge_endian_little),
      .bridge_addr         (bridge_addr),
      .bridge_rd_data      (save_rd_data),

      .read_en  (save_ul_rd),
      .read_addr(save_ul_addr),
      .read_data(bram_dout)
  );

  wire [14:0] bram_addr = save_download_s ? save_ld_addr : save_ul_addr;
  wire bram_wr = save_download_s & save_ld_wr;
  wire [7:0] bram_din = save_ld_data;
  wire [7:0] bram_dout;

  // ==========================================================================
  // Controls
  //
  // A Game Gear has a D-pad, buttons 1 and 2, and Start.
  //
  // Button 1 is A and button 2 is B, which is how MiSTer orders them and puts
  // the button most games use to jump under the Pocket's primary face button.
  // On the console itself 1 is the left of the pair and 2 the right, so the
  // other assignment is just as arguable; input.json names them so the Pocket's
  // own remapping screen can settle it per player.
  // ==========================================================================
  wire [6:0] joy1_gg;
  assign joy1_gg[0] = cont1_key_s[3];                    // right
  assign joy1_gg[1] = cont1_key_s[2];                    // left
  assign joy1_gg[2] = cont1_key_s[1];                    // down
  assign joy1_gg[3] = cont1_key_s[0];                    // up
  assign joy1_gg[4] = cont1_key_s[4];                    // button 1 <- A
  assign joy1_gg[5] = cont1_key_s[5];                    // button 2 <- B
  assign joy1_gg[6] = cont1_key_s[15];                   // start

  // ==========================================================================
  // The machine
  // ==========================================================================
  wire ce_pix;
  wire [11:0] color;
  wire core_hs, core_vs, core_hbl, core_vbl;
  wire [1:0] video_mode;
  wire signed [15:0] audio_l, audio_r;

  // ==========================================================================
  // Savestates
  // ==========================================================================
  wire        ss_save, ss_load, ss_freeze, ss_restored;
  wire [28:0] ss_ddram_addr;
  wire [63:0] ss_ddram_din, ss_ddram_dout;
  wire        ss_ddram_we, ss_ddram_rd, ss_ddram_dout_ready, ss_ddram_busy;
  wire [31:0] ss_rd_data;

  savestate_apf ss (
      .clk_74a(clk_74a),
      .clk_sys(clk_sys),
      .reset_n(~core_reset),

      .savestate_start     (savestate_start),
      .savestate_start_ack (savestate_start_ack),
      .savestate_start_busy(savestate_start_busy),
      .savestate_start_ok  (savestate_start_ok),
      .savestate_start_err (savestate_start_err),
      .savestate_load      (savestate_load),
      .savestate_load_ack  (savestate_load_ack),
      .savestate_load_busy (savestate_load_busy),
      .savestate_load_ok   (savestate_load_ok),
      .savestate_load_err  (savestate_load_err),

      .bridge_wr           (bridge_wr),
      .bridge_rd           (bridge_rd),
      .bridge_endian_little(bridge_endian_little),
      .bridge_addr         (bridge_addr),
      .bridge_wr_data      (bridge_wr_data),
      .bridge_rd_data      (ss_rd_data),

      .ss_save         (ss_save),
      .ss_load         (ss_load),
      .ss_freeze       (ss_freeze),
      .ss_restored     (ss_restored),
      .ddram_addr      (ss_ddram_addr),
      .ddram_din       (ss_ddram_din),
      .ddram_we        (ss_ddram_we),
      .ddram_rd        (ss_ddram_rd),
      .ddram_dout      (ss_ddram_dout),
      .ddram_dout_ready(ss_ddram_dout_ready),
      .ddram_busy      (ss_ddram_busy)
  );

  gg_core gg (
      .clk_sys   (clk_sys),
      .pll_locked(pll_core_locked_s),
      .reset     (core_reset),

      .cart_download(cart_download_s | cb_busy),
      .ioctl_wr     (ioctl_wr),
      .ioctl_addr   (ioctl_addr),
      .ioctl_dout   (ioctl_dout),

      .joy1(joy1_gg),

      .sys_gg    (sys_gg_s),
      .sys_sg    (sys_sg_s),
      .video_mode(video_mode),

      .ggres    (sys_gg_s),
      .region_jp(region_jp_s),
      .sp64     (sp64_s),
      .fm_ena   (fm_en_s),

      .ce_pix(ce_pix),
      .color (color),
      .hsync (core_hs),
      .vsync (core_vs),
      .hblank(core_hbl),
      .vblank(core_vbl),

      .audio_l(audio_l),
      .audio_r(audio_r),

      .cheats_en      (cheats_en_s),
      .gg_code        (gg_code),
      .gg_code_reset  (gg_code_reset),
      .gg_avail       (),

      .poke_code_wr   (poke_code_wr),
      .poke_code_index(poke_code_index),
      .poke_code_addr (poke_code_addr),
      .poke_code_data (poke_code_data),
      .poke_code_total(poke_code_total),

      .rom_overrun(rom_overrun),

      .bram_addr(bram_addr),
      .bram_din (bram_din),
      .bram_wr  (bram_wr),
      .bram_dout(bram_dout),

      .ss_save            (ss_save),
      .ss_load            (ss_load),
      .ss_freeze          (ss_freeze),
      .ss_restored        (ss_restored),
      .ss_ddram_addr      (ss_ddram_addr),
      .ss_ddram_din       (ss_ddram_din),
      .ss_ddram_we        (ss_ddram_we),
      .ss_ddram_rd        (ss_ddram_rd),
      .ss_ddram_dout      (ss_ddram_dout),
      .ss_ddram_dout_ready(ss_ddram_dout_ready),
      .ss_ddram_busy      (ss_ddram_busy),

      .dram_a    (dram_a),
      .dram_ba   (dram_ba),
      .dram_dq   (dram_dq),
      .dram_dqm  (dram_dqm),
      .dram_clk  (dram_clk),
      .dram_cke  (dram_cke),
      .dram_ras_n(dram_ras_n),
      .dram_cas_n(dram_cas_n),
      .dram_we_n (dram_we_n)
  );

  // ==========================================================================
  // Video
  //
  // clk_vid is exactly clk_sys/10, which is the VDP's pixel rate, so one edge
  // of it is one pixel and video_skip is never needed. The VDP holds each
  // pixel for ten clk_sys cycles and both clocks come from one PLL, so the
  // transfer below is a static timing problem rather than a metastability one
  // and core_constraints.sdc keeps the two in the same clock group so that the
  // analyser actually checks it.
  //
  // What APF wants, and what the sibling cores paid to find out:
  //  * video_hs and video_vs are one-cycle pulses, not levels.
  //  * hs is delayed a few cycles so it can never land on the same edge as vs.
  //  * video_rgb must be exactly zero while video_de is low: APF reads that
  //    word as a control channel rather than as a colour.
  // ==========================================================================
  wire de = ~(core_hbl | core_vbl);

  // Which of video.json's scaler modes this frame is. The mode follows the
  // VDP's registers, which a game can change between frames; APF takes the
  // word sent after the last line of a frame for the next one.
  reg [1:0] vmode_v = 0, vmode_v2 = 0;
  always @(posedge clk_vid) {vmode_v, vmode_v2} <= {vmode_v2, video_mode};

  // The overlay is laid out for the 160x144 window. On the wider machines it
  // is drawn in a window of that size in the middle of the picture, by
  // handing it a `de` that is only true inside that window.
  reg [8:0] hx = 0;
  reg [8:0] vy = 0;
  reg       de_prev_v = 0;
  always @(posedge clk_vid) begin
    de_prev_v <= de;
    hx <= de ? hx + 9'd1 : 9'd0;
    if (de_prev_v & ~de) vy <= vy + 9'd1;
    if (core_vbl) vy <= 9'd0;
  end
  wire [8:0] win_x0 = (vmode_v == 2'd0) ? 9'd0 : 9'd48;
  wire [8:0] win_y0 = (vmode_v == 2'd0) ? 9'd0 :
                      (vmode_v == 2'd1) ? 9'd24 :
                      (vmode_v == 2'd2) ? 9'd40 : 9'd48;
  wire osd_de = de && hx >= win_x0 && hx < win_x0 + 9'd160
                   && vy >= win_y0 && vy < win_y0 + 9'd144;

  // The VDP's colour is 4 bits per channel; the top four bits are repeated
  // into the low four so that full scale stays full scale.
  wire [7:0] vid_r = {color[3:0], color[3:0]};
  wire [7:0] vid_g = {color[7:4], color[7:4]};
  wire [7:0] vid_b = {color[11:8], color[11:8]};

  reg video_de_reg = 0;
  reg video_hs_reg = 0;
  reg video_vs_reg = 0;
  reg [23:0] video_rgb_reg = 0;

  reg hs_prev = 0;
  reg vs_prev = 0;
  reg [2:0] hs_delay = 0;

  always @(posedge clk_vid) begin
    video_hs_reg  <= 0;
    video_de_reg  <= 0;
    video_rgb_reg <= 24'h0;

    if (de) begin
      video_de_reg  <= 1;
      // Ink white, panel black. Drawn over the picture rather than blended, so
      // the text stays readable on whatever the game has put up behind it.
      video_rgb_reg <= osd_active ? (osd_ink ? 24'hFFFFFF : 24'h000000)
                                  : {vid_r, vid_g, vid_b};
    end else if (video_de_reg) begin
      // The clock after DE falls carries APF's end-of-line word: function
      // 000 in [2:0] is "set scaler slot", the slot in [15:13]. Zero, which
      // every other blanked clock sends, means slot 0, so this only has to be
      // right on the lines that matter and is sent on all of them.
      video_rgb_reg <= {8'd0, 1'b0, vmode_v, 13'd0};
    end

    if (hs_delay > 0) hs_delay <= hs_delay - 3'd1;
    if (hs_delay == 3'd1) video_hs_reg <= 1;
    if (~hs_prev && core_hs) hs_delay <= 3'd7;

    video_vs_reg <= ~vs_prev && core_vs;

    hs_prev <= core_hs;
    vs_prev <= core_vs;
  end

  assign video_rgb_clock    = clk_vid;
  assign video_rgb_clock_90 = clk_vid_90;
  assign video_de           = video_de_reg;
  assign video_hs           = video_hs_reg;
  assign video_vs           = video_vs_reg;
  assign video_rgb          = video_rgb_reg;
  assign video_skip         = 1'b0;

  // ==========================================================================
  // Audio
  //
  // audio_frame_avg averages each 48 kHz frame before sound_i2s samples it.
  // ==========================================================================
  wire signed [15:0] audio_avg_l, audio_avg_r;

  audio_frame_avg audio_frame_avg (
      .clk  (clk_sys),
      .in_l (audio_l),
      .in_r (audio_r),
      .out_l(audio_avg_l),
      .out_r(audio_avg_r)
  );

  sound_i2s #(
      .CHANNEL_WIDTH(16),
      .SIGNED_INPUT (1)
  ) sound_i2s (
      .clk_74a  (clk_74a),
      .clk_audio(clk_sys),

      .audio_l(audio_avg_l),
      .audio_r(audio_avg_r),

      .audio_mclk(audio_mclk),
      .audio_lrck(audio_lrck),
      .audio_dac (audio_dac)
  );

endmodule
