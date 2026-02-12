/*******************************************************************************
* Module: tb_systolic_array
* Description: 脉动阵列矩阵乘法器测试平台
* Author: AI Hardware Accelerator Engineer
* Date: 2026-02-12
*******************************************************************************/

`timescale 1ns / 1ps

module tb_systolic_array;

    parameter CLK_PERIOD = 10;
    parameter DATA_WIDTH = 16;
    parameter FRAC_WIDTH = 8;
    parameter ARRAY_SIZE = 4;  // 使用4x4阵列便于测试
    
    reg                                 clk;
    reg                                 rst_n;
    reg                                 en;
    reg                                 weight_load_en;
    reg  [ARRAY_SIZE*DATA_WIDTH-1:0]    weight_data;
    reg  [ARRAY_SIZE*DATA_WIDTH-1:0]    activation_in;
    wire [ARRAY_SIZE*DATA_WIDTH-1:0]    result_out;
    wire                                valid;
    
    // 实例化DUT
    systolic_array #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH),
        .ARRAY_SIZE(ARRAY_SIZE)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .en(en),
        .weight_load_en(weight_load_en),
        .weight_data(weight_data),
        .activation_in(activation_in),
        .result_out(result_out),
        .valid(valid)
    );
    
    // 时钟生成
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // 辅助函数
    function [DATA_WIDTH-1:0] float_to_q88;
        input real f;
        begin
            float_to_q88 = $signed($rtoi(f * 256.0));
        end
    endfunction
    
    function real q88_to_float;
        input [DATA_WIDTH-1:0] q;
        begin
            q88_to_float = $signed(q) / 256.0;
        end
    endfunction
    
    integer i, row, col;
    reg [DATA_WIDTH-1:0] weights [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    reg [DATA_WIDTH-1:0] activations [0:ARRAY_SIZE-1];
    reg [DATA_WIDTH-1:0] results [0:ARRAY_SIZE-1];
    
    initial begin
        // 初始化
        rst_n = 0;
        en = 0;
        weight_load_en = 0;
        weight_data = 0;
        activation_in = 0;
        
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 5);
        
        $display("========================================");
        $display("Systolic Array Testbench");
        $display("Array Size: %0dx%0d", ARRAY_SIZE, ARRAY_SIZE);
        $display("========================================");
        
        // 测试1: 单位矩阵乘法
        $display("\nTest 1: Identity matrix multiplication");
        $display("W = I (identity), A = [1, 2, 3, 4]");
        $display("Expected result: [1, 2, 3, 4]");
        
        // 加载单位矩阵作为权重
        weight_load_en = 1;
        for (row = 0; row < ARRAY_SIZE; row = row + 1) begin
            for (col = 0; col < ARRAY_SIZE; col = col + 1) begin
                if (row == col) begin
                    weights[row][col] = float_to_q88(1.0);
                    weight_data[col*DATA_WIDTH +: DATA_WIDTH] = weights[row][col];
                end else begin
                    weights[row][col] = float_to_q88(0.0);
                    weight_data[col*DATA_WIDTH +: DATA_WIDTH] = weights[row][col];
                end
            end
            #CLK_PERIOD;
        end
        weight_load_en = 0;
        
        #(CLK_PERIOD * 5);
        
        // 输入激活值
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            activations[i] = float_to_q88(i + 1.0);
            activation_in[i*DATA_WIDTH +: DATA_WIDTH] = activations[i];
        end
        
        // 启动计算
        en = 1;
        
        // 等待结果有效
        wait(valid);
        #(CLK_PERIOD * 2);
        en = 0;
        
        // 提取并显示结果
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            results[i] = result_out[i*DATA_WIDTH +: DATA_WIDTH];
            $display("  result[%0d] = %f (expected: %f)", 
                     i, q88_to_float(results[i]), i + 1.0);
        end
        
        #(CLK_PERIOD * 20);
        
        // 测试2: 全1矩阵乘法
        $display("\nTest 2: All-ones matrix multiplication");
        $display("W = ones, A = [1, 1, 1, 1]");
        $display("Expected result: [4, 4, 4, 4]");
        
        // 加载全1权重矩阵
        weight_load_en = 1;
        for (row = 0; row < ARRAY_SIZE; row = row + 1) begin
            for (col = 0; col < ARRAY_SIZE; col = col + 1) begin
                weights[row][col] = float_to_q88(1.0);
                weight_data[col*DATA_WIDTH +: DATA_WIDTH] = weights[row][col];
            end
            #CLK_PERIOD;
        end
        weight_load_en = 0;
        
        #(CLK_PERIOD * 5);
        
        // 输入全1激活值
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            activations[i] = float_to_q88(1.0);
            activation_in[i*DATA_WIDTH +: DATA_WIDTH] = activations[i];
        end
        
        en = 1;
        wait(valid);
        #(CLK_PERIOD * 2);
        en = 0;
        
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            results[i] = result_out[i*DATA_WIDTH +: DATA_WIDTH];
            $display("  result[%0d] = %f (expected: 4.0)", 
                     i, q88_to_float(results[i]));
        end
        
        #(CLK_PERIOD * 20);
        
        // 测试3: 递增矩阵
        $display("\nTest 3: Incremental weight matrix");
        
        weight_load_en = 1;
        for (row = 0; row < ARRAY_SIZE; row = row + 1) begin
            for (col = 0; col < ARRAY_SIZE; col = col + 1) begin
                weights[row][col] = float_to_q88((row * ARRAY_SIZE + col) * 0.1);
                weight_data[col*DATA_WIDTH +: DATA_WIDTH] = weights[row][col];
            end
            #CLK_PERIOD;
        end
        weight_load_en = 0;
        
        #(CLK_PERIOD * 5);
        
        // 输入递增激活值
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            activations[i] = float_to_q88(i * 0.5);
            activation_in[i*DATA_WIDTH +: DATA_WIDTH] = activations[i];
        end
        
        en = 1;
        wait(valid);
        #(CLK_PERIOD * 2);
        en = 0;
        
        $display("  Results:");
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            results[i] = result_out[i*DATA_WIDTH +: DATA_WIDTH];
            $display("  result[%0d] = %f", i, q88_to_float(results[i]));
        end
        
        #(CLK_PERIOD * 20);
        
        $display("\n========================================");
        $display("Systolic Array Test Completed");
        $display("========================================");
        
        $finish;
    end
    
    // 波形记录
    initial begin
        $dumpfile("tb_systolic_array.vcd");
        $dumpvars(0, tb_systolic_array);
    end
    
    // 超时保护
    initial begin
        #(CLK_PERIOD * 10000);
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule
