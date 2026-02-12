# 验证与测试完整指南

## 测试覆盖范围

本项目提供了完整的验证测试套件，覆盖从基础运算单元到完整系统的各个层次。

### 测试文件清单

| 测试文件 | 测试目标 | 覆盖功能 |
|---------|---------|---------|
| `tb_mac_unit.v` | MAC单元 | 向量点积、定点数运算、累加器 |
| `tb_softmax_unit.v` | Softmax单元 | 在线算法、归一化、数值稳定性 |
| `tb_systolic_array.v` | 脉动阵列 | 矩阵乘法、权重加载、数据流 |
| `tb_attention_core.v` | 注意力机制 | QK^T计算、因果掩码、端到端流程 |
| `tb_llm_accelerator_top.v` | 完整系统 | AXI接口、控制流、系统集成 |

## 快速开始

### 运行单个测试

```bash
# MAC单元测试
./scripts/run_sim.sh tb_mac_unit

# Softmax单元测试
./scripts/run_sim.sh tb_softmax_unit

# 脉动阵列测试
./scripts/run_sim.sh tb_systolic_array

# 注意力核心测试
./scripts/run_sim.sh tb_attention_core

# 完整系统测试
./scripts/run_sim.sh tb_llm_accelerator_top
```

### 运行完整测试套件

```bash
# 运行所有测试并生成报告
./scripts/run_all_tests.sh

# 查看测试报告
cat sim/test_report.txt

# 查看波形
gtkwave sim/tb_mac_unit.vcd
```

## 测试详解

### 1. MAC单元测试 (tb_mac_unit.v)

**测试目的**: 验证乘加累加单元的基本功能

**测试用例**:
- 简单点积: `[1,2,3,4] · [0.5,0.5,0.5,0.5] = 5.0`
- 负数计算: `[-1,1,-1,1] · [1,1,1,1] = 0.0`

**预期结果**:
```
Test 1: Simple dot product
Result = 0x0500 (5.00)
Expected ≈ 5.0

Test 2: Negative numbers
Result = 0x0000 (0.00)
Expected = 0.0
```

### 2. Softmax单元测试 (tb_softmax_unit.v)

**测试目的**: 验证Softmax归一化的正确性和数值稳定性

**测试用例**:
1. 均匀分布: 所有输入相同，输出应均为1/N
2. 递增序列: 较大值应有较大的概率
3. 单个最大值: 最大值位置概率接近1.0
4. 负值输入: 测试数值稳定性

**关键检查点**:
- 输出和为1.0（归一化）
- 最大值位置获得最高概率
- 无数值溢出或下溢

### 3. 脉动阵列测试 (tb_systolic_array.v)

**测试目的**: 验证Weight-Stationary脉动阵列的矩阵乘法

**测试用例**:
1. 单位矩阵: `I × [1,2,3,4] = [1,2,3,4]`
2. 全1矩阵: `ones × [1,1,1,1] = [4,4,4,4]`
3. 递增矩阵: 验证一般矩阵乘法

**数据流验证**:
- 权重正确加载到PE
- 激活值从左向右流动
- 部分和从上向下累加

### 4. 注意力机制测试 (tb_attention_core.v)

**测试目的**: 端到端验证注意力计算流程

**测试用例**:
1. 单位矩阵测试: Q=K=I, V=ones
2. 因果掩码测试: 验证自回归掩码
3. 全零输入: 边界条件测试

**计算流程验证**:
```
输入(Q,K,V) → QK^T → 缩放 → 掩码 → Softmax → 加权和 → 输出
```

**关键检查点**:
- QK^T矩阵计算正确
- 因果掩码正确应用（上三角为负无穷）
- Softmax归一化
- 最终输出维度正确

### 5. 系统级测试 (tb_llm_accelerator_top.v)

**测试目的**: 验证AXI接口和系统集成

**测试流程**:
1. 读取初始状态寄存器
2. 写入配置寄存器
3. 启动注意力计算
4. 轮询状态直到完成
5. 启动FFN计算
6. 读取最终状态

