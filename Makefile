# =============================================================================
# Makefile - Timer/Counter Subsystem
# =============================================================================

# Tool paths
IVERILOG    ?= iverilog
VVP         ?= vvp
YOSYS       ?= yosys
PYTHON      ?= python3
OPENROAD    ?= openroad

# Directory paths
RTL_DIR     := rtl
TB_DIR      := tb
SYNTH_DIR   := synth
SIM_DIR     := sim
PY_DIR      := python

# Design parameters
NUM_CHANNELS := 4
WIDTH        := 32

# RTL sources
RTL_SRCS := $(RTL_DIR)/prescaler.sv \
            $(RTL_DIR)/counter.sv \
            $(RTL_DIR)/compare_unit.sv \
            $(RTL_DIR)/pwm_generator.sv \
            $(RTL_DIR)/input_capture.sv \
            $(RTL_DIR)/cascade_unit.sv \
            $(RTL_DIR)/register_block.sv \
            $(RTL_DIR)/interrupt_controller.sv \
            $(RTL_DIR)/timer_top.sv

TB_SRCS := $(TB_DIR)/timer_tb.sv \
           $(TB_DIR)/agents/apb_bfm.sv

ASSERT_SRCS := $(TB_DIR)/assertions/timer_assertions.sv

# =============================================================================
# Targets
# =============================================================================

.PHONY: all clean sim sim_assert synth yosys test test_python help

all: test

# Create output directories
$(SIM_DIR)/results $(SIM_DIR)/logs $(SYNTH_DIR)/output:
	mkdir -p $@

# =============================================================================
# Simulation
# =============================================================================

sim: $(SIM_DIR)/results $(SIM_DIR)/logs
	@echo "=== Compiling RTL + Testbench ==="
	$(IVERILOG) -g2012 \
		-DNUM_CHANNELS=$(NUM_CHANNELS) \
		-DWIDTH=$(WIDTH) \
		-I $(RTL_DIR) \
		$(RTL_SRCS) $(TB_SRCS) \
		-o $(SIM_DIR)/results/timer_tb.vvp 2>&1 | tee $(SIM_DIR)/logs/compile.log
	@echo "=== Running Simulation ==="
	$(VVP) $(SIM_DIR)/results/timer_tb.vvp 2>&1 | tee $(SIM_DIR)/logs/sim.log
	@echo "=== Simulation Complete ==="

sim_assert: $(SIM_DIR)/results $(SIM_DIR)/logs
	@echo "=== Compiling with Assertions ==="
	$(IVERILOG) -g2012 \
		-DNUM_CHANNELS=$(NUM_CHANNELS) \
		-DWIDTH=$(WIDTH) \
		-I $(RTL_DIR) \
		$(RTL_SRCS) $(TB_SRCS) $(ASSERT_SRCS) \
		-o $(SIM_DIR)/results/timer_tb_assert.vvp 2>&1 | tee $(SIM_DIR)/logs/compile_assert.log
	@echo "=== Running with Assertions ==="
	$(VVP) $(SIM_DIR)/results/timer_tb_assert.vvp 2>&1 | tee $(SIM_DIR)/logs/sim_assert.log
	@echo "=== Assertion Run Complete ==="

# =============================================================================
# Python Golden Model
# =============================================================================

test_python:
	@echo "=== Running Python Golden Model Tests ==="
	$(PYTHON) -m pytest $(PY_DIR) -q
	$(PYTHON) $(PY_DIR)/timer_golden_model.py
	@echo "=== Python Tests Complete ==="

# =============================================================================
# Synthesis (Yosys)
# =============================================================================

synth: yosys

yosys: $(SYNTH_DIR)/output $(SIM_DIR)/logs
	@echo "=== Running Yosys Synthesis ==="
	cd $(SYNTH_DIR) && $(YOSYS) -s synth_yosys.ys 2>&1 | tee ../$(SIM_DIR)/logs/yosys.log
	@echo "=== Synthesis Complete ==="

# =============================================================================
# OpenROAD (requires PDK)
# =============================================================================

openroad: synth
	@echo "=== Running OpenROAD ==="
	$(OPENROAD) -exit $(SYNTH_DIR)/openroad/floorplan.tcl 2>&1 | tee $(SIM_DIR)/logs/openroad.log
	@echo "=== OpenROAD Complete ==="

# =============================================================================
# Combined Tests
# =============================================================================

test: test_python sim
	@echo ""
	@echo "=========================================="
	@echo "  All tests completed successfully!"
	@echo "=========================================="

test_all: test_python sim sim_assert yosys
	@echo ""
	@echo "=========================================="
	@echo "  Full test suite completed!"
	@echo "=========================================="

# =============================================================================
# Clean
# =============================================================================

clean:
	rm -rf $(SIM_DIR)/results $(SIM_DIR)/logs
	rm -rf $(SYNTH_DIR)/output
	rm -rf $(PY_DIR)/__pycache__
	rm -f *.vvp *.vcd

# =============================================================================
# Help
# =============================================================================

help:
	@echo "Timer/Counter Subsystem - Build System"
	@echo ""
	@echo "Targets:"
	@echo "  make test        - Run Python model + RTL simulation (default)"
	@echo "  make test_all    - Full suite: Python + sim + assertions + synthesis"
	@echo "  make sim         - Compile and run RTL simulation"
	@echo "  make sim_assert  - Compile and run with assertion monitor"
	@echo "  make test_python - Run Python golden model"
	@echo "  make yosys       - Run Yosys synthesis"
	@echo "  make openroad    - Run OpenROAD (requires PDK)"
	@echo "  make clean       - Remove all generated files"
	@echo ""
	@echo "Parameters:"
	@echo "  NUM_CHANNELS=$(NUM_CHANNELS)  WIDTH=$(WIDTH)"
	@echo "  Override with: make NUM_CHANNELS=8 WIDTH=64"
