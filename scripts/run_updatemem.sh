#! bash
# run from context of top level of repo
updatemem -force -meminfo ./hw/proj/hw.runs/impl_1/design_1_wrapper.mmi -data ./sw/ws/app_component/build/app_component.elf -proc design_1_i/microblaze_0 -bit ./hw/proj/hw.runs/impl_1/design_1_wrapper.bit -out ./host/top_out.bit
cp ./hw/proj/hw.runs/impl_1/design_1_wrapper.ltx ./host/design_1_wrapper.ltx