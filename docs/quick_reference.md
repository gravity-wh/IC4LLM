# LLM硬件加速器 - 快速参考手册

## 寄存器映射速查表

### AXI4-Lite地址空间

| 偏移地址 | 寄存器名 | 类型 | 复位值 | 描述 |
|---------|---------|------|--------|------|
| 0x00 | CONTROL | R/W | 0x0 | 控制寄存器 |
| 0x04 | CONFIG | R/W | 0x0 | 配置寄存器 |
| 0x08 | STATUS | R | - | 状态寄存器 |

### CONTROL寄存器 (0x00)

| 位 | 名称 | 访问 | 描述 |
|----|------|------|------|
| [0] | attn_start | W | 启动注意力计算（写1触发） |
| [1] | ffn_start | W | 启动FFN计算（写1触发） |
| [2] | causal_mask_en | R/W | 因果掩码使能（1=启用） |
| [3] | weight_load_mode | R/W | 权重加载模式（1=加载中） |
| [31:4] | Reserved | - | 保留位 |

### CONFIG寄存器 (0x04)

| 位 | 名称 | 访问 | 描述 |
|----|------|------|------|
| [1:0] | weight_select | R/W | 权重选择：0=W1, 1=W2, 2=b1, 3=b2 |
| [31:16] | weight_data | R/W | 权重数据（Q8.8格式） |

### STATUS寄存器 (0x08)

| 位 | 名称 | 访问 | 描述 |
|----|------|------|------|
| [0] | attn_busy | R | 注意力计算忙（1=运行中） |
| [1] | ffn_busy | R | FFN计算忙（1=运行中） |
| [2] | attn_valid | R | 注意力计算完成（1=有效结果） |
| [3] | ffn_valid | R | FFN计算完成（1=有效结果） |
| [31:4] | Reserved | - | 保留位 |

## 操作流程

### 启动注意力计算

```c
// 伪代码示例
void start_attention(bool use_causal_mask) {
    // 1. 配置因果掩码
    uint32_t ctrl = use_causal_mask ? 0x04 : 0x00;
    
    // 2. 启动计算
    ctrl |= 0x01;
    write_reg(ADDR_CONTROL, ctrl);
    
    // 3. 轮询状态
    while (!(read_reg(ADDR_STATUS) & 0x04)) {
        // 等待attn_valid
    }
    
    // 4. 读取结果（从数据接口）
}
```

### 加载FFN权重

```c
void load_ffn_weights(float* weights, int layer, int count) {
    // 1. 进入权重加载模式
    write_reg(ADDR_CONTROL, 0x08);
    
    // 2. 选择权重类型
    uint32_t cfg = (layer & 0x03);
    
    // 3. 逐个写入权重
    for (int i = 0; i < count; i++) {
        uint16_t w = float_to_q88(weights[i]);
        cfg = (cfg & 0x03) | (w << 16);
        write_reg(ADDR_CONFIG, cfg);
        usleep(1); // 等待写入
    }
    
    // 4. 退出加载模式
    write_reg(ADDR_CONTROL, 0x00);
}
```

## 数据格式转换

### Q8.8定点数

```python
def float_to_q88(f):
    """浮点数转Q8.8定点数"""
    return int(f * 256) & 0xFFFF

def q88_to_float(q):
    """Q8.8定点数转浮点数"""
    if q & 0x8000:  # 负数
        return -(0x10000 - q) / 256.0
    else:
        return q / 256.0

# 示例
print(hex(float_to_q88(1.0)))    # 0x0100
print(hex(float_to_q88(0.5)))    # 0x0080
print(hex(float_to_q88(-1.0)))   # 0xff00
print(q88_to_float(0x0100))      # 1.0
```

### 向量打包

```python
def pack_vector(vec, data_width=16):
    """将向量打包为字节流"""
    packed = 0
    for i, val in enumerate(vec):
        packed |= (val & ((1 << data_width) - 1)) << (i * data_width)
    return packed

def unpack_vector(packed, vec_size, data_width=16):
    """从字节流解包向量"""
    mask = (1 << data_width) - 1
    vec = []
    for i in range(vec_size):
        val = (packed >> (i * data_width)) & mask
        vec.append(val)
    return vec
```

## 性能计算公式

### 注意力机制延迟

```
T_attention = T_qk + T_softmax + T_attn_v

T_qk = L² * d_k / throughput_mac
T_softmax = L² * cycles_per_softmax
T_attn_v = L² * d_v / throughput_mac
```

其中：
- L = 序列长度
- d_k, d_v = 键/值维度
- throughput_mac = MAC单元吞吐量

### FFN延迟

```
T_ffn = T_fc1 + T_gelu + T_fc2

T_fc1 = d_model * d_hidden / throughput_mac
T_gelu = d_hidden * cycles_per_gelu
T_fc2 = d_hidden * d_model / throughput_mac
```

### 吞吐量估算

```
Throughput = Batch_Size * Seq_Len / (T_attention + T_ffn) [tokens/sec]
```

## 常用Vivado TCL命令

```tcl
# 快速综合
launch_runs synth_1 -jobs 8
wait_on_run synth_1

# 查看资源使用
report_utilization

# 查看时序
report_timing_summary

# 查看功耗
report_power

# 导出网表
write_verilog -force post_synth.v

# 查看关键路径
report_timing -max_paths 10 -nworst 10

# 设置时钟频率
create_clock -period 10.0 [get_ports clk]
```

## 调试技巧

### 使用$display跟踪状态

```verilog
always @(posedge clk) begin
    if (state != next_state) begin
        $display("Time=%0t: State %d -> %d", $time, state, next_state);
    end
end
```

### 添加断言

```verilog
// 检查有效信号时序
always @(posedge clk) begin
    if (valid && !busy) begin
        $error("Invalid state: valid without busy at time %0t", $time);
    end
end
```

### 波形分析要点

1. **检查握手协议**
   - valid/ready信号配对
   - 数据稳定性

2. **状态机转换**
   - 是否按预期流转
   - 有无死锁

3. **数据流动**
   - MAC输入输出匹配
   - 累加器清零时机

## 故障排除

| 症状 | 可能原因 | 解决方案 |
|------|---------|---------|
| 综合失败 | 语法错误 | 检查Vivado日志 |
| 时序违例 | 关键路径过长 | 增加流水线/降频 |
| 仿真不收敛 | 状态机死锁 | 添加超时保护 |
| 结果错误 | 定点数溢出 | 检查位宽配置 |
| 资源不足 | 设计过大 | 减小参数规模 |

## 联系方式

- GitHub Issues: https://github.com/gravity-wh/IC4LLM/issues
- 技术文档: `/docs` 目录

---

**快速参考手册版本**: 1.0  
**最后更新**: 2026-02-12
