#!/bin/bash
# 完整测试套件运行脚本
# 运行所有testbench并生成报告

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SIM_DIR="${PROJECT_DIR}/sim"
REPORT_FILE="${SIM_DIR}/test_report.txt"

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================"
echo "LLM加速器完整测试套件"
echo "========================================"
echo ""

# 检查iverilog
if ! command -v iverilog &> /dev/null; then
    echo -e "${RED}错误: 未找到Icarus Verilog (iverilog)${NC}"
    echo "请安装: sudo apt-get install iverilog"
    exit 1
fi

# 创建仿真目录
mkdir -p $SIM_DIR
cd $SIM_DIR

# 测试列表
TESTS=(
    "tb_mac_unit"
    "tb_softmax_unit"
    "tb_systolic_array"
    "tb_attention_core"
    "tb_llm_accelerator_top"
)

# 初始化报告
echo "LLM硬件加速器测试报告" > $REPORT_FILE
echo "生成时间: $(date)" >> $REPORT_FILE
echo "========================================" >> $REPORT_FILE
echo "" >> $REPORT_FILE

# 统计变量
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# 收集RTL文件
RTL_FILES=""
for dir in utils attention ffn memory top; do
    if [ -d "${PROJECT_DIR}/rtl/${dir}" ]; then
        RTL_FILES="${RTL_FILES} ${PROJECT_DIR}/rtl/${dir}/*.v"
    fi
done

# 运行每个测试
for TEST in "${TESTS[@]}"; do
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    TB_FILE="${PROJECT_DIR}/tb/${TEST}.v"
    
    if [ ! -f "$TB_FILE" ]; then
        echo -e "${RED}✗ ${TEST}: 测试文件未找到${NC}"
        echo "${TEST}: SKIP (文件未找到)" >> $REPORT_FILE
        continue
    fi
    
    echo -e "${YELLOW}运行测试: ${TEST}${NC}"
    
    # 编译
    iverilog -g2012 -o ${TEST}.vvp \
        -I${PROJECT_DIR}/rtl \
        $RTL_FILES \
        $TB_FILE 2>&1 | tee ${TEST}_compile.log
    
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        echo -e "${RED}✗ ${TEST}: 编译失败${NC}"
        echo "${TEST}: FAIL (编译错误)" >> $REPORT_FILE
        echo "  查看日志: ${SIM_DIR}/${TEST}_compile.log" >> $REPORT_FILE
        FAILED_TESTS=$((FAILED_TESTS + 1))
        continue
    fi
    
    # 运行仿真
    timeout 60s vvp ${TEST}.vvp > ${TEST}_sim.log 2>&1
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 124 ]; then
        echo -e "${RED}✗ ${TEST}: 超时${NC}"
        echo "${TEST}: FAIL (超时)" >> $REPORT_FILE
        FAILED_TESTS=$((FAILED_TESTS + 1))
    elif [ $EXIT_CODE -ne 0 ]; then
        echo -e "${RED}✗ ${TEST}: 运行失败${NC}"
        echo "${TEST}: FAIL (运行时错误)" >> $REPORT_FILE
        FAILED_TESTS=$((FAILED_TESTS + 1))
    else
        # 检查是否有ERROR关键字
        if grep -q "ERROR" ${TEST}_sim.log; then
            echo -e "${RED}✗ ${TEST}: 发现错误${NC}"
            echo "${TEST}: FAIL (检测到错误)" >> $REPORT_FILE
            FAILED_TESTS=$((FAILED_TESTS + 1))
        else
            echo -e "${GREEN}✓ ${TEST}: 通过${NC}"
            echo "${TEST}: PASS" >> $REPORT_FILE
            PASSED_TESTS=$((PASSED_TESTS + 1))
        fi
    fi
    
    # 添加仿真日志摘要
    echo "  日志摘要:" >> $REPORT_FILE
    tail -n 10 ${TEST}_sim.log | sed 's/^/    /' >> $REPORT_FILE
    echo "" >> $REPORT_FILE
done

# 生成总结
echo "" >> $REPORT_FILE
echo "========================================" >> $REPORT_FILE
echo "测试总结" >> $REPORT_FILE
echo "========================================" >> $REPORT_FILE
echo "总计测试: $TOTAL_TESTS" >> $REPORT_FILE
echo "通过: $PASSED_TESTS" >> $REPORT_FILE
echo "失败: $FAILED_TESTS" >> $REPORT_FILE
echo "跳过: $((TOTAL_TESTS - PASSED_TESTS - FAILED_TESTS))" >> $REPORT_FILE

# 显示总结
echo ""
echo "========================================"
echo "测试总结"
echo "========================================"
echo -e "总计测试: $TOTAL_TESTS"
echo -e "${GREEN}通过: $PASSED_TESTS${NC}"
if [ $FAILED_TESTS -gt 0 ]; then
    echo -e "${RED}失败: $FAILED_TESTS${NC}"
else
    echo -e "失败: $FAILED_TESTS"
fi
echo ""
echo "详细报告: ${REPORT_FILE}"
echo "波形文件: ${SIM_DIR}/*.vcd"
echo ""

# 退出状态
if [ $FAILED_TESTS -gt 0 ]; then
    echo -e "${RED}测试失败！${NC}"
    exit 1
else
    echo -e "${GREEN}所有测试通过！${NC}"
    exit 0
fi
