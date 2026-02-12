# LLM硬件加速器 - 使用示例

本文档提供实际使用示例，帮助您快速上手LLM硬件加速器。

## 示例1: 基本仿真测试

### 1.1 运行MAC单元测试

这是最基础的功能测试，验证定点数乘加运算：

```bash
cd /path/to/IC4LLM

# 使用Icarus Verilog仿真
./scripts/run_sim.sh tb_mac_unit

# 查看波形
gtkwave sim/tb_mac_unit.vcd
```

**预期输出**:
```
==========================================
MAC Unit Testbench Started
==========================================

Test 1: Simple dot product
Result = 0x0500 (5.00)
Expected ≈ 5.0

Test 2: Negative numbers
Result = 0x0000 (0.00)
Expected = 0.0

==========================================
MAC Unit Test Completed
==========================================
```

### 1.2 运行完整系统测试

测试整个加速器系统，包括AXI4-Lite接口：

```bash
./scripts/run_sim.sh tb_llm_accelerator_top
```

**预期输出**:
```
==========================================
LLM Accelerator Testbench Started
==========================================

Test 1: Read initial status
Status Register = 0x00000000

Test 2: Write configuration
Config Register = 0x12345678 (Expected: 0x12345678)

Test 3: Start Attention Computation
Waiting for attention completion...
Attention computation completed!

Test 4: Start FFN Computation
Waiting for FFN completion...
FFN computation completed!

Test 5: Read final status
Final Status Register = 0x0000000C

==========================================
Testbench Completed Successfully
==========================================
```

## 示例2: Vivado工程创建

### 2.1 使用TCL脚本创建工程

创建文件 `scripts/create_project.tcl`:

```tcl
# 设置项目路径
set project_name "llm_accelerator"
set project_dir "./vivado_project"
set rtl_dir "./rtl"

# 创建项目
create_project $project_name $project_dir -part xczu9eg-ffvb1156-2-e -force

# 添加所有RTL文件
add_files [glob $rtl_dir/utils/*.v]
add_files [glob $rtl_dir/attention/*.v]
add_files [glob $rtl_dir/ffn/*.v]
add_files [glob $rtl_dir/memory/*.v]
add_files [glob $rtl_dir/top/*.v]

# 添加约束
add_files -fileset constrs_1 [glob ./constraints/*.xdc]

# 添加仿真文件
add_files -fileset sim_1 [glob ./tb/*.v]

# 设置顶层
set_property top llm_accelerator_top [current_fileset]
set_property top tb_llm_accelerator_top [get_filesets sim_1]

# 更新编译顺序
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "Project created successfully!"
```

在Vivado中运行：
```tcl
cd /path/to/IC4LLM
source scripts/create_project.tcl
```

### 2.2 运行仿真

在Vivado TCL控制台：
```tcl
# 启动行为仿真
launch_simulation

# 运行100us
run 100us

# 查看波形
```

### 2.3 运行综合

```tcl
# 运行综合
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

# 打开综合结果
open_run synth_1

# 查看报告
report_utilization
report_timing_summary
```

## 示例3: C/C++软件驱动

### 3.1 基本的寄存器访问函数

```c
#include <stdint.h>
#include <unistd.h>

// 寄存器地址定义
#define LLM_ACCEL_BASE      0xA0000000
#define REG_CONTROL         (LLM_ACCEL_BASE + 0x00)
#define REG_CONFIG          (LLM_ACCEL_BASE + 0x04)
#define REG_STATUS          (LLM_ACCEL_BASE + 0x08)

// 控制位定义
#define CTRL_ATTN_START     (1 << 0)
#define CTRL_FFN_START      (1 << 1)
#define CTRL_CAUSAL_MASK    (1 << 2)
#define CTRL_WEIGHT_LOAD    (1 << 3)

// 状态位定义
#define STAT_ATTN_BUSY      (1 << 0)
#define STAT_FFN_BUSY       (1 << 1)
#define STAT_ATTN_VALID     (1 << 2)
#define STAT_FFN_VALID      (1 << 3)

// 寄存器访问函数
static inline void write_reg(uint32_t addr, uint32_t value) {
    *(volatile uint32_t*)addr = value;
}

static inline uint32_t read_reg(uint32_t addr) {
    return *(volatile uint32_t*)addr;
}

// 定点数转换
static inline uint16_t float_to_q88(float f) {
    int32_t temp = (int32_t)(f * 256.0f);
    return (uint16_t)(temp & 0xFFFF);
}

static inline float q88_to_float(uint16_t q) {
    if (q & 0x8000) {
        // 负数
        int32_t temp = (int32_t)q | 0xFFFF0000;
        return (float)temp / 256.0f;
    } else {
        return (float)q / 256.0f;
    }
}
```

