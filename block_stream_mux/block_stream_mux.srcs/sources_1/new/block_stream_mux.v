module block_stream_mux (
    // Clock and Reset
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME clk, FREQ_HZ 24000000, PHASE 0.0, ASSOCIATED_RESET rst, ASSOCIATED_BUSIF y_block_stream:cb_block_stream:cr_block_stream:m_block_stream" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    input wire clk,
    
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME rst, POLARITY ACTIVE_HIGH" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst RST" *)
    input wire rst,
    
    // Channel select from FSM controller
    (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 channel_select DATA" *)
    input wire [1:0] channel_select,
    
    // ========== Y CHANNEL INPUT (from block_buffer_0) ==========
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME y_block_stream, TDATA_NUM_BYTES 64, HAS_TREADY 0" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 y_block_stream TDATA" *)
    input wire [511:0] y_block_data_flat,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 y_block_stream TVALID" *)
    input wire y_block_ready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 y_block_stream TLAST" *)
    input wire y_block_valid,
    
    // ========== Cb CHANNEL INPUT (from block_buffer_1) ==========
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME cb_block_stream, TDATA_NUM_BYTES 64, HAS_TREADY 0" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 cb_block_stream TDATA" *)
    input wire [511:0] cb_block_data_flat,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 cb_block_stream TVALID" *)
    input wire cb_block_ready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 cb_block_stream TLAST" *)
    input wire cb_block_valid,
    
    // ========== Cr CHANNEL INPUT (from block_buffer_2) ==========
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME cr_block_stream, TDATA_NUM_BYTES 64, HAS_TREADY 0" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 cr_block_stream TDATA" *)
    input wire [511:0] cr_block_data_flat,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 cr_block_stream TVALID" *)
    input wire cr_block_ready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 cr_block_stream TLAST" *)
    input wire cr_block_valid,
    
    // ========== OUTPUT TO DCT ==========
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME m_block_stream, TDATA_NUM_BYTES 64, HAS_TREADY 0" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_block_stream TDATA" *)
    output reg [511:0] m_block_data_flat,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_block_stream TVALID" *)
    output reg m_block_ready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_block_stream TLAST" *)
    output reg m_block_valid
);

// Multiplexer logic - selects one of three input channels based on FSM controller
always @(posedge clk) begin
    if (rst) begin
        m_block_data_flat <= 512'd0;
        m_block_ready <= 1'b0;
        m_block_valid <= 1'b0;
    end else begin
        case (channel_select)
            2'd0: begin // Y channel
                m_block_data_flat <= y_block_data_flat;
                m_block_ready <= y_block_ready;
                m_block_valid <= y_block_valid;
            end
            2'd1: begin // Cb channel
                m_block_data_flat <= cb_block_data_flat;
                m_block_ready <= cb_block_ready;
                m_block_valid <= cb_block_valid;
            end
            2'd2: begin // Cr channel
                m_block_data_flat <= cr_block_data_flat;
                m_block_ready <= cr_block_ready;
                m_block_valid <= cr_block_valid;
            end
            default: begin // Invalid channel - output zeros
                m_block_data_flat <= 512'd0;
                m_block_ready <= 1'b0;
                m_block_valid <= 1'b0;
            end
        endcase
    end
end

endmodule
