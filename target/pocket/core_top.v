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

  // cart is unused, so set all level translators accordingly
  // directions are 0:IN, 1:OUT
  assign cart_tran_bank3         = 8'hzz;
  assign cart_tran_bank3_dir     = 1'b0;
  assign cart_tran_bank2         = 8'hzz;
  assign cart_tran_bank2_dir     = 1'b0;
  assign cart_tran_bank1         = 8'hzz;
  assign cart_tran_bank1_dir     = 1'b0;
  assign cart_tran_bank0         = 4'hf;
  assign cart_tran_bank0_dir     = 1'b1;
  assign cart_tran_pin30         = 1'b0;  // reset or cs2, we let the hw control it by itself
  assign cart_tran_pin30_dir     = 1'bz;
  assign cart_pin30_pwroff_reset = 1'b0;  // hardware can control this
  assign cart_tran_pin31         = 1'bz;  // input
  assign cart_tran_pin31_dir     = 1'b0;  // input

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

  // A Game Gear draws 160x144 and video.json declares that one mode, so the
  // upstream "Extended" option that opens the picture out to the whole 256x192
  // field is not offered: it would need a second scaler mode and the APF slot
  // word that selects between them, which is P5 work if Master System is ever
  // in scope.
  reg region_jp = 0;  // 0 = export, 1 = Japan
  reg sp64 = 0;  // lift the 8-sprites-per-line limit

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
      endcase
    end

    if (bridge_rd) begin
      casex (bridge_addr)
        32'hF0000100: settings_rd_data <= {31'd0, region_jp};
        32'hF0000104: settings_rd_data <= {31'd0, sp64};
        // Diagnostics. The Pocket menu is the only console this core has, so
        // the one thing that can go wrong silently is reported as a number:
        // a non-zero value here means bytes were dropped on the way into
        // SDRAM and the loaded ROM has holes in it.
        32'hF0000200: settings_rd_data <= {31'd0, rom_overrun_74};
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

  // No APF savestates yet: docs/PLAN.md 9.4 decides between MiSTer's
  // savestates.sv and the APF mechanism once P0 has measured what is free.
  wire savestate_supported = 0;
  wire [31:0] savestate_addr = 0;
  wire [31:0] savestate_size = 0;
  wire [31:0] savestate_maxloadsize = 0;

  wire savestate_start;
  wire savestate_start_ack = 0;
  wire savestate_start_busy = 0;
  wire savestate_start_ok = 0;
  wire savestate_start_err = 0;

  wire savestate_load;
  wire savestate_load_ack = 0;
  wire savestate_load_busy = 0;
  wire savestate_load_ok = 0;
  wire savestate_load_err = 0;

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

  wire cart_download_74 = any_download && dataslot_requestwrite_id == 16'd1;
  wire save_download_74 = any_download && dataslot_requestwrite_id == 16'd2;

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
  wire region_jp_s, sp64_s;
  wire reset_delay_s;

  synch_3 s_locked (pll_core_locked, pll_core_locked_s, clk_sys);
  synch_3 s_resetn (reset_n, reset_n_s, clk_sys);
  synch_3 s_dl (cart_download_74, cart_download_s, clk_sys);
  synch_3 s_svdl (save_download_74, save_download_s, clk_sys);
  synch_3 s_rstd (reset_delay > 0, reset_delay_s, clk_sys);
  synch_3 #(16) s_cont1 (cont1_key, cont1_key_s, clk_sys);
  synch_3 #(2) s_set ({region_jp, sp64}, {region_jp_s, sp64_s}, clk_sys);

  wire core_reset = ~reset_n_s | reset_delay_s;

  // The overrun flag the other way, for the menu readout.
  wire rom_overrun;
  wire rom_overrun_74;
  synch_3 s_ovr (rom_overrun, rom_overrun_74, clk_74a);

  // ==========================================================================
  // ROM in
  // ==========================================================================
  wire ioctl_wr;
  wire [24:0] ioctl_addr;
  wire [7:0] ioctl_dout;

  data_loader #(
      .ADDRESS_MASK_UPPER_4 (4'h1),
      .ADDRESS_SIZE         (25),
      .OUTPUT_WORD_SIZE     (1),
      .WRITE_MEM_CLOCK_DELAY(4)
  ) rom_loader (
      .clk_74a   (clk_74a),
      .clk_memory(clk_sys),

      .bridge_wr           (bridge_wr),
      .bridge_endian_little(bridge_endian_little),
      .bridge_addr         (bridge_addr),
      .bridge_wr_data      (bridge_wr_data),

      .write_en  (ioctl_wr),
      .write_addr(ioctl_addr),
      .write_data(ioctl_dout)
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
  wire signed [15:0] audio_l, audio_r;

  gg_core gg (
      .clk_sys   (clk_sys),
      .pll_locked(pll_core_locked_s),
      .reset     (core_reset),

      .cart_download(cart_download_s),
      .ioctl_wr     (ioctl_wr),
      .ioctl_addr   (ioctl_addr),
      .ioctl_dout   (ioctl_dout),

      .joy1(joy1_gg),

      .ggres    (1'b1),
      .region_jp(region_jp_s),
      .sp64     (sp64_s),

      .ce_pix(ce_pix),
      .color (color),
      .hsync (core_hs),
      .vsync (core_vs),
      .hblank(core_hbl),
      .vblank(core_vbl),

      .audio_l(audio_l),
      .audio_r(audio_r),

      .rom_overrun(rom_overrun),

      .bram_addr(bram_addr),
      .bram_din (bram_din),
      .bram_wr  (bram_wr),
      .bram_dout(bram_dout),

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
      video_rgb_reg <= {vid_r, vid_g, vid_b};
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
  // The PSG output is a continuously updated signed level, not a stream of
  // samples: sound_i2s resamples it to 48 kHz by taking whatever it finds.
  // ==========================================================================
  sound_i2s #(
      .CHANNEL_WIDTH(16),
      .SIGNED_INPUT (1)
  ) sound_i2s (
      .clk_74a  (clk_74a),
      .clk_audio(clk_sys),

      .audio_l(audio_l),
      .audio_r(audio_r),

      .audio_mclk(audio_mclk),
      .audio_lrck(audio_lrck),
      .audio_dac (audio_dac)
  );

endmodule
