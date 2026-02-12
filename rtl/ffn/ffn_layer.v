/*******************************************************************************
* Module: ffn_layer
* Description: 前馈网络层 (Feed-Forward Network)
*              实现 FFN(x) = GELU(xW1 + b1)W2 + b2
*              支持向量化计算和流水线处理
* Author: AI Hardware Accelerator Engineer
* Date: 2026-02-12
*******************************************************************************/

module ffn_layer #(
    parameter DATA_WIDTH = 16,
    parameter FRAC_WIDTH = 8,
    parameter INPUT_DIM = 512,      // 输入维度
    parameter HIDDEN_DIM = 2048,    // 隐藏层维度
    parameter OUTPUT_DIM = 512      // 输出维度
)(
    input  wire                                 clk,
    input  wire                                 rst_n,
    input  wire                                 start,
    // 权重加载接口
    input  wire                                 weight_load_en,
    input  wire [1:0]                           weight_select, // 0:W1, 1:W2, 2:b1, 3:b2
    input  wire [DATA_WIDTH-1:0]                weight_data,
    // 数据输入
    input  wire [INPUT_DIM*DATA_WIDTH-1:0]      x_in,
    // 数据输出
    output reg  [OUTPUT_DIM*DATA_WIDTH-1:0]     y_out,
    output reg                                  valid,
    output reg                                  busy
);

    // 状态机
    localparam IDLE         = 3'b000;
    localparam CALC_XW1     = 3'b001;
    localparam ADD_BIAS1    = 3'b010;
    localparam CALC_GELU    = 3'b011;
    localparam CALC_HW2     = 3'b100;
    localparam ADD_BIAS2    = 3'b101;
    localparam DONE         = 3'b110;
    
    reg [2:0] state, next_state;
    reg [15:0] calc_counter;
    
    // 权重存储（简化：使用小型示例）
    // 实际应用中应使用片上SRAM或外部存储
    reg [DATA_WIDTH-1:0] W1 [0:HIDDEN_DIM-1][0:INPUT_DIM-1];
    reg [DATA_WIDTH-1:0] W2 [0:OUTPUT_DIM-1][0:HIDDEN_DIM-1];
    reg [DATA_WIDTH-1:0] b1 [0:HIDDEN_DIM-1];
    reg [DATA_WIDTH-1:0] b2 [0:OUTPUT_DIM-1];
    
    // 中间结果
    reg [DATA_WIDTH-1:0] hidden [0:HIDDEN_DIM-1];      // xW1 + b1
    reg [DATA_WIDTH-1:0] hidden_act [0:HIDDEN_DIM-1];  // GELU(hidden)
    reg [DATA_WIDTH-1:0] output_temp [0:OUTPUT_DIM-1]; // hidden_act * W2
    
    // 展开输入向量
    wire [DATA_WIDTH-1:0] x [0:INPUT_DIM-1];
    genvar gi;
    generate
        for (gi = 0; gi < INPUT_DIM; gi = gi + 1) begin : input_unpack
            assign x[gi] = x_in[gi*DATA_WIDTH +: DATA_WIDTH];
        end
    endgenerate
    
    // MAC单元实例化（用于矩阵乘法）
    wire [INPUT_DIM*DATA_WIDTH-1:0] mac1_a, mac1_b;
    wire [DATA_WIDTH-1:0] mac1_result;
    wire mac1_valid, mac1_en, mac1_clear;
    
    mac_unit #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH),
        .VEC_SIZE(INPUT_DIM)
    ) mac1_inst (
        .clk(clk),
        .rst_n(rst_n),
        .en(mac1_en),
        .clear_acc(mac1_clear),
        .a_vec(mac1_a),
        .b_vec(mac1_b),
        .result(mac1_result),
        .valid(mac1_valid)
    );
    
    wire [HIDDEN_DIM*DATA_WIDTH-1:0] mac2_a, mac2_b;
    wire [DATA_WIDTH-1:0] mac2_result;
    wire mac2_valid, mac2_en, mac2_clear;
    
    mac_unit #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH),
        .VEC_SIZE(HIDDEN_DIM)
    ) mac2_inst (
        .clk(clk),
        .rst_n(rst_n),
        .en(mac2_en),
        .clear_acc(mac2_clear),
        .a_vec(mac2_a),
        .b_vec(mac2_b),
        .result(mac2_result),
        .valid(mac2_valid)
    );
    
    // GELU激活函数单元
    wire [DATA_WIDTH-1:0] gelu_in, gelu_out;
    wire gelu_en, gelu_valid;
    
    activation_gelu #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH)
    ) gelu_inst (
        .clk(clk),
        .rst_n(rst_n),
        .en(gelu_en),
        .x_in(gelu_in),
        .y_out(gelu_out),
        .valid(gelu_valid)
    );
    
    // 权重加载逻辑
    reg [15:0] weight_load_addr;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_load_addr <= 0;
        end else if (weight_load_en) begin
            case (weight_select)
                2'b00: begin // W1
                    if (weight_load_addr < INPUT_DIM * HIDDEN_DIM) begin
                        W1[weight_load_addr / INPUT_DIM][weight_load_addr % INPUT_DIM] <= weight_data;
                        weight_load_addr <= weight_load_addr + 1;
                    end
                end
                2'b01: begin // W2
                    if (weight_load_addr < HIDDEN_DIM * OUTPUT_DIM) begin
                        W2[weight_load_addr / HIDDEN_DIM][weight_load_addr % HIDDEN_DIM] <= weight_data;
                        weight_load_addr <= weight_load_addr + 1;
                    end
                end
                2'b10: begin // b1
                    if (weight_load_addr < HIDDEN_DIM) begin
                        b1[weight_load_addr] <= weight_data;
                        weight_load_addr <= weight_load_addr + 1;
                    end
                end
                2'b11: begin // b2
                    if (weight_load_addr < OUTPUT_DIM) begin
                        b2[weight_load_addr] <= weight_data;
                        weight_load_addr <= weight_load_addr + 1;
                    end
                end
            endcase
        end else begin
            weight_load_addr <= 0;
        end
    end
    
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
                    next_state = CALC_XW1;
            end
            CALC_XW1: begin
                if (calc_counter == HIDDEN_DIM-1 && mac1_valid)
                    next_state = ADD_BIAS1;
            end
            ADD_BIAS1: begin
                if (calc_counter == HIDDEN_DIM-1)
                    next_state = CALC_GELU;
            end
            CALC_GELU: begin
                if (calc_counter == HIDDEN_DIM-1 && gelu_valid)
                    next_state = CALC_HW2;
            end
            CALC_HW2: begin
                if (calc_counter == OUTPUT_DIM-1 && mac2_valid)
                    next_state = ADD_BIAS2;
            end
            ADD_BIAS2: begin
                if (calc_counter == OUTPUT_DIM-1)
                    next_state = DONE;
            end
            DONE: begin
                next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end
    
    // 数据路径
    integer i, j;
    reg signed [2*DATA_WIDTH-1:0] temp_add;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            calc_counter <= 0;
            valid <= 0;
            busy <= 0;
            for (i = 0; i < HIDDEN_DIM; i = i + 1) begin
                hidden[i] <= 0;
                hidden_act[i] <= 0;
            end
            for (i = 0; i < OUTPUT_DIM; i = i + 1) begin
                output_temp[i] <= 0;
            end
        end else begin
            case (state)
                IDLE: begin
                    calc_counter <= 0;
                    valid <= 0;
                    busy <= start;
                end
                
                CALC_XW1: begin
                    // 计算 hidden[i] = x · W1[i]
                    busy <= 1'b1;
                    if (mac1_valid) begin
                        hidden[calc_counter] <= mac1_result;
                        if (calc_counter == HIDDEN_DIM-1)
                            calc_counter <= 0;
                        else
                            calc_counter <= calc_counter + 1;
                    end
                end
                
                ADD_BIAS1: begin
                    // hidden[i] = hidden[i] + b1[i]
                    hidden[calc_counter] <= $signed(hidden[calc_counter]) + $signed(b1[calc_counter]);
                    
                    if (calc_counter == HIDDEN_DIM-1)
                        calc_counter <= 0;
                    else
                        calc_counter <= calc_counter + 1;
                end
                
                CALC_GELU: begin
                    // hidden_act[i] = GELU(hidden[i])
                    if (gelu_valid) begin
                        hidden_act[calc_counter] <= gelu_out;
                        if (calc_counter == HIDDEN_DIM-1)
                            calc_counter <= 0;
                        else
                            calc_counter <= calc_counter + 1;
                    end
                end
                
                CALC_HW2: begin
                    // output_temp[i] = hidden_act · W2[i]
                    if (mac2_valid) begin
                        output_temp[calc_counter] <= mac2_result;
                        if (calc_counter == OUTPUT_DIM-1)
                            calc_counter <= 0;
                        else
                            calc_counter <= calc_counter + 1;
                    end
                end
                
                ADD_BIAS2: begin
                    // output[i] = output_temp[i] + b2[i]
                    y_out[calc_counter*DATA_WIDTH +: DATA_WIDTH] <= 
                        $signed(output_temp[calc_counter]) + $signed(b2[calc_counter]);
                    
                    if (calc_counter == OUTPUT_DIM-1)
                        calc_counter <= 0;
                    else
                        calc_counter <= calc_counter + 1;
                end
                
                DONE: begin
                    valid <= 1'b1;
                    busy <= 1'b0;
                end
            endcase
        end
    end
    
    // MAC单元控制信号
    assign mac1_en = (state == CALC_XW1);
    assign mac1_clear = 1'b1; // 每次新计算清除累加器
    
    assign mac2_en = (state == CALC_HW2);
    assign mac2_clear = 1'b1;
    
    // MAC输入向量准备
    generate
        for (gi = 0; gi < INPUT_DIM; gi = gi + 1) begin : mac1_input_mux
            assign mac1_a[gi*DATA_WIDTH +: DATA_WIDTH] = x[gi];
            assign mac1_b[gi*DATA_WIDTH +: DATA_WIDTH] = W1[calc_counter][gi];
        end
    endgenerate
    
    generate
        for (gi = 0; gi < HIDDEN_DIM; gi = gi + 1) begin : mac2_input_mux
            assign mac2_a[gi*DATA_WIDTH +: DATA_WIDTH] = hidden_act[gi];
            assign mac2_b[gi*DATA_WIDTH +: DATA_WIDTH] = W2[calc_counter][gi];
        end
    endgenerate
    
    // GELU输入
    assign gelu_in = hidden[calc_counter];
    assign gelu_en = (state == CALC_GELU);

endmodule
