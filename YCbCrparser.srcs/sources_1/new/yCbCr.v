module ycbcr_parser (
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME clk, FREQ_HZ 24000000, PHASE 0.0, ASSOCIATED_RESET rst" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    input wire clk,
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME rst, POLARITY ACTIVE_HIGH" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst RST" *)
    input wire rst,
    input wire enable,
    
    // Input from camera interface
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME pixel_stream_in, TDATA_NUM_BYTES 1, HAS_TREADY 0, HAS_TLAST 1, HAS_TUSER 1, TUSER_WIDTH 1" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 pixel_stream_in TDATA" *)
    input wire [7:0] pixel_in,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 pixel_stream_in TVALID" *)
    input wire pixel_valid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 pixel_stream_in TUSER" *)
    input wire frame_start,
    input wire line_start,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 pixel_stream_in TLAST" *)
    input wire line_end,
    
    // Output streams for each channel
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME y_stream, TDATA_NUM_BYTES 1, HAS_TREADY 0" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 y_stream TDATA" *)
    output reg [7:0] y_data,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 y_stream TVALID" *)
    output reg y_valid,
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME cb_stream, TDATA_NUM_BYTES 1, HAS_TREADY 0" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 cb_stream TDATA" *)
    output reg [7:0] cb_data,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 cb_stream TVALID" *)
    output reg cb_valid,
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME cr_stream, TDATA_NUM_BYTES 1, HAS_TREADY 0" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 cr_stream TDATA" *)
    output reg [7:0] cr_data,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 cr_stream TVALID" *)
    output reg cr_valid,
    
    // Control signals
    (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 parsing_active DATA" *)
    output reg parsing_active
);

// YCbCr 4:2:2 format: Y0 Cb Y1 Cr Y2 Cb Y3 Cr...
// Every 4 bytes = 2 Y samples, 1 Cb sample, 1 Cr sample
reg [1:0] current_channel;
localparam PARSE_Y0 = 2'b00;
localparam PARSE_CB = 2'b01;
localparam PARSE_Y1 = 2'b10;
localparam PARSE_CR = 2'b11;

reg [1:0] parse_state;
reg [7:0] pixel_buffer;

always @(posedge clk) begin
    if (rst) begin
        parse_state <= PARSE_Y0;
        y_data <= 0;
        y_valid <= 0;
        cb_data <= 0;
        cb_valid <= 0;
        cr_data <= 0;
        cr_valid <= 0;
        current_channel <= 0;
        parsing_active <= 0;
        pixel_buffer <= 0;
    end else begin
        // Default values
        y_valid <= 0;
        cb_valid <= 0;
        cr_valid <= 0;
        
        if (frame_start) begin
            parse_state <= PARSE_Y0;
            parsing_active <= 1;
        end
        if (line_end) begin
            parse_state <= PARSE_Y0;
        end
        
        if (enable && parsing_active && pixel_valid) begin
            case (parse_state)
                PARSE_Y0: begin
                    y_data <= pixel_in;
                    y_valid <= 1;
                    current_channel <= 0; // Y channel
                    parse_state <= PARSE_CB;
                end
                
                PARSE_CB: begin
                    cb_data <= pixel_in;
                    cb_valid <= 1;
                    current_channel <= 1; // Cb channel
                    parse_state <= PARSE_Y1;
                end
                
                PARSE_Y1: begin
                    y_data <= pixel_in;
                    y_valid <= 1;
                    current_channel <= 0; // Y channel
                    parse_state <= PARSE_CR;
                end
                
                PARSE_CR: begin
                    cr_data <= pixel_in;
                    cr_valid <= 1;
                    current_channel <= 2; // Cr channel
                    parse_state <= PARSE_Y0;
                end
                
                default: parse_state <= PARSE_Y0;
            endcase
        end
    end
end

endmodule