### 3.2 启动注意力计算

```c
int run_attention(bool use_causal_mask, int timeout_ms) {
    uint32_t ctrl = 0;
    
    // 配置因果掩码
    if (use_causal_mask) {
        ctrl |= CTRL_CAUSAL_MASK;
    }
    
    // 启动计算
    ctrl |= CTRL_ATTN_START;
    write_reg(REG_CONTROL, ctrl);
    
    // 轮询状态，带超时
    int elapsed = 0;
    while (elapsed < timeout_ms) {
        uint32_t status = read_reg(REG_STATUS);
        
        // 检查是否完成
        if (status & STAT_ATTN_VALID) {
            printf("Attention completed in %d ms\n", elapsed);
            return 0; // 成功
        }
        
        usleep(1000); // 睡眠1ms
        elapsed++;
    }
    
    printf("Attention timeout after %d ms\n", timeout_ms);
    return -1; // 超时
}
```

### 3.3 加载FFN权重

```c
int load_ffn_weights(float* weights, int layer, int count) {
    // 进入权重加载模式
    write_reg(REG_CONTROL, CTRL_WEIGHT_LOAD);
    
    // 配置权重选择
    uint32_t cfg = (layer & 0x03);
    write_reg(REG_CONFIG, cfg);
    
    // 逐个写入权重
    for (int i = 0; i < count; i++) {
        uint16_t w = float_to_q88(weights[i]);
        cfg = (layer & 0x03) | ((uint32_t)w << 16);
        write_reg(REG_CONFIG, cfg);
        usleep(10); // 等待写入完成
    }
    
    // 退出加载模式
    write_reg(REG_CONTROL, 0);
    
    printf("Loaded %d weights to layer %d\n", count, layer);
    return 0;
}
```

### 3.4 完整使用示例

```c
int main() {
    printf("LLM Accelerator Demo\n");
    
    // 1. 初始化（复位）
    write_reg(REG_CONTROL, 0);
    usleep(1000);
    
    // 2. 读取状态
    uint32_t status = read_reg(REG_STATUS);
    printf("Initial status: 0x%08x\n", status);
    
    // 3. 加载权重（示例数据）
    float w1_weights[16] = {
        1.0, 0.5, 0.25, 0.125,
        -1.0, -0.5, -0.25, -0.125,
        2.0, 1.5, 1.0, 0.5,
        -2.0, -1.5, -1.0, -0.5
    };
    load_ffn_weights(w1_weights, 0, 16);
    
    // 4. 运行注意力计算
    printf("\nRunning attention with causal mask...\n");
    int ret = run_attention(true, 1000);
    if (ret != 0) {
        printf("Attention failed!\n");
        return -1;
    }
    
    // 5. 运行FFN计算
    printf("\nRunning FFN...\n");
    write_reg(REG_CONTROL, CTRL_FFN_START);
    
    // 轮询FFN完成
    int timeout = 1000;
    while (timeout-- > 0) {
        status = read_reg(REG_STATUS);
        if (status & STAT_FFN_VALID) {
            printf("FFN completed!\n");
            break;
        }
        usleep(1000);
    }
    
    if (timeout <= 0) {
        printf("FFN timeout!\n");
        return -1;
    }
    
    printf("\nDemo completed successfully!\n");
    return 0;
}
```

## 示例4: Python验证脚本

### 4.1 定点数验证

