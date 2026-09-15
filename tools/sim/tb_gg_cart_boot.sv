// SPDX-License-Identifier: GPL-3.0-or-later
// gg_cart_boot against gg_cart_model through gg_cart_bus: the bytes that come
// out must be the cartridge's image, in order, for every size the header can
// name, and for a cartridge with no header at all.
`timescale 1ns/1ps
`default_nettype none
module tb;
  reg clk = 0; always #9.312 clk = ~clk;
  reg reset = 1, start = 0;

  wire bus_req, bus_wr, bus_done, bus_busy, bus_rejected, write_active;
  wire [15:0] bus_addr; wire [7:0] bus_wdata, bus_rdata;
  wire [15:0] e_ad_out; wire e_ad_oe; wire [7:0] e_hi_out, e_hi_in; wire e_hi_oe;
  wire [3:0] e_ctl_out; wire e_p30_out, e_p30_oe;
  wire out_wr; wire [24:0] out_addr; wire [7:0] out_data;
  wire busy, done, header_ok; wire [3:0] size_code, state; wire [31:0] size_bytes;

  gg_cart_bus #(.ADDR_SETUP_CYCLES(2), .STROBE_CYCLES(3), .HOLD_CYCLES(2)) bus (
    .clk(clk), .reset(reset), .gg_mode(1'b1), .req(bus_req), .wr(bus_wr), .addr(bus_addr),
    .wdata(bus_wdata), .rdata(bus_rdata), .done(bus_done), .busy(bus_busy),
    .write_active(write_active), .rejected(bus_rejected),
    .e_ad_out(e_ad_out), .e_ad_oe(e_ad_oe), .e_hi_out(e_hi_out), .e_hi_oe(e_hi_oe),
    .e_hi_in(e_hi_in), .e_ctl_out(e_ctl_out), .e_p30_out(e_p30_out), .e_p30_oe(e_p30_oe));

  localparam integer ROM_BYTES = 524288;
  gg_cart_model #(.ROM_BYTES(ROM_BYTES)) cart (
    .e_ad_out(e_ad_out), .e_ad_oe(e_ad_oe), .e_hi_out(e_hi_out), .e_hi_oe(e_hi_oe),
    .e_ctl_out(e_ctl_out), .e_p30_out(e_p30_out), .e_p30_oe(e_p30_oe), .e_hi_in(e_hi_in));

  gg_cart_boot dut (
    .clk(clk), .reset(reset), .start(start),
    .bus_req(bus_req), .bus_wr(bus_wr), .bus_addr(bus_addr), .bus_wdata(bus_wdata),
    .bus_rdata(bus_rdata), .bus_done(bus_done), .bus_busy(bus_busy),
    .out_wr(out_wr), .out_addr(out_addr), .out_data(out_data),
    .busy(busy), .done(done), .header_ok(header_ok), .size_code(size_code),
    .size_bytes(size_bytes), .state(state));

  reg [7:0] got [0:ROM_BYTES-1];
  integer count, i, fails = 0, rejected = 0;
  always @(posedge clk) begin
    if (out_wr) begin
      if (out_addr != count) begin $display("FAIL out of order: got addr %0h want %0h", out_addr, count); fails = fails + 1; end
      got[out_addr] = out_data;
      count = count + 1;
    end
    if (bus_done && bus_rejected) rejected = rejected + 1;
  end

  task load(input integer bytes, input [3:0] code, input integer with_header);
    integer k;
    begin
      for (k = 0; k < ROM_BYTES; k = k + 1) cart.rom[k] = (k * 7 + (k >> 9) + bytes) & 8'hFF;
      if (with_header) begin
        cart.rom[16'h7FF0] = "T"; cart.rom[16'h7FF1] = "M"; cart.rom[16'h7FF2] = "R"; cart.rom[16'h7FF3] = " ";
        cart.rom[16'h7FF4] = "S"; cart.rom[16'h7FF5] = "E"; cart.rom[16'h7FF6] = "G"; cart.rom[16'h7FF7] = "A";
        cart.rom[16'h7FFF] = {4'h6, code};
      end
    end
  endtask

  task run(input integer bytes, input [3:0] code, input integer with_header, input integer want_ok);
    begin
      count = 0;
      reset = 1; repeat (4) @(posedge clk); reset = 0; repeat (4) @(posedge clk);
      start = 1; @(posedge clk); start = 0;
      wait (done); repeat (4) @(posedge clk);
      if (count != bytes) begin $display("FAIL size %0d: emitted %0d bytes", bytes, count); fails = fails + 1; end
      if (size_bytes != bytes) begin $display("FAIL size_bytes %0d want %0d", size_bytes, bytes); fails = fails + 1; end
      if (header_ok != want_ok) begin $display("FAIL header_ok %0d want %0d", header_ok, want_ok); fails = fails + 1; end
      for (i = 0; i < bytes; i = i + 1)
        if (got[i] !== cart.rom[i % ROM_BYTES]) begin
          if (fails < 8) $display("FAIL byte %0h: got %02x want %02x", i, got[i], cart.rom[i]);
          fails = fails + 1;
        end
      $display("size %0d code %0h header %0d: %0d bytes, header_ok=%0d, mapper writes %0d, rejected %0d",
               bytes, code, with_header, count, header_ok, cart.mapper_write_count, rejected);
    end
  endtask

  initial begin
    #1;
    load(524288, 4'h1, 1); run(524288, 4'h1, 1, 1);
    load(131072, 4'hF, 1); run(131072, 4'hF, 1, 1);
    load(32768,  4'hC, 1); run(32768,  4'hC, 1, 1);
    load(65536,  4'hE, 1); run(65536,  4'hE, 1, 1);
    load(524288, 4'h0, 0); run(524288, 4'h1, 0, 0);   // no header: 512 KB, code 1
    if (cart.save_write_count != 0 || cart.eeprom_enable_count != 0) begin
      $display("FAIL: cartridge saw a data-window write or an EEPROM enable"); fails = fails + 1; end
    $display(fails == 0 ? "PASS" : "FAIL");
    $finish;
  end
endmodule
`default_nettype wire
