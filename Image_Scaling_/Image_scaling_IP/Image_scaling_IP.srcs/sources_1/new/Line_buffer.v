`timescale 1ns / 1ps

module line_buffer_3x #(
    parameter W_IN       = 800,
    parameter H_IN       = 566,
    parameter DATA_WIDTH = 24
)(
    input wire aclk,
    input wire aresetn,
    input wire frame_done, 
    input wire read_en, 
    
    input wire [DATA_WIDTH-1:0] s_axis_tdata,
    input wire                  s_axis_tvalid,
    output wire                 s_axis_tready,
    input wire                  s_axis_tuser,  
    input wire                  s_axis_tlast,  
    
    input wire [$clog2(W_IN)-1:0] x0,
    input wire [$clog2(W_IN)-1:0] x1,
    input wire [$clog2(H_IN)-1:0] y0,
    input wire [$clog2(H_IN)-1:0] y1,
    
    output reg [DATA_WIDTH-1:0] I00,
    output reg [DATA_WIDTH-1:0] I01,
    output reg [DATA_WIDTH-1:0] I10,
    output reg [DATA_WIDTH-1:0] I11,
    output wire window_valid
);

    localparam HALF_W = W_IN / 2;
    localparam HALF_BITS = $clog2(HALF_W);


    reg [DATA_WIDTH-1:0] line_mem_0_even [0:HALF_W-1];
    reg [DATA_WIDTH-1:0] line_mem_0_odd  [0:HALF_W-1];
    
    reg [DATA_WIDTH-1:0] line_mem_1_even [0:HALF_W-1];
    reg [DATA_WIDTH-1:0] line_mem_1_odd  [0:HALF_W-1];
    
    reg [DATA_WIDTH-1:0] line_mem_2_even [0:HALF_W-1];
    reg [DATA_WIDTH-1:0] line_mem_2_odd  [0:HALF_W-1];

    reg [$clog2(W_IN)-1:0] write_x;
    reg [$clog2(H_IN):0]   write_y; 
    reg [1:0]              write_y_mod3;

    assign s_axis_tready = (write_y <= y0 + 2) || frame_done; 
    assign window_valid  = (write_y > y1);

    wire [$clog2(W_IN)-1:0] act_x = s_axis_tuser ? 0 : write_x;
    wire [1:0]              act_y = s_axis_tuser ? 0 : write_y_mod3;


    wire [HALF_BITS-1:0] write_addr   = act_x[$clog2(W_IN)-1 : 1]; // Divide by 2
    wire                 write_is_odd = act_x[0];                  // Check LSB

    always @(posedge aclk) begin
        if (!aresetn) begin
            write_x <= 0; write_y <= 0; write_y_mod3 <= 0;
        end else if (s_axis_tvalid && s_axis_tready) begin
            
            // Route to Even or Odd bank based on the X coordinate
            if (act_y == 0) begin
                if (write_is_odd) line_mem_0_odd[write_addr]  <= s_axis_tdata;
                else              line_mem_0_even[write_addr] <= s_axis_tdata;
            end
            if (act_y == 1) begin
                if (write_is_odd) line_mem_1_odd[write_addr]  <= s_axis_tdata;
                else              line_mem_1_even[write_addr] <= s_axis_tdata;
            end
            if (act_y == 2) begin
                if (write_is_odd) line_mem_2_odd[write_addr]  <= s_axis_tdata;
                else              line_mem_2_even[write_addr] <= s_axis_tdata;
            end

            if (s_axis_tuser) begin
                write_x <= 1; write_y <= 0; write_y_mod3 <= 0;
            end else if (s_axis_tlast) begin
                write_x <= 0; write_y <= write_y + 1;
                write_y_mod3 <= (write_y_mod3 == 2) ? 0 : write_y_mod3 + 1;
            end else begin
                write_x <= write_x + 1;
            end
        end
    end


    wire [HALF_BITS-1:0] read_addr_odd  = x0[$clog2(W_IN)-1 : 1];
    wire [HALF_BITS-1:0] read_addr_even = x0[0] ? x1[$clog2(W_IN)-1 : 1] : x0[$clog2(W_IN)-1 : 1];

    reg [DATA_WIDTH-1:0] out_0_even, out_0_odd;
    reg [DATA_WIDTH-1:0] out_1_even, out_1_odd;
    reg [DATA_WIDTH-1:0] out_2_even, out_2_odd;
    
    reg x0_is_odd_reg;
    reg x0_is_clamped_reg;
    reg [1:0] y0_mod3_reg, y1_mod3_reg;

    always @(posedge aclk) begin
        if (read_en) begin
            out_0_even <= line_mem_0_even[read_addr_even];
            out_0_odd  <= line_mem_0_odd[read_addr_odd];
            
            out_1_even <= line_mem_1_even[read_addr_even];
            out_1_odd  <= line_mem_1_odd[read_addr_odd];
            
            out_2_even <= line_mem_2_even[read_addr_even];
            out_2_odd  <= line_mem_2_odd[read_addr_odd];

            // Delay control flags
            x0_is_odd_reg     <= x0[0];
            x0_is_clamped_reg <= (x0 == x1);
            y0_mod3_reg       <= y0 % 3;
            y1_mod3_reg       <= y1 % 3;
        end
    end
    wire [DATA_WIDTH-1:0] row0_x0 = x0_is_odd_reg ? out_0_odd  : out_0_even;
    wire [DATA_WIDTH-1:0] row0_x1 = x0_is_clamped_reg ? row0_x0 : (x0_is_odd_reg ? out_0_even : out_0_odd);

    wire [DATA_WIDTH-1:0] row1_x0 = x0_is_odd_reg ? out_1_odd  : out_1_even;
    wire [DATA_WIDTH-1:0] row1_x1 = x0_is_clamped_reg ? row1_x0 : (x0_is_odd_reg ? out_1_even : out_1_odd);

    wire [DATA_WIDTH-1:0] row2_x0 = x0_is_odd_reg ? out_2_odd  : out_2_even;
    wire [DATA_WIDTH-1:0] row2_x1 = x0_is_clamped_reg ? row2_x0 : (x0_is_odd_reg ? out_2_even : out_2_odd);


    always @(*) begin
        case (y0_mod3_reg)
            0: begin I00 = row0_x0; I10 = row0_x1; end
            1: begin I00 = row1_x0; I10 = row1_x1; end
            2: begin I00 = row2_x0; I10 = row2_x1; end
            default: begin I00 = 0; I10 = 0; end
        endcase

        case (y1_mod3_reg)
            0: begin I01 = row0_x0; I11 = row0_x1; end
            1: begin I01 = row1_x0; I11 = row1_x1; end
            2: begin I01 = row2_x0; I11 = row2_x1; end
            default: begin I01 = 0; I11 = 0; end
        endcase
    end

endmodule