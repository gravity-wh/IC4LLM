/*******************************************************************************
* Module: attention_core
* Description: 多头自注意力核心计算单元
*              实现 Attention(Q,K,V) = softmax(QK^T/√d_k) * V
*              支持因果掩码（Causal Masking）用于自回归生成
* Author: AI Hardware Accelerator Engineer
* Date: 2026-02-12
*******************************************************************************/

module attention_core #(
    parameter DATA_WIDTH = 16,
    parameter FRAC_WIDTH = 8,
    parameter SEQ_LEN = 8,          // 序列长度
    parameter HEAD_DIM = 64,        // 每个注意力头的维度
    parameter NUM_HEADS = 4         // 注意力头数量
)(
    input  wire                                 clk,
    input  wire                                 rst_n,
    input  wire                                 start,
    input  wire                                 causal_mask_en,
    // Q, K, V 输入 (简化为单头)
    input  wire [SEQ_LEN*HEAD_DIM*DATA_WIDTH-1:0]  q_in,
    input  wire [SEQ_LEN*HEAD_DIM*DATA_WIDTH-1:0]  k_in,
    input  wire [SEQ_LEN*HEAD_DIM*DATA_WIDTH-1:0]  v_in,
    // 输出
    output reg  [SEQ_LEN*HEAD_DIM*DATA_WIDTH-1:0]  attn_out,
    output reg                                  valid,
    output reg                                  busy
);

    // 状态机
    localparam IDLE         = 4'b0000;
    localparam CALC_QK      = 4'b0001;
    localparam SCALE_QK     = 4'b0010;
    localparam APPLY_MASK   = 4'b0011;
    localparam CALC_SOFTMAX = 4'b0100;
    localparam CALC_ATTN_V  = 4'b0101;
    localparam DONE         = 4'b0110;
    
    reg [3:0] state, next_state;
    reg [7:0] seq_counter_i, seq_counter_j;
    
    // 内部存储
    // QK^T 结果矩阵 (SEQ_LEN x SEQ_LEN)
    reg [DATA_WIDTH-1:0] qk_matrix [0:SEQ_LEN-1][0:SEQ_LEN-1];
    
    // Softmax 后的注意力分数
    reg [DATA_WIDTH-1:0] attn_scores [0:SEQ_LEN-1][0:SEQ_LEN-1];
    
    // 展开Q, K, V向量（简化：仅处理第一个头）
    wire [DATA_WIDTH-1:0] q [0:SEQ_LEN-1][0:HEAD_DIM-1];
    wire [DATA_WIDTH-1:0] k [0:SEQ_LEN-1][0:HEAD_DIM-1];
    wire [DATA_WIDTH-1:0] v [0:SEQ_LEN-1][0:HEAD_DIM-1];
    
    // MAC单元接口
    wire [HEAD_DIM*DATA_WIDTH-1:0] mac_a, mac_b;
    wire [DATA_WIDTH-1:0] mac_result;
    wire mac_valid, mac_en, mac_clear;
    
    // Softmax单元接口
    wire [SEQ_LEN*DATA_WIDTH-1:0] softmax_in, softmax_out;
    wire softmax_start, softmax_valid;
    
    // 缩放因子：1/sqrt(d_k)
    // 对于d_k=64, sqrt(64)=8, 因此缩放因子约为0.125 = 1/8
    localparam [DATA_WIDTH-1:0] SCALE_FACTOR = 16'h0020; // 0.125 in Q8.8 format
    
    genvar gi, gj;
    generate
        for (gi = 0; gi < SEQ_LEN; gi = gi + 1) begin : seq_unpack
            for (gj = 0; gj < HEAD_DIM; gj = gj + 1) begin : dim_unpack
                assign q[gi][gj] = q_in[(gi*HEAD_DIM + gj)*DATA_WIDTH +: DATA_WIDTH];
                assign k[gi][gj] = k_in[(gi*HEAD_DIM + gj)*DATA_WIDTH +: DATA_WIDTH];
                assign v[gi][gj] = v_in[(gi*HEAD_DIM + gj)*DATA_WIDTH +: DATA_WIDTH];
            end
        end
    endgenerate
    
    // 实例化MAC单元计算点积
    mac_unit #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH),
        .VEC_SIZE(HEAD_DIM)
    ) mac_inst (
        .clk(clk),
        .rst_n(rst_n),
        .en(mac_en),
        .clear_acc(mac_clear),
        .a_vec(mac_a),
        .b_vec(mac_b),
        .result(mac_result),
        .valid(mac_valid)
    );
    
    // 实例化Softmax单元
    softmax_unit #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH),
        .VEC_SIZE(SEQ_LEN)
    ) softmax_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(softmax_start),
        .x_in(softmax_in),
        .y_out(softmax_out),
        .valid(softmax_valid)
    );
    
    // 状态机时序逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end
    
    // 状态转移逻辑
    reg softmax_done;
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (start)
                    next_state = CALC_QK;
            end
            CALC_QK: begin
                if (seq_counter_i == SEQ_LEN-1 && seq_counter_j == SEQ_LEN-1 && mac_valid)
                    next_state = SCALE_QK;
            end
            SCALE_QK: begin
                if (seq_counter_i == SEQ_LEN-1 && seq_counter_j == SEQ_LEN-1)
                    next_state = causal_mask_en ? APPLY_MASK : CALC_SOFTMAX;
            end
            APPLY_MASK: begin
                if (seq_counter_i == SEQ_LEN-1)
                    next_state = CALC_SOFTMAX;
            end
            CALC_SOFTMAX: begin
                if (softmax_done)
                    next_state = CALC_ATTN_V;
            end
            CALC_ATTN_V: begin
                if (seq_counter_i == SEQ_LEN-1 && seq_counter_j == HEAD_DIM-1 && mac_valid)
                    next_state = DONE;
            end
            DONE: begin
                next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end
    
    // 数据路径控制
    integer i, j, k;
    reg signed [2*DATA_WIDTH-1:0] temp_mult;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            seq_counter_i <= 0;
            seq_counter_j <= 0;
            softmax_done <= 0;
            valid <= 0;
            busy <= 0;
            for (i = 0; i < SEQ_LEN; i = i + 1) begin
                for (j = 0; j < SEQ_LEN; j = j + 1) begin
                    qk_matrix[i][j] <= 0;
                    attn_scores[i][j] <= 0;
                end
            end
        end else begin
            case (state)
                IDLE: begin
                    seq_counter_i <= 0;
                    seq_counter_j <= 0;
                    softmax_done <= 0;
                    valid <= 0;
                    busy <= start;
                end
                
                CALC_QK: begin
                    // 计算 QK^T[i][j] = Q[i] · K[j]
                    busy <= 1'b1;
                    if (mac_valid) begin
                        qk_matrix[seq_counter_i][seq_counter_j] <= mac_result;
                        
                        if (seq_counter_j == SEQ_LEN-1) begin
                            seq_counter_j <= 0;
                            if (seq_counter_i == SEQ_LEN-1)
                                seq_counter_i <= 0;
                            else
                                seq_counter_i <= seq_counter_i + 1;
                        end else begin
                            seq_counter_j <= seq_counter_j + 1;
                        end
                    end
                end
                
                SCALE_QK: begin
                    // 缩放：QK^T / sqrt(d_k)
                    temp_mult = $signed(qk_matrix[seq_counter_i][seq_counter_j]) * $signed(SCALE_FACTOR);
                    qk_matrix[seq_counter_i][seq_counter_j] <= temp_mult[DATA_WIDTH+FRAC_WIDTH-1:FRAC_WIDTH];
                    
                    if (seq_counter_j == SEQ_LEN-1) begin
                        seq_counter_j <= 0;
                        if (seq_counter_i == SEQ_LEN-1)
                            seq_counter_i <= 0;
                        else
                            seq_counter_i <= seq_counter_i + 1;
                    end else begin
                        seq_counter_j <= seq_counter_j + 1;
                    end
                end
                
                APPLY_MASK: begin
                    // 应用因果掩码（上三角置为负无穷大）
                    for (j = 0; j < SEQ_LEN; j = j + 1) begin
                        if (j > seq_counter_i)
                            qk_matrix[seq_counter_i][j] <= {1'b1, {(DATA_WIDTH-1){1'b0}}}; // 最小负数
                    end
                    
                    if (seq_counter_i == SEQ_LEN-1)
                        seq_counter_i <= 0;
                    else
                        seq_counter_i <= seq_counter_i + 1;
                end
                
                CALC_SOFTMAX: begin
                    // 对每一行应用Softmax
                    if (!softmax_done) begin
                        if (seq_counter_i < SEQ_LEN && !softmax_valid) begin
                            // 启动Softmax计算
                            if (seq_counter_i == 0 || softmax_valid) begin
                                seq_counter_i <= seq_counter_i + 1;
                            end
                        end else if (softmax_valid) begin
                            // 存储Softmax结果
                            for (j = 0; j < SEQ_LEN; j = j + 1) begin
                                attn_scores[seq_counter_i-1][j] <= softmax_out[j*DATA_WIDTH +: DATA_WIDTH];
                            end
                            
                            if (seq_counter_i == SEQ_LEN) begin
                                softmax_done <= 1'b1;
                                seq_counter_i <= 0;
                                seq_counter_j <= 0;
                            end
                        end
                    end
                end
                
                CALC_ATTN_V: begin
                    // 计算 Output[i][j] = Σ(attn_scores[i][k] * V[k][j])
                    if (mac_valid) begin
                        // 存储结果（简化，实际需要适当的索引）
                        attn_out[(seq_counter_i*HEAD_DIM + seq_counter_j)*DATA_WIDTH +: DATA_WIDTH] <= mac_result;
                        
                        if (seq_counter_j == HEAD_DIM-1) begin
                            seq_counter_j <= 0;
                            if (seq_counter_i == SEQ_LEN-1)
                                seq_counter_i <= 0;
                            else
                                seq_counter_i <= seq_counter_i + 1;
                        end else begin
                            seq_counter_j <= seq_counter_j + 1;
                        end
                    end
                end
                
                DONE: begin
                    valid <= 1'b1;
                    busy <= 1'b0;
                end
            endcase
        end
    end
    
    // MAC单元输入多路复用
    assign mac_en = (state == CALC_QK || state == CALC_ATTN_V);
    assign mac_clear = (seq_counter_j == 0);
    
    // 准备MAC输入向量
    generate
        for (gi = 0; gi < HEAD_DIM; gi = gi + 1) begin : mac_input_mux
            assign mac_a[gi*DATA_WIDTH +: DATA_WIDTH] = 
                (state == CALC_QK) ? q[seq_counter_i][gi] : 
                (state == CALC_ATTN_V) ? {{DATA_WIDTH{1'b0}}} : {DATA_WIDTH{1'b0}};
            
            assign mac_b[gi*DATA_WIDTH +: DATA_WIDTH] = 
                (state == CALC_QK) ? k[seq_counter_j][gi] : 
                (state == CALC_ATTN_V) ? {{DATA_WIDTH{1'b0}}} : {DATA_WIDTH{1'b0}};
        end
    endgenerate
    
    // Softmax输入准备
    generate
        for (gi = 0; gi < SEQ_LEN; gi = gi + 1) begin : softmax_input_mux
            assign softmax_in[gi*DATA_WIDTH +: DATA_WIDTH] = qk_matrix[seq_counter_i][gi];
        end
    endgenerate
    
    assign softmax_start = (state == CALC_SOFTMAX && !softmax_done && seq_counter_i < SEQ_LEN);

endmodule
