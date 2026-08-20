# =============================================================================
# OpenROAD Floorplan Script - Timer/Counter Subsystem
# =============================================================================
# Usage: openroad synth/openroad/floorplan.tcl

# Read design
read_lef technology.lef
read_def synth/output/timer_top.def

# Initialize floorplan
initialize_floorplan \
    -core_utilization 0.6 \
    -core_aspect_ratio 1.0 \
    -left_margin 20.0 \
    -right_margin 20.0 \
    -top_margin 20.0 \
    -bottom_margin 20.0

# Add tap cells
add_tap_cells -prefix TAP -cell_name FILLCELL_X1 -distance 30

# Add power rails
add_power_domains

# Global placement
global_placement -overflow 0.15 -density 0.7

# CTS (Clock Tree Synthesis)
clock_tree_synthesis \
    -buf_list {CLKBUF_X1 CLKBUF_X2 CLKBUF_X4} \
    -root_buf CLKBUF_X4 \
    -wire_unit 20

# Route global signals
global_routing

# Detailed routing
detailed_routing

# Repair design
repair_design

# Write results
write_def synth/openroad/results/timer_top_routed.def
write_verilog synth/openroad/results/timer_top_routed.v

# Report
report_design_area
report_design_power
report_timing
