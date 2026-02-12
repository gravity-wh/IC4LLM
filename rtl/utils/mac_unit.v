/*******************************************************************************
* Module: mac_unit
* Description: 乘加累加单元 (Multiply-Accumulate Unit)
*              支持向量点积计算：result = a[0]*b[0] + a[1]*b[1] + ... + a[n-1]*b[n-1]
* Author: AI Hardware Accelerator Engineer
* Date: 2026-02-12
*******************************************************************************/

module mac_unit #(
    parameter DATA_WIDTH = 16,
    parameter FRAC_WIDTH = 8,
    parameter VEC_SIZE = 8
)(
    input  wire                             clk,
    input  wire                             rst_n,
    input  wire                             en,
    input  wire                             clear_acc,
    input  wire [VEC_SIZE*DATA_WIDTH-1:0]   a_vec,
    input  wire [VEC_SIZE*DATA_WIDTH-1:0]   b_vec,
    output reg  [DATA_WIDTH-1:0]            result,
    output reg                              valid
);

    // 展开向量输入
    wire [DATA_WIDTH-1:0] a [0:VEC_SIZE-1];
    wire [DATA_WIDTH-1:0] b [0:VEC_SIZE-1];
    
    genvar i;
    generate
        for (i = 0; i < VEC_SIZE; i = i + 1) begin : vec_unpack
            assign a[i] = a_vec[i*DATA_WIDTH +: DATA_WIDTH];
            assign b[i] = b_vec[i*DATA_WIDTH +: DATA_WIDTH];
        end
    endgenerate
    
    // 乘法结果
    reg signed [2*DATA_WIDTH-1:0] mult_results [0:VEC_SIZE-1];
    reg signed [2*DATA_WIDTH-1:0] sum;
    reg signed [2*DATA_WIDTH-1:0] accumulator;
    
    integer j;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (j = 0; j < VEC_SIZE; j = j + 1) begin
                mult_results[j] <= 0;
            end
            sum <= 0;
            accumulator <= 0;
            result <= 0;
            valid <= 0;
        end else if (en) begin
            // 计算所有乘法
            for (j = 0; j < VEC_SIZE; j = j + 1) begin
                mult_results[j] <= $signed(a[j]) * $signed(b[j]);
            end
            
            // 累加所有乘法结果
            sum = 0;
            for (j = 0; j < VEC_SIZE; j = j + 1) begin
                sum = sum + mult_results[j];
            end
            
            // 累加器逻辑
            if (clear_acc) begin
                accumulator <= sum;
            end else begin
                accumulator <= accumulator + sum;
            end
            
            // 调整小数位并输出
            result <= accumulator[DATA_WIDTH+FRAC_WIDTH-1:FRAC_WIDTH];
            valid <= 1'b1;
        end else begin
            valid <= 1'b0;
        end
    end

endmodule