**AXI事务验证**:
- 写地址/数据握手
- 读地址/数据握手
- 响应信号正确
- 寄存器读写一致性

## 波形分析

### 查看波形

```bash
# 使用GTKWave查看
gtkwave sim/tb_attention_core.vcd

# 推荐监控的信号
# - 时钟和复位: clk, rst_n
# - 状态机: state, next_state
# - 控制信号: start, valid, busy
# - 数据路径: q_in, k_in, v_in, attn_out
```

### 关键波形特征

1. **状态机转换**:
   ```
   IDLE → CALC_QK → SCALE_QK → APPLY_MASK → CALC_SOFTMAX → CALC_ATTN_V → DONE
   ```

2. **握手协议**:
   - `start` 上升沿触发
   - `busy` 保持高电平
   - `valid` 脉冲表示完成

3. **数据流动**:
   - MAC单元输入稳定
   - 累加器正确清零
   - 结果按序输出

## 性能基准

### 延迟测试

运行性能测试并记录延迟：

```verilog
// 在testbench中添加计时
integer start_time, end_time;

start_time = $time;
start = 1;
#CLK_PERIOD;
start = 0;

wait(valid);
end_time = $time;

$display("延迟: %0d ns (%0d cycles)", 
         end_time - start_time, 
         (end_time - start_time) / CLK_PERIOD);
```

**参考延迟** (SEQ_LEN=8, HEAD_DIM=64, @100MHz):
- MAC单元: ~10ns (1周期)
- Softmax (VEC_SIZE=8): ~1μs
- 注意力机制: ~93μs
- FFN层: ~52μs

### 资源使用

综合后查看资源报告：
```bash
./scripts/run_vivado_synth.sh
cat reports/utilization_post_synth.rpt
```

## 调试技巧

### 添加调试输出

```verilog
// 在关键位置添加$display
always @(posedge clk) begin
    if (state != next_state) begin
        $display("Time=%0t: State %d->%d", $time, state, next_state);
    end
end

// 监控数据
always @(posedge clk) begin
    if (valid) begin
        $display("Output: 0x%h", attn_out);
    end
end
```

### 使用断言

```verilog
// 检查握手协议
always @(posedge clk) begin
    if (valid && !busy) begin
        $error("Invalid state at %0t", $time);
        $finish;
    end
end
```

### 波形对比

1. 记录正确的黄金参考波形
2. 修改代码后重新仿真
3. 使用GTKWave对比两个波形文件

## 持续集成

### GitHub Actions示例

创建 `.github/workflows/test.yml`:

```yaml
name: Run Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Install Icarus Verilog
        run: sudo apt-get install -y iverilog
      
      - name: Run Tests
        run: ./scripts/run_all_tests.sh
      
      - name: Upload Test Report
        if: always()
        uses: actions/upload-artifact@v2
        with:
          name: test-report
          path: sim/test_report.txt
```

## 覆盖率分析

### 功能覆盖率

手动检查清单：

- [ ] 所有状态机状态都被访问
- [ ] 所有分支条件都被测试
- [ ] 边界条件测试（最大/最小值）
- [ ] 错误情况处理
- [ ] 超时保护机制

### 代码覆盖率

使用Verilator进行覆盖率分析：

```bash
# 安装Verilator
sudo apt-get install verilator

# 生成覆盖率报告
verilator --coverage --cc rtl/top/llm_accelerator_top.v
```

## 故障排查

### 常见问题

| 问题 | 可能原因 | 解决方案 |
|------|---------|---------|
| 仿真不收敛 | 状态机死锁 | 检查状态转移条件 |
| 结果错误 | 定点数溢出 | 增加位宽或调整缩放 |
| 编译失败 | 语法错误 | 查看编译日志 |
| 波形异常 | 时序违例 | 检查时钟约束 |

### 获取帮助

1. 查看测试日志: `sim/*_sim.log`
2. 检查编译日志: `sim/*_compile.log`
3. 查看波形文件: `sim/*.vcd`
4. 参考文档: `docs/`

---

**文档版本**: 2.0  
**最后更新**: 2026-02-12  
**测试套件版本**: 1.0
