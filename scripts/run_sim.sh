#!/bin/bash
# Icarus Verilog 仿真脚本（开源仿真工具）
# 使用方法: ./run_sim.sh [testbench_name]

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TB_NAME="${1:-tb_mac_unit}"

echo "=========================================="
echo "LLM Accelerator - Icarus Verilog Simulation"
echo "=========================================="
echo "Project Directory: ${PROJECT_DIR}"
echo "Testbench: ${TB_NAME}"
echo ""

# 检查iverilog是否安装
if ! command -v iverilog &> /dev/null; then
    echo "Error: Icarus Verilog (iverilog) not found"
    echo "Please install: sudo apt-get install iverilog"
    exit 1
fi

# 创建仿真目录
SIM_DIR="${PROJECT_DIR}/sim"
mkdir -p $SIM_DIR
cd $SIM_DIR

# 收集所有Verilog文件
RTL_FILES=""
for dir in utils attention ffn memory top; do
    if [ -d "${PROJECT_DIR}/rtl/${dir}" ]; then
        RTL_FILES="${RTL_FILES} ${PROJECT_DIR}/rtl/${dir}/*.v"
    fi
done

TB_FILE="${PROJECT_DIR}/tb/${TB_NAME}.v"

if [ ! -f "$TB_FILE" ]; then
    echo "Error: Testbench file not found: $TB_FILE"
    exit 1
fi

# 编译
echo "Compiling design..."
iverilog -g2012 -o ${TB_NAME}.vvp \
    -I${PROJECT_DIR}/rtl \
    $RTL_FILES \
    $TB_FILE

if [ $? -ne 0 ]; then
    echo "Compilation failed!"
    exit 1
fi

# 运行仿真
echo ""
echo "Running simulation..."
echo "=========================================="
vvp ${TB_NAME}.vvp

# 检查是否生成了VCD文件
if [ -f "${TB_NAME}.vcd" ]; then
    echo ""
    echo "=========================================="
    echo "Simulation completed successfully!"
    echo "VCD file: ${SIM_DIR}/${TB_NAME}.vcd"
    echo "View with: gtkwave ${SIM_DIR}/${TB_NAME}.vcd"
    echo "=========================================="
else
    echo ""
    echo "=========================================="
    echo "Simulation completed (no VCD generated)"
    echo "=========================================="
fi
