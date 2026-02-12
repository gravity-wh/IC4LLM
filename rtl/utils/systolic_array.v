/*******************************************************************************
* Module: systolic_array
* Description: 脉动阵列矩阵乘法器 (Weight-Stationary架构)
*              实现 C = A * B，其中A为激活矩阵，B为权重矩阵（预加载）
*              阵列大小: ARRAY_SIZE x ARRAY_SIZE
* Author: AI Hardware Accelerator Engineer
* Date: 2026-02-12
*******************************************************************************/

module systolic_array #(
    parameter DATA_WIDTH = 16,
    parameter FRAC_WIDTH = 8,
    parameter ARRAY_SIZE = 8
)(
    input  wire                                 clk,
    input  wire                                 rst_n,
    input  wire                                 en,
    input  wire                                 weight_load_en,
    input  wire [ARRAY_SIZE*DATA_WIDTH-1:0]     weight_data,  // 权重加载数据
    input  wire [ARRAY_SIZE*DATA_WIDTH-1:0]     activation_in, // 激活值输入
    output wire [ARRAY_SIZE*DATA_WIDTH-1:0]     result_out,    // 计算结果输出
    output wire                                 valid
);

    // PE (Processing Element) 定义
    wire [DATA_WIDTH-1:0] a_horizontal [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    wire [DATA_WIDTH-1:0] p_vertical [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    
    // 展开输入向量
    wire [DATA_WIDTH-1:0] activation [0:ARRAY_SIZE-1];
    wire [DATA_WIDTH-1:0] weight [0:ARRAY_SIZE-1];
    wire [DATA_WIDTH-1:0] result [0:ARRAY_SIZE-1];
    
    genvar i, j;
    generate
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin : unpack
            assign activation[i] = activation_in[i*DATA_WIDTH +: DATA_WIDTH];
            assign weight[i] = weight_data[i*DATA_WIDTH +: DATA_WIDTH];
            assign result_out[i*DATA_WIDTH +: DATA_WIDTH] = p_vertical[i][ARRAY_SIZE-1];
        end
    endgenerate
    
    // 脉动阵列PE实例化
    generate
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin : row
            for (j = 0; j < ARRAY_SIZE; j = j + 1) begin : col
                // 第一列的激活输入
                if (j == 0) begin
                    assign a_horizontal[i][j] = activation[i];
                end
                
                // 第一行的部分和输入（初始为0）
                if (i == 0) begin
                    // 顶部PE没有来自上方的部分和
                end
                
                systolic_pe #(
                    .DATA_WIDTH(DATA_WIDTH),
                    .FRAC_WIDTH(FRAC_WIDTH)
                ) pe_inst (
                    .clk(clk),
                    .rst_n(rst_n),
                    .en(en),
                    .weight_load_en(weight_load_en),
                    .weight_in(weight[j]),
                    .a_in(a_horizontal[i][j]),
                    .p_in((i == 0) ? {DATA_WIDTH{1'b0}} : p_vertical[i-1][j]),
                    .a_out((j < ARRAY_SIZE-1) ? a_horizontal[i][j+1] : ),
                    .p_out(p_vertical[i][j])
                );
            end
        end
    endgenerate
    
    // 输出有效信号（可以根据流水线深度调整）
    reg [3:0] valid_delay;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            valid_delay <= 4'b0;
        else
            valid_delay <= {valid_delay[2:0], en};
    end
    
    assign valid = valid_delay[3];

endmodule

/*******************************************************************************
* Module: systolic_pe
* Description: 脉动阵列处理单元 (Processing Element)
*              存储权重，执行乘加操作，传递激活值和部分和
*******************************************************************************/
module systolic_pe #(
    parameter DATA_WIDTH = 16,
    parameter FRAC_WIDTH = 8
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     en,
    input  wire                     weight_load_en,
    input  wire [DATA_WIDTH-1:0]    weight_in,
    input  wire [DATA_WIDTH-1:0]    a_in,       // 激活值输入（来自左侧）
    input  wire [DATA_WIDTH-1:0]    p_in,       // 部分和输入（来自上方）
    output reg  [DATA_WIDTH-1:0]    a_out,      // 激活值输出（向右）
    output reg  [DATA_WIDTH-1:0]    p_out       // 部分和输出（向下）
);

    reg [DATA_WIDTH-1:0] weight_reg;
    reg signed [2*DATA_WIDTH-1:0] mult_result;
    reg signed [2*DATA_WIDTH-1:0] add_result;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_reg <= 0;
            mult_result <= 0;
            add_result <= 0;
            a_out <= 0;
            p_out <= 0;
        end else begin
            // 权重加载
            if (weight_load_en) begin
                weight_reg <= weight_in;
            end
            
            if (en) begin
                // 乘法操作
                mult_result <= $signed(a_in) * $signed(weight_reg);
                
                // 加法操作：新的乘积 + 来自上方的部分和
                add_result <= mult_result + ($signed(p_in) << FRAC_WIDTH);
                
                // 传递激活值到右侧PE
                a_out <= a_in;
                
                // 传递部分和到下方PE
                p_out <= add_result[DATA_WIDTH+FRAC_WIDTH-1:FRAC_WIDTH];
            end
        end
    end

endmodule
