# =============================================================================
# SDC Timing Constraints - Timer/Counter Subsystem
# =============================================================================

# Clock definition (100 MHz)
create_clock -name clk -period 10.0 [get_ports clk]

# Input clock uncertainty
set_clock_uncertainty 0.5 [get_clocks clk]

# Input delay (relative to clock edge)
set_input_delay -clock clk -max 2.0 [get_ports {paddr[*]}]
set_input_delay -clock clk -min 0.5 [get_ports {paddr[*]}]
set_input_delay -clock clk -max 2.0 [get_ports {psel}]
set_input_delay -clock clk -min 0.5 [get_ports {psel}]
set_input_delay -clock clk -max 2.0 [get_ports {penable}]
set_input_delay -clock clk -min 0.5 [get_ports {penable}]
set_input_delay -clock clk -max 2.0 [get_ports {pwrite}]
set_input_delay -clock clk -min 0.5 [get_ports {pwrite}]
set_input_delay -clock clk -max 2.0 [get_ports {pwdata[*]}]
set_input_delay -clock clk -min 0.5 [get_ports {pwdata[*]}]
set_input_delay -clock clk -max 2.0 [get_ports {capture_in[*]}]
set_input_delay -clock clk -min 0.5 [get_ports {capture_in[*]}]
set_input_delay -clock clk -max 2.0 [get_ports {rst_n}]
set_input_delay -clock clk -min 0.5 [get_ports {rst_n}]

# Output delay
set_output_delay -clock clk -max 2.0 [get_ports {prdata[*]}]
set_output_delay -clock clk -min 0.5 [get_ports {prdata[*]}]
set_output_delay -clock clk -max 2.0 [get_ports {pready}]
set_output_delay -clock clk -min 0.5 [get_ports {pready}]
set_output_delay -clock clk -max 2.0 [get_ports {pslverr}]
set_output_delay -clock clk -min 0.5 [get_ports {pslverr}]
set_output_delay -clock clk -max 2.0 [get_ports {pwm_out[*]}]
set_output_delay -clock clk -min 0.5 [get_ports {pwm_out[*]}]
set_output_delay -clock clk -max 2.0 [get_ports {irq}]
set_output_delay -clock clk -min 0.5 [get_ports {irq}]

# Clock gating check
set_clock_gating_check -setup 0.5 -hold 0.1 [get_clocks clk]

# Max capacitance
set_max_capacitance 0.5 [get_ports {prdata[*]}]

# Max transition
set_max_transition 0.5 [current_design]

# Drive strength
set_driving_cell -lib_cell INV_X1 [get_ports {clk}]
set_driving_cell -lib_cell INV_X1 [get_ports {rst_n}]
set_driving_cell -lib_cell BUF_X2 [get_ports {paddr[*]}]
set_driving_cell -lib_cell BUF_X2 [get_ports {psel}]
set_driving_cell -lib_cell BUF_X2 [get_ports {penable}]
set_driving_cell -lib_cell BUF_X2 [get_ports {pwrite}]
set_driving_cell -lib_cell BUF_X2 [get_ports {pwdata[*]}]
set_driving_cell -lib_cell BUF_X2 [get_ports {capture_in[*]}]

# False paths
set_false_path -from [get_ports rst_n]

# Multicycle paths (if applicable)
# set_multicycle_path 2 -setup -from [get_pins u_reg_block/*/D] -to [get_pins u_reg_block/*/Q]

# Don't touch cells
# set_dont_touch [get_cells u_reg_block]

# Group paths for reporting
group_path -name "reg_to_reg" -from [get_pins -of [get_cells u_*/* -filter "@ref_name == DFF*"]] -to [get_pins -of [get_cells u_*/* -filter "@ref_name == DFF*"]]
