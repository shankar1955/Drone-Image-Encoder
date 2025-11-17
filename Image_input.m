% Camera Signal Generator for Verilog Testbench
% Converts image pixels to camera interface timing signals
% Outputs: cam_pclk, cam_vsync, cam_hsync, cam_data

clear all; close all; clc;

%% Configuration Parameters
IMG_WIDTH = 640;
IMG_HEIGHT = 480;
PIXEL_BITS = 8;

% Timing parameters (VGA standard)
H_FRONT_PORCH = 16;
H_SYNC_PULSE = 96;
H_BACK_PORCH = 48;
V_FRONT_PORCH = 10;
V_SYNC_PULSE = 2;
V_BACK_PORCH = 33;

TOTAL_H = IMG_WIDTH + H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH;
TOTAL_V = IMG_HEIGHT + V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH;

%% Create or Load Test Image
% Option 1: Generate checkerboard pattern
img = uint8(checkerboard(32, ceil(IMG_HEIGHT/64), ceil(IMG_WIDTH/64)) * 255);
img = imresize(img, [IMG_HEIGHT, IMG_WIDTH]);

% Option 2: Generate gradient pattern (uncomment to use)
% [X, Y] = meshgrid(1:IMG_WIDTH, 1:IMG_HEIGHT);
% img = uint8((X + Y) / (IMG_WIDTH + IMG_HEIGHT) * 255);

% Option 3: Load your own image (uncomment to use)
% img = imread('your_image.png');
% if size(img, 3) == 3
%     img = rgb2gray(img);
% end
% img = imresize(img, [IMG_HEIGHT, IMG_WIDTH]);

%% Generate Camera Signals
total_samples = TOTAL_H * TOTAL_V;
cam_pclk = zeros(1, total_samples);
cam_vsync = zeros(1, total_samples);
cam_hsync = zeros(1, total_samples);
cam_data = zeros(1, total_samples);

sample_idx = 1;

fprintf('Generating camera signals...\n');

for v = 1:TOTAL_V
    for h = 1:TOTAL_H
        % Pixel clock (active high during each pixel)
        cam_pclk(sample_idx) = 1;
        
        % Vertical sync (active during first V_SYNC_PULSE lines)
        if v <= V_SYNC_PULSE
            cam_vsync(sample_idx) = 1;
        else
            cam_vsync(sample_idx) = 0;
        end
        
        % Horizontal sync (active during first H_SYNC_PULSE pixels of each line)
        if h <= H_SYNC_PULSE
            cam_hsync(sample_idx) = 1;
        else
            cam_hsync(sample_idx) = 0;
        end
        
        % Pixel data (valid only during active video region)
        v_active = v > (V_SYNC_PULSE + V_BACK_PORCH) && v <= (V_SYNC_PULSE + V_BACK_PORCH + IMG_HEIGHT);
        h_active = h > (H_SYNC_PULSE + H_BACK_PORCH) && h <= (H_SYNC_PULSE + H_BACK_PORCH + IMG_WIDTH);
        
        if v_active && h_active
            row = v - (V_SYNC_PULSE + V_BACK_PORCH);
            col = h - (H_SYNC_PULSE + H_BACK_PORCH);
            cam_data(sample_idx) = img(row, col);
        else
            cam_data(sample_idx) = 0;
        end
        
        sample_idx = sample_idx + 1;
    end
end

fprintf('Total samples generated: %d\n', total_samples);

%% Save Combined Stimulus File
fprintf('Saving combined stimulus file...\n');
fid = fopen('cam_stimulus.txt', 'w');
for i = 1:total_samples
    fprintf(fid, '%d %d %d %d\n', cam_pclk(i), cam_vsync(i), cam_hsync(i), cam_data(i));
end
fclose(fid);

