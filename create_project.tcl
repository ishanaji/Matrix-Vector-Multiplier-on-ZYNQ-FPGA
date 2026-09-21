# create_project.tcl -- Vivado project for Matrix Multiplication
# Usage: source this file from Vivado TCL console

# ---------- Configuration ----------
set PROJ_NAME   "matmul"
set PROJ_DIR    "C:/Vivado_Projects/matmul_project/build"
set PART        "xc7z020clg400-1"
set MATMUL_IP   "C:/Vivado_Projects/matmul_project/ip/matmul_stream"

# ---------- Create project ----------
create_project ${PROJ_NAME} ${PROJ_DIR}/${PROJ_NAME} -part ${PART} -force

# Add HLS IP repository
set_property ip_repo_paths [list ${MATMUL_IP}] [current_project]
update_ip_catalog

# ---------- Create block design ----------
create_bd_design "matmul_design"

# -- Zynq PS --
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7
apply_bd_automation \
    -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" Master "Disable" Slave "Disable"} \
    [get_bd_cells ps7]

# Enable HP0 for DMA memory access, 100MHz clock
set_property -dict [list \
    CONFIG.PCW_USE_S_AXI_HP0          {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
] [get_bd_cells ps7]

# -- AXI DMA (simple mode, no scatter-gather) --
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0
set_property -dict [list \
    CONFIG.c_include_sg               {0} \
    CONFIG.c_sg_include_stscntrl_strm {0} \
    CONFIG.c_mm2s_burst_size          {256} \
    CONFIG.c_s2mm_burst_size          {256} \
    CONFIG.c_sg_length_width          {26} \
] [get_bd_cells axi_dma_0]

# -- matmul_stream IP --
# NOTE: if this line errors, open IP Catalog, find your IP,
# right-click -> Copy VLNV to Clipboard, and paste it below
create_bd_cell -type ip -vlnv xilinx.com:hls:matmul_stream:1.0 matmul_stream_0

# ---------- Stream Connections ----------
# PS sends input vector x -> matmul via DMA
connect_bd_intf_net \
    [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] \
    [get_bd_intf_pins matmul_stream_0/in_stream]

# matmul sends result y -> PS via DMA
connect_bd_intf_net \
    [get_bd_intf_pins matmul_stream_0/out_stream] \
    [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]

# ---------- AXI Lite Control ----------
# DMA control -> PS GP0 (creates AXI interconnect automatically)
apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
    -config {
        Clk_master  "Auto"
        Clk_slave   "Auto"
        Clk_xbar    "Auto"
        Master      "/ps7/M_AXI_GP0"
        Slave       "/axi_dma_0/S_AXI_LITE"
        intc_ip     "New AXI Interconnect"
        master_apm  "0"
    } [get_bd_intf_pins axi_dma_0/S_AXI_LITE]

# matmul control (A matrix, rows, cols, num_vectors) -> PS GP0
apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
    -config {
        Master      "/ps7/M_AXI_GP0"
        Slave       "/matmul_stream_0/s_axi_control"
        intc_ip     "/ps7_axi_periph"
        master_apm  "0"
    } [get_bd_intf_pins matmul_stream_0/s_axi_control]

# ---------- DMA Memory Ports -> HP0 ----------
apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
    -config {
        Master      "/axi_dma_0/M_AXI_MM2S"
        Slave       "/ps7/S_AXI_HP0"
        intc_ip     "New AXI Interconnect"
        master_apm  "0"
    } [get_bd_intf_pins ps7/S_AXI_HP0]

apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
    -config {
        Master      "/axi_dma_0/M_AXI_S2MM"
        Slave       "/ps7/S_AXI_HP0"
        intc_ip     "/axi_mem_intercon"
        master_apm  "0"
    } [get_bd_intf_pins axi_dma_0/M_AXI_S2MM]

# ---------- Validate and Save ----------
regenerate_bd_layout
validate_bd_design
save_bd_design

# ---------- Generate Wrapper ----------
make_wrapper -files [get_files matmul_design.bd] -top
add_files -norecurse \
    ${PROJ_DIR}/${PROJ_NAME}/${PROJ_NAME}.gen/sources_1/bd/matmul_design/hdl/matmul_design_wrapper.v

# ---------- Run Synthesis and Implementation ----------
launch_runs synth_1 -jobs 4
wait_on_run synth_1

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

# ---------- Copy outputs ----------
set BIT_FILE \
    [get_property DIRECTORY [get_runs impl_1]]/matmul_design_wrapper.bit
set HWH_DIR \
    ${PROJ_DIR}/${PROJ_NAME}/${PROJ_NAME}.gen/sources_1/bd/matmul_design/hw_handoff

file mkdir "C:/Vivado_Projects/matmul_project/pynq"
file copy -force ${BIT_FILE} \
    "C:/Vivado_Projects/matmul_project/pynq/matmul_design.bit"
file copy -force ${HWH_DIR}/matmul_design.hwh \
    "C:/Vivado_Projects/matmul_project/pynq/matmul_design.hwh"

puts "====================================="
puts "Done! Files copied to pynq/ folder."
puts "====================================="