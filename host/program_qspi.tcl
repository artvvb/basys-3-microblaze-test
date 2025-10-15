set fpga_part {xc7a35t_0}
set qspi_part {mx25l3273f-spi-x1_x2_x4}

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target

set hw_device [lindex [get_hw_devices $fpga_part] 0]
set binfile [file join [file dirname [info script]] "random_data.bin"]

current_hw_device [get_hw_devices xc7a35t_0]
refresh_hw_device -update_hw_probes false ${hw_device}
create_hw_cfgmem -hw_device ${hw_device} -mem_dev [lindex [get_cfgmem_parts ${qspi_part}] 0]
set_property PROGRAM.BLANK_CHECK  0 [get_property PROGRAM.HW_CFGMEM ${hw_device}]
set_property PROGRAM.ERASE        1 [get_property PROGRAM.HW_CFGMEM ${hw_device}]
set_property PROGRAM.CFG_PROGRAM  1 [get_property PROGRAM.HW_CFGMEM ${hw_device}]
set_property PROGRAM.VERIFY       1 [get_property PROGRAM.HW_CFGMEM ${hw_device}]
set_property PROGRAM.CHECKSUM     0 [get_property PROGRAM.HW_CFGMEM ${hw_device}]
refresh_hw_device ${hw_device}

puts "INFO: Detected ${fpga_part} board and added ${qspi_part} config memory"

set_property PROGRAM.ADDRESS_RANGE {entire_device} [get_property PROGRAM.HW_CFGMEM ${hw_device}]
set_property PROGRAM.FILES [list $binfile] [get_property PROGRAM.HW_CFGMEM ${hw_device}]
set_property PROGRAM.PRM_FILE {} [get_property PROGRAM.HW_CFGMEM ${hw_device}]
set_property PROGRAM.UNUSED_PIN_TERMINATION {pull-none} [get_property PROGRAM.HW_CFGMEM ${hw_device}]
set_property PROGRAM.BLANK_CHECK    0 [get_property PROGRAM.HW_CFGMEM ${hw_device}]
set_property PROGRAM.ERASE          1 [get_property PROGRAM.HW_CFGMEM ${hw_device}]
set_property PROGRAM.CFG_PROGRAM    1 [get_property PROGRAM.HW_CFGMEM ${hw_device}]
set_property PROGRAM.VERIFY         1 [get_property PROGRAM.HW_CFGMEM ${hw_device}]
set_property PROGRAM.CHECKSUM       0 [get_property PROGRAM.HW_CFGMEM ${hw_device}]

puts "INFO: Configured QSPI programming"

startgroup 
create_hw_bitstream -hw_device ${hw_device} [get_property PROGRAM.HW_CFGMEM_BITFILE ${hw_device}]; program_hw_devices ${hw_device}; refresh_hw_device ${hw_device};
program_hw_cfgmem -hw_cfgmem [ get_property PROGRAM.HW_CFGMEM ${hw_device}]
endgroup

puts "QSPI programming complete"