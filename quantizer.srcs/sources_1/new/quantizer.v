module quantizer (
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME clk, FREQ_HZ 24000000, PHASE 0.0, ASSOCIATED_RESET rst" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    input  wire clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst RST" *)
    input  wire rst,
    input  wire enable,
    input  wire start,
    input  wire [1:0] quant_table_select,

    // Input DCT coefficient block (64 samples × 16 bits)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME coeff_stream_in, TDATA_NUM_BYTES 128, HAS_TREADY 0" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 coeff_stream_in TDATA" *)
    input  wire [1023:0] coeff_in,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 coeff_stream_in TVALID" *)
    input  wire coeff_valid,
    (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 coeff_ready DATA" *)
    output wire coeff_ready,

    // Output quantized block (64 samples × 16 bits)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME quant_stream_out, TDATA_NUM_BYTES 128, HAS_TREADY 0" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 quant_stream_out TDATA" *)
    output reg  [1023:0] quant_out,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 quant_stream_out TVALID" *)
    output reg  quant_valid,
    output reg  done,

    // Status
    (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 busy DATA" *)
    output reg  busy
);

localparam integer NUM_SAMPLES = 64;

// Quantization tables
reg [7:0] quant_table_y [0:NUM_SAMPLES-1];
reg [7:0] quant_table_c [0:NUM_SAMPLES-1];

initial begin
    quant_table_y[0]  = 16; quant_table_y[1]  = 11; quant_table_y[2]  = 10; quant_table_y[3]  = 16;
    quant_table_y[4]  = 24; quant_table_y[5]  = 40; quant_table_y[6]  = 51; quant_table_y[7]  = 61;
    quant_table_y[8]  = 12; quant_table_y[9]  = 12; quant_table_y[10] = 14; quant_table_y[11] = 19;
    quant_table_y[12] = 26; quant_table_y[13] = 58; quant_table_y[14] = 60; quant_table_y[15] = 55;
    quant_table_y[16] = 14; quant_table_y[17] = 13; quant_table_y[18] = 16; quant_table_y[19] = 24;
    quant_table_y[20] = 40; quant_table_y[21] = 57; quant_table_y[22] = 69; quant_table_y[23] = 56;
    quant_table_y[24] = 14; quant_table_y[25] = 17; quant_table_y[26] = 22; quant_table_y[27] = 29;
    quant_table_y[28] = 51; quant_table_y[29] = 87; quant_table_y[30] = 80; quant_table_y[31] = 62;
    quant_table_y[32] = 18; quant_table_y[33] = 22; quant_table_y[34] = 37; quant_table_y[35] = 56;
    quant_table_y[36] = 68; quant_table_y[37] = 109; quant_table_y[38] = 103; quant_table_y[39] = 77;
    quant_table_y[40] = 24; quant_table_y[41] = 35; quant_table_y[42] = 55; quant_table_y[43] = 64;
    quant_table_y[44] = 81; quant_table_y[45] = 104; quant_table_y[46] = 113; quant_table_y[47] = 92;
    quant_table_y[48] = 49; quant_table_y[49] = 64; quant_table_y[50] = 78; quant_table_y[51] = 87;
    quant_table_y[52] = 103; quant_table_y[53] = 121; quant_table_y[54] = 120; quant_table_y[55] = 101;
    quant_table_y[56] = 72; quant_table_y[57] = 92; quant_table_y[58] = 95; quant_table_y[59] = 98;
    quant_table_y[60] = 112; quant_table_y[61] = 100; quant_table_y[62] = 103; quant_table_y[63] = 99;

    quant_table_c[0]  = 17; quant_table_c[1]  = 18; quant_table_c[2]  = 24; quant_table_c[3]  = 47;
    quant_table_c[4]  = 99; quant_table_c[5]  = 99; quant_table_c[6]  = 99; quant_table_c[7]  = 99;
    quant_table_c[8]  = 18; quant_table_c[9]  = 21; quant_table_c[10] = 26; quant_table_c[11] = 66;
    quant_table_c[12] = 99; quant_table_c[13] = 99; quant_table_c[14] = 99; quant_table_c[15] = 99;
    quant_table_c[16] = 24; quant_table_c[17] = 26; quant_table_c[18] = 56; quant_table_c[19] = 99;
    quant_table_c[20] = 99; quant_table_c[21] = 99; quant_table_c[22] = 99; quant_table_c[23] = 99;
    quant_table_c[24] = 47; quant_table_c[25] = 66; quant_table_c[26] = 99; quant_table_c[27] = 99;
    quant_table_c[28] = 99; quant_table_c[29] = 99; quant_table_c[30] = 99; quant_table_c[31] = 99;
    quant_table_c[32] = 99; quant_table_c[33] = 99; quant_table_c[34] = 99; quant_table_c[35] = 99;
    quant_table_c[36] = 99; quant_table_c[37] = 99; quant_table_c[38] = 99; quant_table_c[39] = 99;
    quant_table_c[40] = 99; quant_table_c[41] = 99; quant_table_c[42] = 99; quant_table_c[43] = 99;
    quant_table_c[44] = 99; quant_table_c[45] = 99; quant_table_c[46] = 99; quant_table_c[47] = 99;
    quant_table_c[48] = 99; quant_table_c[49] = 99; quant_table_c[50] = 99; quant_table_c[51] = 99;
    quant_table_c[52] = 99; quant_table_c[53] = 99; quant_table_c[54] = 99; quant_table_c[55] = 99;
    quant_table_c[56] = 99; quant_table_c[57] = 99; quant_table_c[58] = 99; quant_table_c[59] = 99;
    quant_table_c[60] = 99; quant_table_c[61] = 99; quant_table_c[62] = 99; quant_table_c[63] = 99;
end

localparam [1:0] S_IDLE       = 2'd0;
localparam [1:0] S_WAIT_BLOCK = 2'd1;
localparam [1:0] S_PROCESS    = 2'd2;
localparam [1:0] S_OUTPUT     = 2'd3;

reg [1:0] state;
reg [1:0] active_table;
reg [5:0] process_idx;
reg block_loaded;

reg  signed [15:0] coeff_buffer [0:NUM_SAMPLES-1];
reg  signed [15:0] quantized_buffer [0:NUM_SAMPLES-1];

integer load_idx;
integer pack_idx;

assign coeff_ready = !block_loaded;

always @(posedge clk) begin
    if (rst) begin
        block_loaded <= 1'b0;
        for (load_idx = 0; load_idx < NUM_SAMPLES; load_idx = load_idx + 1) begin
            coeff_buffer[load_idx]    <= 16'sd0;
            quantized_buffer[load_idx] <= 16'sd0;
        end
    end else begin
        if (coeff_valid && !block_loaded) begin
            for (load_idx = 0; load_idx < NUM_SAMPLES; load_idx = load_idx + 1) begin
                coeff_buffer[load_idx] <= $signed(coeff_in[load_idx*16 +: 16]);
            end
            block_loaded <= 1'b1;
        end else if (state == S_OUTPUT) begin
            block_loaded <= 1'b0;
        end
    end
end

wire [7:0] quant_value = (active_table == 2'd0) ?
                         quant_table_y[process_idx] :
                         quant_table_c[process_idx];

always @(posedge clk) begin
    if (rst) begin
        state         <= S_IDLE;
        active_table  <= 2'd0;
        process_idx   <= 6'd0;
        quant_out     <= {1024{1'b0}};
        quant_valid   <= 1'b0;
        done          <= 1'b0;
        busy          <= 1'b0;
    end else begin
        quant_valid <= 1'b0;
        done        <= 1'b0;

        case (state)
            S_IDLE: begin
                busy <= 1'b0;
                if (start && enable) begin
                    active_table <= quant_table_select;
                    busy         <= 1'b1;
                    if (block_loaded) begin
                        process_idx <= 6'd0;
                        state       <= S_PROCESS;
                    end else begin
                        state       <= S_WAIT_BLOCK;
                    end
                end
            end

            S_WAIT_BLOCK: begin
                busy <= 1'b1;
                if (block_loaded) begin
                    process_idx <= 6'd0;
                    state       <= S_PROCESS;
                end
            end

            S_PROCESS: begin
                busy <= 1'b1;
                if (enable) begin
                    if (quant_value != 0)
                        quantized_buffer[process_idx] <= coeff_buffer[process_idx] / $signed({1'b0, quant_value});
                    else
                        quantized_buffer[process_idx] <= coeff_buffer[process_idx];

                    if (process_idx == NUM_SAMPLES-1) begin
                        state <= S_OUTPUT;
                    end else begin
                        process_idx <= process_idx + 6'd1;
                    end
                end
            end

            S_OUTPUT: begin
                busy <= 1'b0;
                for (pack_idx = 0; pack_idx < NUM_SAMPLES; pack_idx = pack_idx + 1) begin
                    quant_out[pack_idx*16 +: 16] <= quantized_buffer[pack_idx];
                end
                quant_valid <= 1'b1;
                done        <= 1'b1;
                state       <= S_IDLE;
            end

            default: begin
                state <= S_IDLE;
            end
        endcase
    end
end

endmodule

