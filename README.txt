README

Instructions to generate .bit .hwh files below:

Make a folder somewhere called matmul_project, inside it make 4 empty folders:
matmul_project/build
matmul_project/ip
matmul_project/pynq
matmul_project/vivado

Run the CPP and header file on Vitis HLS, then export RTL as zip file. Then extract the contents of the RTL zip file under a new folder:
matmul_project/ip/matmul_stream

Also, copy the create_project.tcl file into matmul_project/vivado

After this, open vivado and then in the tcl console, type -
"source C:/Users/arjun/Desktop/matmul_project/vivado/create_project.tcl" (replace rest of path with whatever path from source is to matmul_project folder)

After running the TCL script, the .bit, .hwh files should be under matmul_project/pynq
These can be run on FPGA using the attached .ipynb notebook


