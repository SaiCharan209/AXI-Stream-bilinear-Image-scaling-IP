`timescale 1ns / 1ps

module image_scale_ip #(
    parameter W_IN        = 800,
    parameter H_IN        = 566,
    parameter W_OUT       = 900,
    parameter H_OUT       = 700,
    parameter FRAC_BITS   = 8,
    parameter CHANNELS    = 3,
    parameter BPC         = 8,
    
    parameter PIXEL_WIDTH = CHANNELS * BPC
) (
    input  wire aclk,
    input  wire aresetn,

    input  wire [PIXEL_WIDTH-1:0] s_axis_tdata,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,
    input  wire                   s_axis_tuser,
    input  wire                   s_axis_tlast,

    output reg  [PIXEL_WIDTH-1:0] m_axis_tdata,
    output reg                    m_axis_tvalid,
    input  wire                   m_axis_tready,
    output reg                    m_axis_tuser,
    output reg                    m_axis_tlast
);


    localparam scale_x = (W_IN << FRAC_BITS) / W_OUT;
    localparam scale_y = (H_IN << FRAC_BITS) / H_OUT;

    localparam X_OUT_BITS = $clog2(W_OUT);
    localparam Y_OUT_BITS = $clog2(H_OUT);
    localparam X_IN_BITS  = $clog2(W_IN);
    localparam Y_IN_BITS  = $clog2(H_IN);

    localparam DIFF_W = BPC + 1; 
    localparam MULT_W = DIFF_W + FRAC_BITS + 1; 


    reg [X_OUT_BITS-1:0] X_out;
    reg [Y_OUT_BITS-1:0] Y_out;

    reg [X_IN_BITS+FRAC_BITS-1:0] X_in_calc;
    reg [X_IN_BITS+FRAC_BITS-1:0] Y_in_calc;

    wire [X_IN_BITS-1:0] x0_raw = (X_in_calc >> FRAC_BITS);
    wire [Y_IN_BITS-1:0] y0_raw = (Y_in_calc >> FRAC_BITS);

    // Boundary clamping to prevent out-of-bounds line buffer addressing
    wire [X_IN_BITS-1:0] x0 = (x0_raw >= W_IN-1) ? (W_IN-1) : x0_raw[X_IN_BITS-1:0];
    wire [Y_IN_BITS-1:0] y0 = (y0_raw >= H_IN-1) ? (H_IN-1) : y0_raw[Y_IN_BITS-1:0];
    wire [X_IN_BITS-1:0] x1 = (x0 >= W_IN-1)     ? (W_IN-1) : x0 + 1;
    wire [Y_IN_BITS-1:0] y1 = (y0 >= H_IN-1)     ? (H_IN-1) : y0 + 1;

    wire window_valid;
    wire [PIXEL_WIDTH-1:0] buffer_I00, buffer_I01, buffer_I10, buffer_I11;
    reg frame_done;

    wire generate_en = window_valid && m_axis_tready && !frame_done;


    line_buffer_3x #(
        .W_IN       (W_IN), 
        .H_IN       (H_IN), 
        .DATA_WIDTH (PIXEL_WIDTH) 
    ) u_line_buffer (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .frame_done    (frame_done),
        .read_en       (generate_en),
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tready (s_axis_tready),
        .s_axis_tuser  (s_axis_tuser),
        .s_axis_tlast  (s_axis_tlast),
        .x0            (x0), 
        .x1            (x1), 
        .y0            (y0), 
        .y1            (y1),
        .I00           (buffer_I00), 
        .I01           (buffer_I01), 
        .I10           (buffer_I10), 
        .I11           (buffer_I11),
        .window_valid  (window_valid)
    );

    reg [5:0] valid_pipe;
    reg [5:0] sof_pipe;
    reg [5:0] last_pipe;

    wire is_sof  = (X_out == 0) && (Y_out == 0);
    wire is_last = (X_out == W_OUT - 1);
    reg [FRAC_BITS-1:0] S1S2_a, S1S2_b;

    always @(posedge aclk) begin : STAGE1_COUNTER
        if (!aresetn) begin
            X_out      <= 0; 
            Y_out      <= 0;
            X_in_calc  <= 0; 
            Y_in_calc  <= 0;
            frame_done <= 0;
        end else begin
            if (s_axis_tready && s_axis_tuser && s_axis_tvalid) begin
                X_out      <= 0;
                Y_out      <= 0;
                X_in_calc  <= 0;
                Y_in_calc  <= 0;
                frame_done <= 0;
            end 

            if (m_axis_tready) begin
                valid_pipe <= {valid_pipe[4:0], generate_en};
                sof_pipe   <= {sof_pipe[4:0],   (generate_en && is_sof)};
                last_pipe  <= {last_pipe[4:0],  (generate_en && is_last)};

                if (generate_en) begin
                    S1S2_a <= X_in_calc[FRAC_BITS-1:0];
                    S1S2_b <= Y_in_calc[FRAC_BITS-1:0];
                    
                    if (X_out == W_OUT - 1) begin
                        if (Y_out == H_OUT - 1) begin
                            frame_done <= 1; 
                        end else begin
                            X_out     <= 0;
                            Y_out     <= Y_out + 1;
                            X_in_calc <= 0;
                            Y_in_calc <= Y_in_calc + scale_y;
                        end
                    end else begin
                        X_out     <= X_out + 1;
                        X_in_calc <= X_in_calc + scale_x;
                    end
                end
            end
        end
    end


    reg [FRAC_BITS-1:0]   S2S3_a, S2S3_b;
    reg [PIXEL_WIDTH-1:0] S2S3_I00, S2S3_I01, S2S3_I10, S2S3_I11;

    always @(posedge aclk) begin : STAGE2_LINE_FETCH
        if (!aresetn) begin
            S2S3_a   <= 0; S2S3_b   <= 0;
            S2S3_I00 <= 0; S2S3_I01 <= 0; S2S3_I10 <= 0; S2S3_I11 <= 0;
        end else if (m_axis_tready && valid_pipe[0]) begin
            S2S3_a   <= S1S2_a; 
            S2S3_b   <= S1S2_b; 
            S2S3_I00 <= buffer_I00; S2S3_I01 <= buffer_I01;
            S2S3_I10 <= buffer_I10; S2S3_I11 <= buffer_I11;
        end
    end


    (* use_dsp = "yes" *) reg signed [MULT_W-1:0] S3S4_mult_T [0:CHANNELS-1];
    (* use_dsp = "yes" *) reg signed [MULT_W-1:0] S3S4_mult_B [0:CHANNELS-1];
    reg [PIXEL_WIDTH-1:0] S3S4_I00, S3S4_I01;
    reg [FRAC_BITS-1:0]   S3S4_b; 
        reg signed [DIFF_W-1:0] diff_T, diff_B;

    always @(posedge aclk) begin : STAGE3_X_MULT

        if (m_axis_tready && valid_pipe[1]) begin
            for (i = 0; i < CHANNELS; i = i + 1) begin
                diff_T = $signed({1'b0, S2S3_I10[i*BPC +: BPC]}) - $signed({1'b0, S2S3_I00[i*BPC +: BPC]});
                diff_B = $signed({1'b0, S2S3_I11[i*BPC +: BPC]}) - $signed({1'b0, S2S3_I01[i*BPC +: BPC]});

                S3S4_mult_T[i] <= $signed({1'b0, S2S3_a}) * diff_T;
                S3S4_mult_B[i] <= $signed({1'b0, S2S3_a}) * diff_B;
            end
            S3S4_I00 <= S2S3_I00; 
            S3S4_I01 <= S2S3_I01;
            S3S4_b   <= S2S3_b;   
        end
    end


    reg [PIXEL_WIDTH-1:0] S4S5_T, S4S5_B;
    reg [FRAC_BITS-1:0]   S4S5_b;
             integer i;

    always @(posedge aclk) begin : STAGE4_X_ADD
        if (m_axis_tready && valid_pipe[2]) begin
            for (i = 0; i < CHANNELS; i = i + 1) begin
                S4S5_T[i*BPC +: BPC] <= S3S4_I00[i*BPC +: BPC] + S3S4_mult_T[i][FRAC_BITS+BPC-1 : FRAC_BITS];
                S4S5_B[i*BPC +: BPC] <= S3S4_I01[i*BPC +: BPC] + S3S4_mult_B[i][FRAC_BITS+BPC-1 : FRAC_BITS];
            end
            S4S5_b <= S3S4_b;
        end
    end


    (* use_dsp = "yes" *) reg signed [MULT_W-1:0] S5S6_mult_Y [0:CHANNELS-1];
    reg [PIXEL_WIDTH-1:0] S5S6_T;
        reg signed [DIFF_W-1:0] diff_Y;
    always @(posedge aclk) begin : STAGE5_Y_MULT
        if (m_axis_tready && valid_pipe[3]) begin
            for (i = 0; i < CHANNELS; i = i + 1) begin
                diff_Y = $signed({1'b0, S4S5_B[i*BPC +: BPC]}) - $signed({1'b0, S4S5_T[i*BPC +: BPC]});
                S5S6_mult_Y[i] <= $signed({1'b0, S4S5_b}) * diff_Y;
            end
            S5S6_T <= S4S5_T;
        end
    end

    always @(posedge aclk) begin : STAGE6_OUTPUT                
        if (!aresetn) begin
            m_axis_tvalid <= 0;
            m_axis_tuser  <= 0;
            m_axis_tlast  <= 0;
            m_axis_tdata  <= 0;
        end else if (m_axis_tready) begin
            m_axis_tvalid <= valid_pipe[4];
            m_axis_tuser  <= sof_pipe[4];
            m_axis_tlast  <= last_pipe[4];
            
            if (valid_pipe[4]) begin
                for (i = 0; i < CHANNELS; i = i + 1) begin
                    m_axis_tdata[i*BPC +: BPC] <= S5S6_T[i*BPC +: BPC] + S5S6_mult_Y[i][FRAC_BITS+BPC-1 : FRAC_BITS];
                end
            end
        end
    end

endmodule