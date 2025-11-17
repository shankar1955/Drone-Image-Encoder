module sccb_controller (
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME clk, FREQ_HZ 100000000, PHASE 0.0, ASSOCIATED_RESET rst" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    input wire clk,              // 100MHz system clock
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME rst, POLARITY ACTIVE_HIGH" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst RST" *)
    input wire rst,              // Reset signal
    input wire start_config,     // Start configuration
    (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 config_done DATA" *)
    output reg config_done,      // Configuration complete
    (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 config_busy DATA" *)
    output reg config_busy,      // Configuration in progress
    
    // SCCB Interface
    (* X_INTERFACE_INFO = "xilinx.com:signal:bidirectional:1.0 sccb_sda DATA" *)
    inout wire sccb_sda,         // SCCB data line
    (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 sccb_scl DATA" *)
    output reg sccb_scl          // SCCB clock line
);

// SCCB timing parameters (100kHz SCCB clock)
parameter SCCB_CLK_DIV = 500;   // 100MHz / (2 * 100kHz) = 500

// Configuration registers for YCbCr 4:2:2 output
parameter NUM_CONFIGS = 12;
reg [15:0] config_data [0:NUM_CONFIGS-1];

// FIXED: Make device_addr a wire instead of reg assigned in always block
wire [7:0] device_addr = 8'h42;  // OV7670 I2C address

// Initialize camera for YCbCr 4:2:2 output
initial begin
    config_data[0]  = {8'h12, 8'h80}; // COM7 - Reset all registers
    config_data[1]  = {8'h12, 8'h02}; // COM7 - YUV output format
    config_data[2]  = {8'h11, 8'h00}; // CLKRC - Use external clock directly
    config_data[3]  = {8'h6B, 8'h4A}; // DBLV - Enable PLL
    config_data[4]  = {8'h3A, 8'h04}; // TSLB - Set UV auto adjust
    config_data[5]  = {8'h40, 8'hD0}; // COM15 - Output range [16-235]
    config_data[6]  = {8'h8C, 8'h00}; // RGB444 - Disable RGB444
    config_data[7]  = {8'h04, 8'h00}; // COM1 - Disable CCIR656
    config_data[8]  = {8'h14, 8'h18}; // COM9 - Automatic gain ceiling
    config_data[9]  = {8'h4F, 8'h80}; // MTX1 - Color matrix
    config_data[10] = {8'h50, 8'h80}; // MTX2 - Color matrix
    config_data[11] = {8'h51, 8'h00}; // MTX3 - Color matrix
end

// State machine states
localparam IDLE = 3'b000;
localparam START = 3'b001;
localparam DEVICE_ADDR = 3'b010;
localparam REG_ADDR = 3'b011;
localparam REG_DATA = 3'b100;
localparam STOP = 3'b101;
localparam WAIT_STATE = 3'b110;

reg [2:0] state;
reg [9:0] clk_divider;
reg [3:0] config_index;
reg [3:0] bit_index;
reg [7:0] current_reg_addr, current_reg_data;  // These need proper reset!
reg sccb_clk_en;
reg sda_out, sda_oe;

// Generate SCCB clock enable
always @(posedge clk) begin
    if (rst) begin
        clk_divider <= 0;
        sccb_clk_en <= 0;
    end else begin
        if (clk_divider >= SCCB_CLK_DIV - 1) begin
            clk_divider <= 0;
            sccb_clk_en <= 1;
        end else begin
            clk_divider <= clk_divider + 1;
            sccb_clk_en <= 0;
        end
    end
end

// FIXED: Main state machine with proper reset for all registers
always @(posedge clk) begin
    if (rst) begin
        state <= IDLE;
        config_done <= 0;
        config_busy <= 0;
        config_index <= 0;
        sccb_scl <= 1;
        sda_out <= 1;
        sda_oe <= 0;
        bit_index <= 0;
        
        // CRITICAL FIX: Add reset values for these registers
        current_reg_addr <= 8'h00;
        current_reg_data <= 8'h00;
        
    end else begin
        case (state)
            IDLE: begin
                config_busy <= 0;
                if (start_config) begin
                    config_busy <= 1;
                    config_done <= 0;
                    config_index <= 0;
                    sccb_scl <= 1;
                    sda_out <= 1;
                    sda_oe <= 0;
                    bit_index <= 0;
                    state <= START;
                end
            end
            
            START: begin
                if (sccb_clk_en) begin
                    // Start condition
                    sda_out <= 0;
                    sda_oe <= 1;
                    sccb_scl <= 1;
                    
                    // FIXED: These assignments are now safe because registers have reset values
                    current_reg_addr <= config_data[config_index][15:8];
                    current_reg_data <= config_data[config_index][7:0];
                    
                    state <= DEVICE_ADDR;
                    bit_index <= 7;
                end
            end
            
            DEVICE_ADDR: begin
                if (sccb_clk_en) begin
                    sccb_scl <= ~sccb_scl;
                    if (!sccb_scl) begin // Falling edge
                        if (bit_index == 0) begin
                            sda_out <= 1'b0; // Write bit (R/W = 0)
                        end else begin
                            sda_out <= device_addr[bit_index]; // Device address bits
                        end
                        
                        if (bit_index == 0) begin
                            state <= REG_ADDR;
                            bit_index <= 7;
                        end else begin
                            bit_index <= bit_index - 1;
                        end
                    end
                end
            end
            
            REG_ADDR: begin
                if (sccb_clk_en) begin
                    sccb_scl <= ~sccb_scl;
                    if (!sccb_scl) begin // Falling edge
                        sda_out <= current_reg_addr[bit_index];
                        
                        if (bit_index == 0) begin
                            state <= REG_DATA;
                            bit_index <= 7;
                        end else begin
                            bit_index <= bit_index - 1;
                        end
                    end
                end
            end
            
            REG_DATA: begin
                if (sccb_clk_en) begin
                    sccb_scl <= ~sccb_scl;
                    if (!sccb_scl) begin // Falling edge
                        sda_out <= current_reg_data[bit_index];
                        
                        if (bit_index == 0) begin
                            state <= STOP;
                        end else begin
                            bit_index <= bit_index - 1;
                        end
                    end
                end
            end
            
            STOP: begin
                if (sccb_clk_en) begin
                    // Stop condition
                    sccb_scl <= 1;
                    sda_out <= 1;
                    
                    if (config_index >= NUM_CONFIGS - 1) begin
                        config_done <= 1;
                        config_busy <= 0;
                        state <= IDLE;
                    end else begin
                        config_index <= config_index + 1;
                        state <= WAIT_STATE;
                    end
                end
            end
            
            WAIT_STATE: begin
                if (sccb_clk_en) begin
                    state <= START;
                end
            end
            
            default: begin
                state <= IDLE;
            end
        endcase
    end
end

// Tristate control for SDA
assign sccb_sda = sda_oe ? sda_out : 1'bz;

endmodule