%% Save Individual Signal Files
fprintf('Saving individual signal files...\n');
dlmwrite('cam_pclk.txt', cam_pclk', 'delimiter', '\n', 'precision', '%d');
dlmwrite('cam_vsync.txt', cam_vsync', 'delimiter', '\n', 'precision', '%d');
dlmwrite('cam_hsync.txt', cam_hsync', 'delimiter', '\n', 'precision', '%d');
dlmwrite('cam_data.txt', cam_data', 'delimiter', '\n', 'precision', '%d');

%% Save Binary Format (for faster loading)
fprintf('Saving binary format...\n');
save('cam_signals.mat', 'cam_pclk', 'cam_vsync', 'cam_hsync', 'cam_data', ...
     'IMG_WIDTH', 'IMG_HEIGHT', 'TOTAL_H', 'TOTAL_V');

%% Generate Verilog Testbench Memory Initialization Files
fprintf('Saving Verilog memory initialization files...\n');

% cam_pclk.mem
fid = fopen('cam_pclk.mem', 'w');
for i = 1:total_samples
    fprintf(fid, '%01X\n', cam_pclk(i));
end
fclose(fid);

% cam_vsync.mem
fid = fopen('cam_vsync.mem', 'w');
for i = 1:total_samples
    fprintf(fid, '%01X\n', cam_vsync(i));
end
fclose(fid);

% cam_hsync.mem
fid = fopen('cam_hsync.mem', 'w');
for i = 1:total_samples
    fprintf(fid, '%01X\n', cam_hsync(i));
end
fclose(fid);

% cam_data.mem
fid = fopen('cam_data.mem', 'w');
for i = 1:total_samples
    fprintf(fid, '%02X\n', cam_data(i));
end
fclose(fid);

%% Plot Signals for Verification
fprintf('Generating verification plots...\n');

% Plot first 10 lines for visualization
samples_to_plot = min(TOTAL_H * 10, total_samples);

figure('Position', [100 100 1200 800]);

subplot(4,1,1);
plot(1:samples_to_plot, cam_pclk(1:samples_to_plot), 'LineWidth', 1.5);
title('cam\_pclk (Pixel Clock)', 'FontSize', 12);
ylabel('Value');
ylim([-0.5 1.5]);
grid on;

subplot(4,1,2);
plot(1:samples_to_plot, cam_vsync(1:samples_to_plot), 'LineWidth', 1.5);
title('cam\_vsync (Vertical Sync)', 'FontSize', 12);
ylabel('Value');
ylim([-0.5 1.5]);
grid on;

subplot(4,1,3);
plot(1:samples_to_plot, cam_hsync(1:samples_to_plot), 'LineWidth', 1.5);
title('cam\_hsync (Horizontal Sync)', 'FontSize', 12);
ylabel('Value');
ylim([-0.5 1.5]);
grid on;

subplot(4,1,4);
plot(1:samples_to_plot, cam_data(1:samples_to_plot), 'LineWidth', 1);
title('cam\_data (Pixel Data)', 'FontSize', 12);
ylabel('Value');
xlabel('Sample Number');
grid on;

saveas(gcf, 'camera_signals_plot.png');

% Display original image
figure('Position', [100 100 800 600]);
imshow(img);
title('Input Image Pattern', 'FontSize', 14);
saveas(gcf, 'input_image.png');

%% Summary
fprintf('\n=== Generation Complete ===\n');
fprintf('Image Size: %d x %d\n', IMG_WIDTH, IMG_HEIGHT);
fprintf('Total Samples: %d\n', total_samples);
fprintf('Total Lines: %d (Active: %d)\n', TOTAL_V, IMG_HEIGHT);
fprintf('Total Pixels per Line: %d (Active: %d)\n', TOTAL_H, IMG_WIDTH);
fprintf('\nFiles Generated:\n');
fprintf('  - cam_stimulus.txt (combined format)\n');
fprintf('  - cam_pclk.txt, cam_vsync.txt, cam_hsync.txt, cam_data.txt\n');
fprintf('  - cam_pclk.mem, cam_vsync.mem, cam_hsync.mem, cam_data.mem (hex format)\n');
fprintf('  - cam_signals.mat (MATLAB binary)\n');
fprintf('  - camera_signals_plot.png\n');
fprintf('  - input_image.png\n');
fprintf('=========================\n');