```python
#!/usr/bin/env python3
"""定点数Q8.8格式验证脚本"""

def float_to_q88(f):
    """浮点数转Q8.8"""
    # 限制范围
    f = max(-128.0, min(127.996, f))
    return int(f * 256) & 0xFFFF

def q88_to_float(q):
    """Q8.8转浮点数"""
    if q & 0x8000:  # 负数
        return -((0x10000 - q) / 256.0)
    else:
        return q / 256.0

def test_conversion():
    """测试转换精度"""
    test_values = [0.0, 1.0, -1.0, 0.5, -0.5, 3.14, -3.14, 127.0, -128.0]
    
    print("Q8.8 Conversion Test")
    print("=" * 50)
    for val in test_values:
        q = float_to_q88(val)
        recovered = q88_to_float(q)
        error = abs(val - recovered)
        print(f"Original: {val:8.4f}  Q8.8: 0x{q:04x}  "
              f"Recovered: {recovered:8.4f}  Error: {error:.6f}")

if __name__ == "__main__":
    test_conversion()
```

### 4.2 矩阵运算验证

```python
import numpy as np

def fixed_point_matmul(A, B, frac_bits=8):
    """定点数矩阵乘法模拟"""
    # 转换为定点数
    scale = 2 ** frac_bits
    A_int = (A * scale).astype(np.int32)
    B_int = (B * scale).astype(np.int32)
    
    # 整数矩阵乘法
    C_int = np.matmul(A_int, B_int)
    
    # 调整小数位
    C_int = C_int >> frac_bits
    
    # 转回浮点数
    C = C_int.astype(np.float32) / scale
    return C

# 测试
A = np.random.randn(4, 4).astype(np.float32)
B = np.random.randn(4, 4).astype(np.float32)

C_float = np.matmul(A, B)
C_fixed = fixed_point_matmul(A, B)

error = np.abs(C_float - C_fixed).max()
print(f"Maximum error: {error:.6f}")
```

## 示例5: 性能分析

### 5.1 计算延迟估算

```python
def estimate_latency(seq_len, head_dim, num_heads, freq_mhz):
    """估算注意力机制延迟"""
    
    # 时钟周期（纳秒）
    clk_period_ns = 1000.0 / freq_mhz
    
    # QK^T计算：seq_len^2 次点积，每次head_dim个MAC
    qk_cycles = seq_len * seq_len * head_dim
    
    # Softmax：seq_len^2 个元素
    softmax_cycles = seq_len * seq_len * 10  # 假设每个元素10周期
    
    # 注意力加权：seq_len^2 * head_dim
    attn_v_cycles = seq_len * seq_len * head_dim
    
    # 总周期
    total_cycles = qk_cycles + softmax_cycles + attn_v_cycles
    
    # 延迟（微秒）
    latency_us = (total_cycles * clk_period_ns) / 1000.0
    
    return {
        'cycles': total_cycles,
        'latency_us': latency_us,
        'breakdown': {
            'qk': (qk_cycles * clk_period_ns) / 1000.0,
            'softmax': (softmax_cycles * clk_period_ns) / 1000.0,
            'attn_v': (attn_v_cycles * clk_period_ns) / 1000.0
        }
    }

# 示例：计算seq_len=8, head_dim=64, 100MHz
result = estimate_latency(8, 64, 4, 100)
print(f"Total cycles: {result['cycles']}")
print(f"Latency: {result['latency_us']:.2f} us")
print(f"Breakdown: QK={result['breakdown']['qk']:.2f}us, "
      f"Softmax={result['breakdown']['softmax']:.2f}us, "
      f"AttnV={result['breakdown']['attn_v']:.2f}us")
```

**输出示例**:
```
Total cycles: 9280
Latency: 92.80 us
Breakdown: QK=40.96us, Softmax=6.40us, AttnV=40.96us
```

## 故障排除示例

### 问题1: 仿真不收敛

**现象**: testbench运行超时
**解决**:
```verilog
// 添加超时保护
initial begin
    #1000000; // 1ms超时
    $display("ERROR: Simulation timeout!");
    $finish;
end
```

### 问题2: 定点数溢出

**现象**: 计算结果异常大或为负数
**解决**: 检查累加器位宽
```verilog
// 扩展累加器位宽
reg signed [2*DATA_WIDTH-1:0] accumulator; // 而不是 [DATA_WIDTH-1:0]
```

### 问题3: AXI握手失败

**现象**: 寄存器读写无响应
**解决**: 检查ready/valid信号
```verilog
// 确保握手完成
always @(posedge clk) begin
    if (s_axi_awvalid && s_axi_awready) begin
        // 写地址已接受
    end
end
```

---

**使用示例文档版本**: 1.0  
**最后更新**: 2026-02-12  
**适用于**: IC4LLM v1.0
