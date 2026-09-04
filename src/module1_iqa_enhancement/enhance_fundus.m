function [enhancedGray, enhancedRGB, greenChannel] = enhance_fundus(img, options)
% ENHANCE_FUNDUS Adaptive contrast enhancement and background illumination normalization
% for retinal fundus photography.
% Isolates the high-contrast green absorption channel, applies Rayleigh CLAHE,
% and normalizes non-uniform illumination for accurate lesion and vessel segmentation.
%
% Syntax:
%   [enhancedGray, enhancedRGB, greenChannel] = enhance_fundus(img)
%   [enhancedGray, enhancedRGB, greenChannel] = enhance_fundus(img, options)
%
% Inputs:
%   img          - RGB retinal fundus image (uint8 or double [0, 1])
%   options      - (Optional) Struct with fields:
%                  .clipLimit    - CLAHE clipping limit (default: 0.02)
%                  .numTiles     - CLAHE tile grid size (default: [8, 8])
%                  .bgDiskRadius - Structuring element radius for illumination flattening (default: 30)
%
% Outputs:
%   enhancedGray - Enhanced green channel (double [0, 1]) optimized for segmentation
%   enhancedRGB  - Full-color enhanced RGB fundus image for doctor visualization
%   greenChannel - Raw extracted green channel
%
% SIH Problem Statement 26038 | MathWorks Sponsored Prototype

    if nargin < 2
        options = struct();
    end
    if ~isfield(options, 'clipLimit'),    options.clipLimit    = 0.02; end
    if ~isfield(options, 'numTiles'),     options.numTiles     = [8, 8]; end
    if ~isfield(options, 'bgDiskRadius'), options.bgDiskRadius = 30; end

    % Convert to double [0, 1]
    if isa(img, 'uint8')
        imgDbl = double(img) / 255.0;
    else
        imgDbl = double(img);
        if max(imgDbl(:)) > 1.0
            imgDbl = imgDbl / max(imgDbl(:));
        end
    end

    % 1. Extract High-Contrast Green Channel
    % Hemoglobin absorbs strongly in green (540-570 nm), maximizing vessel & lesion contrast
    if size(imgDbl, 3) == 3
        greenChannel = imgDbl(:,:,2);
    else
        greenChannel = imgDbl;
    end

    % Field of View mask
    fovMask = greenChannel > 0.04;
    fovMask = imfill(fovMask, 'holes');
    seSmall = strel('disk', 4);
    fovMask = imerode(fovMask, seSmall);

    % 2. Background Illumination Normalization (Morphological Top-Hat / Opening)
    % Non-uniform illumination (vignetting, central bright flash) is estimated
    % using a large disk structuring element and subtracted
    seBg = strel('disk', options.bgDiskRadius);
    background = imopen(greenChannel, seBg);
    
    % Illumination-flattened green channel
    flatGreen = greenChannel - background;
    % Rescale to [0, 1] within FOV
    flatMin = min(flatGreen(fovMask));
    flatMax = max(flatGreen(fovMask));
    if flatMax > flatMin
        flatGreen = (flatGreen - flatMin) / (flatMax - flatMin);
    end
    flatGreen(~fovMask) = 0;

    % 3. Contrast-Limited Adaptive Histogram Equalization (CLAHE)
    % Rayleigh distribution prevents over-amplification of noise in dark regions
    % and enhances subtle microaneurysms and hard exudates
    if exist('adapthisteq', 'file') == 2
        try
            enhancedGray = adapthisteq(flatGreen, ...
                'ClipLimit', options.clipLimit, ...
                'Distribution', 'rayleigh', ...
                'NumTiles', options.numTiles);
        catch
            % Fallback if toolbox adapthisteq fails
            enhancedGray = local_contrast_enhance(flatGreen);
        end
    else
        enhancedGray = local_contrast_enhance(flatGreen);
    end

    enhancedGray = enhancedGray .* double(fovMask);

    % 4. Generate Enhanced Color RGB Composite for Doctor's Screen
    if size(imgDbl, 3) == 3
        % Enhance luminance channel in HSV space for natural color preservation
        if exist('rgb2hsv', 'file') == 2 && exist('hsv2rgb', 'file') == 2
            hsv = rgb2hsv(imgDbl);
            hsv(:,:,3) = enhancedGray;
            enhancedRGB = hsv2rgb(hsv);
        else
            % Direct RGB scaling
            ratio = (enhancedGray + 0.05) ./ (greenChannel + 0.05);
            enhancedRGB = zeros(size(imgDbl));
            for c = 1:3
                enhancedRGB(:,:,c) = min(1.0, max(0.0, imgDbl(:,:,c) .* ratio));
            end
        end
        enhancedRGB = min(1.0, max(0.0, enhancedRGB));
    else
        enhancedRGB = repmat(enhancedGray, [1, 1, 3]);
    end
end

% -------------------------------------------------------------------------
% Local Contrast Enhancement Fallback (Uncalibrated Environments)
% -------------------------------------------------------------------------
function out = local_contrast_enhance(in)
    % Gamma + unsharp masking
    gammaVal = 0.85;
    inGamma = in .^ gammaVal;
    h = fspecial_gaussian([15, 15], 3.0);
    blurred = conv2(inGamma, h, 'same');
    highPass = inGamma - blurred;
    out = inGamma + 1.2 * highPass;
    out = min(1.0, max(0.0, out));
end

function h = fspecial_gaussian(p2, p3)
    siz = (p2 - 1) / 2;
    std = p3;
    [x, y] = meshgrid(-siz(2):siz(2), -siz(1):siz(1));
    arg = -(x.*x + y.*y) / (2 * std * std);
    h = exp(arg);
    h(h < eps * max(h(:))) = 0;
    sumh = sum(h(:));
    if sumh ~= 0
        h = h / sumh;
    end
end
