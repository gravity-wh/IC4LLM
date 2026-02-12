#!/bin/bash
# Vivado 综合脚本 - Batch模式
# 使用方法: ./run_vivado_synth.sh

# 设置Vivado路径（根据实际安装路径调整）
VIVADO_PATH="/tools/Xilinx/Vivado/2023.1"
VIVADO_BIN="${VIVADO_PATH}/bin/vivado"

# 检查Vivado是否存在
if [ ! -f "$VIVADO_BIN" ]; then
    echo "Error: Vivado not found at $VIVADO_BIN"
    echo "Please update VIVADO_PATH in this script"
    exit 1
fi

# 设置工程路径
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VIVADO_DIR="${PROJECT_DIR}/vivado_project"

echo "=========================================="
echo "LLM Accelerator - Vivado Synthesis"
echo "=========================================="
echo "Project Directory: ${PROJECT_DIR}"
echo "Vivado Directory: ${VIVADO_DIR}"
echo ""

# 创建TCL脚本
TCL_SCRIPT="${PROJECT_DIR}/scripts/synth.tcl"

cat > $TCL_SCRIPT << 'EOF'
# Vivado TCL综合脚本

# 设置工程路径
set project_dir [file dirname [file dirname [info script]]]
set vivado_dir "${project_dir}/vivado_project"

# 创建工程
create_project llm_accelerator ${vivado_dir} -part xczu9eg-ffvb1156-2-e -force

# 添加RTL源文件
add_files -norecurse [glob ${project_dir}/rtl/utils/*.v]
add_files -norecurse [glob ${project_dir}/rtl/attention/*.v]
add_files -norecurse [glob ${project_dir}/rtl/ffn/*.v]
add_files -norecurse [glob ${project_dir}/rtl/memory/*.v]
add_files -norecurse [glob ${project_dir}/rtl/top/*.v]

# 添加约束文件
add_files -fileset constrs_1 -norecurse ${project_dir}/constraints/timing.xdc
add_files -fileset constrs_1 -norecurse ${project_dir}/constraints/physical.xdc

# 设置顶层模块
set_property top llm_accelerator_top [current_fileset]

# 更新编译顺序
update_compile_order -fileset sources_1

# 综合设置
set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY rebuilt [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING true [get_runs synth_1]

# 运行综合
puts "=========================================="
puts "Starting Synthesis..."
puts "=========================================="
launch_runs synth_1 -jobs 8
wait_on_run synth_1

# 打开综合后设计
open_run synth_1

# 生成报告
puts "Generating reports..."
file mkdir ${project_dir}/reports
report_utilization -file ${project_dir}/reports/utilization_post_synth.rpt
report_timing_summary -file ${project_dir}/reports/timing_post_synth.rpt
report_power -file ${project_dir}/reports/power_post_synth.rpt

# 检查时序
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "=========================================="
puts "Synthesis Complete"
puts "Worst Negative Slack (Setup): $wns ns"
puts "=========================================="

if {$wns < 0} {
    puts "WARNING: Timing constraints not met!"
    exit 1
} else {
    puts "SUCCESS: All timing constraints met"
    exit 0
}
EOF

# 运行Vivado
echo "Starting Vivado in batch mode..."
$VIVADO_BIN -mode batch -source $TCL_SCRIPT -log ${PROJECT_DIR}/vivado_synth.log

# 检查结果
if [ $? -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo "Synthesis completed successfully!"
    echo "Check reports in: ${PROJECT_DIR}/reports/"
    echo "=========================================="
else
    echo ""
    echo "=========================================="
    echo "Synthesis failed. Check log file:"
    echo "${PROJECT_DIR}/vivado_synth.log"
    echo "=========================================="
    exit 1
fi
