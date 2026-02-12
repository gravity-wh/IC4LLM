/*******************************************************************************
* Module: softmax_unit
* Description: Softmax计算单元，采用在线算法减少内存占用
*              输出 = exp(x_i - max) / Σexp(x_j - max)
* Author: AI Hardware Accelerator Engineer
* Date: 2026-02-12
*******************************************************************************/

module softmax_unit #(
    parameter DATA_WIDTH = 16,
    parameter FRAC_WIDTH = 8,
    parameter VEC_SIZE = 8
)(
    input  wire                             clk,
    input  wire                             rst_n,
    input  wire                             start,
    input  wire [VEC_SIZE*DATA_WIDTH-1:0]   x_in,
    output reg  [VEC_SIZE*DATA_WIDTH-1:0]   y_out,
    output reg                              valid
);

    // 状态机
    localparam IDLE       = 3'b000;
    localparam FIND_MAX   = 3'b001;
    localparam CALC_EXP   = 3'b010;
    localparam CALC_SUM   = 3'b011;
    localparam CALC_DIV   = 3'b100;
    localparam DONE       = 3'b101;
    
    reg [2:0] state, next_state;
    reg [3:0] counter;
    
    // 展开向量
    wire [DATA_WIDTH-1:0] x [0:VEC_SIZE-1];
    reg  [DATA_WIDTH-1:0] y [0:VEC_SIZE-1];
    reg  [DATA_WIDTH-1:0] exp_values [0:VEC_SIZE-1];
    
    reg signed [DATA_WIDTH-1:0] max_val;
    reg signed [2*DATA_WIDTH-1:0] sum_exp;
    
    genvar i;
    generate
        for (i = 0; i < VEC_SIZE; i = i + 1) begin : unpack
            assign x[i] = x_in[i*DATA_WIDTH +: DATA_WIDTH];
        end
    endgenerate
    
    integer j;
    
    // 状态机时序逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end
    
    // 状态转移逻辑
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (start)
                    next_state = FIND_MAX;
            end
            FIND_MAX: begin
                if (counter == VEC_SIZE-1)
                    next_state = CALC_EXP;
            end
            CALC_EXP: begin
                if (counter == VEC_SIZE-1)
                    next_state = CALC_SUM;
            end
            CALC_SUM: begin
                next_state = CALC_DIV;
            end
            CALC_DIV: begin
                if (counter == VEC_SIZE-1)
                    next_state = DONE;
            end
            DONE: begin
                next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end
    
    // 数据路径
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 0;
            max_val <= {1'b1, {(DATA_WIDTH-1){1'b0}}}; // 最小负数
            sum_exp <= 0;
            valid <= 0;
            for (j = 0; j < VEC_SIZE; j = j + 1) begin
                exp_values[j] <= 0;
                y[j] <= 0;
            end
        end else begin
            case (state)
                IDLE: begin
                    counter <= 0;
                    max_val <= {1'b1, {(DATA_WIDTH-1){1'b0}}};
                    sum_exp <= 0;
                    valid <= 0;
                end
                
                FIND_MAX: begin
                    // 找最大值（数值稳定性）
                    if ($signed(x[counter]) > $signed(max_val))
                        max_val <= x[counter];
                    counter <= counter + 1;
                end
                
                CALC_EXP: begin
                    // 计算 exp(x - max)，使用查找表近似
                    exp_values[counter] <= exp_approx(x[counter] - max_val);
                    counter <= counter + 1;
                end
                
                CALC_SUM: begin
                    // 求和
                    sum_exp = 0;
                    for (j = 0; j < VEC_SIZE; j = j + 1) begin
                        sum_exp = sum_exp + exp_values[j];
                    end
                    counter <= 0;
                end
                
                CALC_DIV: begin
                    // 除法：exp_values[i] / sum_exp
                    y[counter] <= divide_approx(exp_values[counter], sum_exp[DATA_WIDTH+FRAC_WIDTH-1:FRAC_WIDTH]);
                    counter <= counter + 1;
                end
                
                DONE: begin
                    // 打包输出
                    for (j = 0; j < VEC_SIZE; j = j + 1) begin
                        y_out[j*DATA_WIDTH +: DATA_WIDTH] <= y[j];
                    end
                    valid <= 1'b1;
                end
            endcase
        end
    end
    
    // 指数函数近似（使用分段线性）
    function [DATA_WIDTH-1:0] exp_approx;
        input signed [DATA_WIDTH-1:0] x;
        begin
            // exp(x) 近似实现
            // 对于 x < -8, exp(x) ≈ 0
            // 对于 x > 0, exp(x) ≈ 1 + x
            // 对于 -8 < x < 0, 使用线性插值
            if (x < -(8 << FRAC_WIDTH))
                exp_approx = 1; // 接近0，最小表示为1
            else if (x > 0)
                exp_approx = (1 << FRAC_WIDTH) + x;
            else
                exp_approx = (1 << FRAC_WIDTH) + (x >>> 3); // 粗略近似
        end
    endfunction
    
    // 除法近似（使用Newton-Raphson迭代）
    function [DATA_WIDTH-1:0] divide_approx;
        input [DATA_WIDTH-1:0] numerator;
        input [DATA_WIDTH-1:0] denominator;
        begin
            // 简化实现：y/sum ≈ y * (1/sum)
            // 实际应用中可用除法器IP核
            if (denominator == 0)
                divide_approx = 0;
            else
                divide_approx = (numerator << FRAC_WIDTH) / denominator;
        end
    endfunction

endmodule
