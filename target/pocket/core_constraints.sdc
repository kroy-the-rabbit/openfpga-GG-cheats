#
# User core constraints for the Pocket Game Gear core.
#
# platform/pocket/apf_constraints.sdc creates clk_74a, clk_74b and
# bridge_spiclk, runs derive_pll_clocks and then reads this file.
#
# `ic` is the core_top instance inside apf_top; `mp1` is mf_pllbase inside it.
# general[0] is clk_sys at 53.693181 MHz, general[1] is clk_vid at 5.369318 MHz
# and general[2] is clk_vid shifted 90 degrees.
#

# ------------------------------------------------------------------------------
# SDRAM clock.
#
# gg_core forwards it through a DDR output register with datain_h = 0 and
# datain_l = 1, so the part sees a clock inverted with respect to clk_sys: the
# SDRAM samples half a clk_sys period after the address and command change,
# which is where the 9.3 ns of margin comes from. Declared before the clock
# groups below so the fitter has it during timing-driven placement.
# ------------------------------------------------------------------------------
create_generated_clock -name sdram_clk -invert \
    -source [get_pins {ic|mp1|mf_pllbase_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] \
    [get_ports {dram_clk}]

# ------------------------------------------------------------------------------
# Clock groups.
#
# The three PLL outputs are deliberately in ONE group, not three. clk_vid is
# exactly clk_sys / 10 out of the same VCO and core_top hands the picture
# across that boundary once per pixel, so the transfer is a real timing path
# and putting the two in separate asynchronous groups would stop the analyser
# ever looking at it. sdram_clk belongs to the same group for the same reason.
# ------------------------------------------------------------------------------
set_clock_groups -asynchronous \
    -group { bridge_spiclk } \
    -group { clk_74a } \
    -group { clk_74b } \
    -group { ic|mp1|mf_pllbase_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk \
             ic|mp1|mf_pllbase_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk \
             ic|mp1|mf_pllbase_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk \
             sdram_clk }

# ------------------------------------------------------------------------------
# SDRAM interface timing.
#
# Numbers for the 512 Mbit x16 part the Pocket carries, from its data sheet:
# tDS 1.5 ns and tDH 0.8 ns into the chip, tAC 6.0 ns and tOH 2.5 ns out of it.
# The controller runs at 53.693181 MHz, half the rate the same numbers are met
# at elsewhere in this tree, so there should be margin; whether there is, is
# one of the things the P0 report answers. See docs/BASELINE.md.
# ------------------------------------------------------------------------------
set sdram_outputs [get_ports {dram_a[*] dram_ba[*] dram_dq[*] dram_dqm[*] \
                              dram_ras_n dram_cas_n dram_we_n dram_cke}]

set_output_delay -clock sdram_clk -max  1.5 $sdram_outputs
set_output_delay -clock sdram_clk -min -0.8 $sdram_outputs

set_input_delay -clock sdram_clk -max 6.0 [get_ports {dram_dq[*]}]
set_input_delay -clock sdram_clk -min 2.5 [get_ports {dram_dq[*]}]

# Read data is registered three clk_sys cycles after the READ command is issued
# and CAS latency is two, so the capture has a whole cycle in hand. Without
# this the analyser assumes the very next edge.
set_multicycle_path -setup 2 -from [get_clocks {sdram_clk}] -to [get_clocks {*general[0].gpll*}]
set_multicycle_path -hold  1 -from [get_clocks {sdram_clk}] -to [get_clocks {*general[0].gpll*}]
