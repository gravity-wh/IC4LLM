/*******************************************************************************
* Module: tb_softmax_unit
* Description: Softmax单元的测试平台
* Author: AI Hardware Accelerator Engineer
* Date: 2026-02-12
*******************************************************************************/

`timescale 1ns / 1ps

module tb_softmax_unit;

    parameter CLK_PERIOD = 10;
    parameter DATA_WIDTH = 16;
    parameter FRAC_WIDTH = 8;
    parameter VEC_SIZE = 8;
    
    reg                             clk;
    reg                             rst_n;
    reg                             start;
    reg  [VEC_SIZE*DATA_WIDTH-1:0]  x_in;
    wire [VEC_SIZE*DATA_WIDTH-1:0]  y_out;
    wire                            valid;
    
    // 实例化DUT
    softmax_unit #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH),
        .VEC_SIZE(VEC_SIZE)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .x_in(x_in),
        .y_out(y_out),
        .valid(valid)
    );
    
    // 时钟生成
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // 辅助函数：浮点数转Q8.8
    function [DATA_WIDTH-1:0] float_to_q88;
        input real f;
        begin
            float_to_q88 = $signed($rtoi(f * 256.0));
        end
    endfunction
    
    // 辅助函数：Q8.8转浮点数
    function real q88_to_float;
        input [DATA_WIDTH-1:0] q;
        begin
            q88_to_float = $signed(q) / 256.0;
        end
    endfunction
    
    // 测试向量
    integer i;
    reg signed [DATA_WIDTH-1:0] x_array [0:VEC_SIZE-1];
    reg signed [DATA_WIDTH-1:0] y_array [0:VEC_SIZE-1];
    real sum;
    
    initial begin
        // 初始化
        rst_n = 0;
        start = 0;
        x_in = 0;
        
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 5);
        
        $display("========================================");
        $display("Softmax Unit Testbench Started");
        $display("========================================");
        
        // 测试1: 均匀分布输入
        $display("\nTest 1: Uniform distribution");
        // x = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
        // 期望：每个输出约为 1/8 = 0.125
        for (i = 0; i < VEC_SIZE; i = i + 1) begin
            x_array[i] = float_to_q88(1.0);
            x_in[i*DATA_WIDTH +: DATA_WIDTH] = x_array[i];
        end
        
        start = 1;
        #CLK_PERIOD;
        start = 0;
        
        wait(valid);
        #(CLK_PERIOD * 2);
        
        // 提取结果
        sum = 0.0;
        for (i = 0; i < VEC_SIZE; i = i + 1) begin
            y_array[i] = y_out[i*DATA_WIDTH +: DATA_WIDTH];
            sum = sum + q88_to_float(y_array[i]);
            $display("  y[%0d] = %f (0x%04h)", i, q88_to_float(y_array[i]), y_array[i]);
        end
        $display("  Sum = %f (Expected: 1.0)", sum);
        
        #(CLK_PERIOD * 10);
        
        // 测试2: 递增序列
        $display("\nTest 2: Increasing sequence");
        // x = [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5]
        // 较大的值应该有较大的softmax输出
        for (i = 0; i < VEC_SIZE; i = i + 1) begin
            x_array[i] = float_to_q88(i * 0.5);
            x_in[i*DATA_WIDTH +: DATA_WIDTH] = x_array[i];
        end
        
        start = 1;
        #CLK_PERIOD;
        start = 0;
        
        wait(valid);
        #(CLK_PERIOD * 2);
        
        sum = 0.0;
        for (i = 0; i < VEC_SIZE; i = i + 1) begin
            y_array[i] = y_out[i*DATA_WIDTH +: DATA_WIDTH];
            sum = sum + q88_to_float(y_array[i]);
            $display("  y[%0d] = %f (0x%04h)", i, q88_to_float(y_array[i]), y_array[i]);
        end
        $display("  Sum = %f (Expected: 1.0)", sum);
        
        #(CLK_PERIOD * 10);
        
        // 测试3: 单个最大值
        $display("\nTest 3: Single maximum");
        // x = [0, 0, 0, 5.0, 0, 0, 0, 0]
        // 期望：y[3] 应该接近 1.0，其他接近 0
        for (i = 0; i < VEC_SIZE; i = i + 1) begin
            if (i == 3)
                x_array[i] = float_to_q88(5.0);
            else
                x_array[i] = float_to_q88(0.0);
            x_in[i*DATA_WIDTH +: DATA_WIDTH] = x_array[i];
        end
        
        start = 1;
        #CLK_PERIOD;
        start = 0;
        
        wait(valid);
        #(CLK_PERIOD * 2);
        
        sum = 0.0;
        for (i = 0; i < VEC_SIZE; i = i + 1) begin
            y_array[i] = y_out[i*DATA_WIDTH +: DATA_WIDTH];
            sum = sum + q88_to_float(y_array[i]);
            $display("  y[%0d] = %f (0x%04h)", i, q88_to_float(y_array[i]), y_array[i]);
        end
        $display("  Sum = %f (Expected: 1.0)", sum);
        $display("  y[3] should be close to 1.0");
        
        #(CLK_PERIOD * 10);
        
        // 测试4: 负值输入
        $display("\nTest 4: Negative values");
        // x = [-2, -1, 0, 1, 2, 3, 4, 5]
        for (i = 0; i < VEC_SIZE; i = i + 1) begin
            x_array[i] = float_to_q88(i - 2.0);
            x_in[i*DATA_WIDTH +: DATA_WIDTH] = x_array[i];
        end
        
        start = 1;
        #CLK_PERIOD;
        start = 0;
        
        wait(valid);
        #(CLK_PERIOD * 2);
        
        sum = 0.0;
        for (i = 0; i < VEC_SIZE; i = i + 1) begin
            y_array[i] = y_out[i*DATA_WIDTH +: DATA_WIDTH];
            sum = sum + q88_to_float(y_array[i]);
            $display("  y[%0d] = %f (0x%04h)", i, q88_to_float(y_array[i]), y_array[i]);
        end
        $display("  Sum = %f (Expected: 1.0)", sum);
        
        #(CLK_PERIOD * 20);
        
        $display("\n========================================");
        $display("Softmax Unit Test Completed");
        $display("========================================");
        
        $finish;
    end
    
    // 波形记录
    initial begin
        $dumpfile("tb_softmax_unit.vcd");
        $dumpvars(0, tb_softmax_unit);
    end
    
    // 超时保护
    initial begin
        #(CLK_PERIOD * 10000);
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule
