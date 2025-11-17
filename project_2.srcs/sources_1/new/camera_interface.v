module camera_interface (
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME pix_clk, FREQ_HZ 24000000, PHASE 0.0, CLK_DOMAIN camera_interface_pix_clk, ASSOCIATED_RESET rst, ASSOCIATED_BUSIF pixel_stream" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 pix_clk CLK" *)
    input wire pix_clk,       // Clock from Clocking Wizard for camera domain
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME rst, POLARITY ACTIVE_HIGH" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst RST" *)
    input wire rst,           // Active-high reset
    input wire enable,        // Enable capture
    
    // OV7670 Camera Interface
    input wire cam_pclk,      // Camera pixel clock
    input wire cam_vsync,     // Vertical sync
    input wire cam_href,      // Horizontal reference
    input wire [7:0] cam_data, // Camera data (YCbCr 4:2:2)
    
    // Output to YCbCr parser
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME pixel_stream, TDATA_NUM_BYTES 1, HAS_TREADY 0, HAS_TLAST 1, HAS_TUSER 1, TUSER_WIDTH 1" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 pixel_stream TDATA" *)
    output reg [7:0] pixel_out,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 pixel_stream TVALID" *)
    output reg pixel_valid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 pixel_stream TUSER" *)
    output reg frame_start,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 pixel_stream TLAST" *)
    output reg line_end,
    output reg line_start,
    
    (* X_INTERFACE_INFO = "xilinx.com:signal:status:1.0 capturing SIGNAL" *)
    output reg capturing
);

// Synchronize camera signals to pixel clock domain
(* ASYNC_REG = "TRUE" *) reg cam_pclk_d1, cam_pclk_d2;
(* ASYNC_REG = "TRUE" *) reg cam_vsync_d1, cam_vsync_d2;
(* ASYNC_REG = "TRUE" *) reg cam_href_d1, cam_href_d2;
reg [7:0] cam_data_d1;
reg frame_end;

// Status signals
reg [15:0] pixel_count;

// Edge detection
wire pclk_posedge = cam_pclk_d1 & ~cam_pclk_d2;
wire vsync_posedge = cam_vsync_d1 & ~cam_vsync_d2;
wire vsync_negedge = ~cam_vsync_d1 & cam_vsync_d2;
wire href_posedge = cam_href_d1 & ~cam_href_d2;
wire href_negedge = ~cam_href_d1 & cam_href_d2;

// State machine states
localparam IDLE = 2'b00;
localparam CAPTURE = 2'b01;
localparam FRAME_END_STATE = 2'b10;

reg [1:0] state;

// Synchronize camera signals
always @(posedge pix_clk) begin
    if (rst) begin
        cam_pclk_d1 <= 0;
        cam_pclk_d2 <= 0;
        cam_vsync_d1 <= 0;
        cam_vsync_d2 <= 0;
        cam_href_d1 <= 0;
        cam_href_d2 <= 0;
        cam_data_d1 <= 0;
    end else begin
        cam_pclk_d2 <= cam_pclk_d1;
        cam_pclk_d1 <= cam_pclk;
        cam_vsync_d2 <= cam_vsync_d1;
        cam_vsync_d1 <= cam_vsync;
        cam_href_d2 <= cam_href_d1;
        cam_href_d1 <= cam_href;
        cam_data_d1 <= cam_data;
    end
end

// Main state machine and pixel capture
always @(posedge pix_clk) begin
    if (rst) begin
        state <= IDLE;
        pixel_out <= 0;
        pixel_valid <= 0;
        frame_start <= 0;
        line_start <= 0;
        line_end <= 0;
        frame_end <= 0;
        pixel_count <= 0;
        capturing <= 0;
    end else begin
        // Default values
        pixel_valid <= 0;
        frame_start <= 0;
        line_start <= 0;
        line_end <= 0;
        frame_end <= 0;
        
        case (state)
            IDLE: begin
                capturing <= 0;
                pixel_count <= 0;
                if (enable && vsync_posedge) begin
                    state <= CAPTURE;
                    capturing <= 1;
                    frame_start <= 1;
                end
            end
            
            CAPTURE: begin
                // Detect line start
                if (href_posedge) begin
                    line_start <= 1;
                end
                if (href_negedge) begin
                    line_end <= 1;
                end
                
                // Capture pixel on positive edge of pixel clock
                if (pclk_posedge && cam_href_d1) begin
                    pixel_out <= cam_data_d1;
                    pixel_valid <= 1;
                    pixel_count <= pixel_count + 1;
                end
                
                // Check for frame end
                if (vsync_negedge) begin
                    state <= FRAME_END_STATE;
                end
            end
            
            FRAME_END_STATE: begin
                frame_end <= 1;
                capturing <= 0;
                state <= IDLE;
            end
            
            default: state <= IDLE;
        endcase
    end
end

endmodule
