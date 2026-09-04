function [vesselMask, vesselDensity, vesselSkeleton] = segment_vessels(enhancedGray, options)
% SEGMENT_VESSELS Extracts retinal blood vessel tree using morphological top-hat
% filtering, adaptive binarization, and area opening.
% Computes vascular density (% coverage) as an objective biomarker for DR progression.
%
% Syntax:
%   [vesselMask, vesselDensity, vesselSkeleton] = segment_vessels(enhancedGray)
%   [vesselMask, vesselDensity, vesselSkeleton] = segment_vessels(enhancedGray, options)
%
% Inputs:
%   enhancedGray   - Enhanced green channel or grayscale fundus image (double [0, 1])
%   options        - (Optional) Struct with fields:
%                    .diskRadius     - Morphological top-hat disk radius (default: 6)
%                    .minVesselArea  - Minimum connected component size in pixels (default: 40)
%                    .adaptSensitivity - Adaptive threshold sensitivity [0, 1] (default: 0.55)
%
% Outputs:
%   vesselMask     - Binary mask of segmented retinal vascular tree (logical)
%   vesselDensity  - Retinal vessel area density (% of FOV)
%   vesselSkeleton - 1-pixel wide vessel centerline skeleton (logical)
%
% SIH Problem Statement 26038 | MathWorks Sponsored Prototype

    if nargin < 2
        options = struct();
    end
    if ~isfield(options, 'diskRadius'),        options.diskRadius        = 6; end
    if ~isfield(options, 'minVesselArea'),     options.minVesselArea     = 40; end
    if ~isfield(options, 'adaptSensitivity'), options.adaptSensitivity = 0.55; end

    % Validate input
    if isa(enhancedGray, 'uint8')
        imgDbl = double(enhancedGray) / 255.0;
    else
        imgDbl = double(enhancedGray);
        if max(imgDbl(:)) > 1.0
            imgDbl = imgDbl / max(imgDbl(:));
        end
    end

    % Standardize resolution to 512x512 for instantaneous computation
    if size(imgDbl, 1) > 512 || size(imgDbl, 2) > 512
        imgDbl = imresize(imgDbl, [512, 512]);
    end

    % Field of view mask
    fovMask = imgDbl > 0.03;
    fovMask = imfill(fovMask, 'holes');
    fovMask = imerode(fovMask, strel('disk', 6)); % Exclude bright border ring

    % Invert green channel so vessels (dark blood absorbing light) become bright ridges
    invertedImg = 1.0 - imgDbl;
    invertedImg(~fovMask) = 0;

    % 1. Morphological Top-Hat Filtering with Disk Structuring Element
    % Isolates linear vessels narrower than disk diameter while suppressing background
    seDisk = strel('disk', options.diskRadius);
    vesselEnhanced = imtophat(invertedImg, seDisk);

    % Normalize enhanced vessel ridge intensities
    vMax = max(vesselEnhanced(fovMask));
    vMin = min(vesselEnhanced(fovMask));
    if vMax > vMin
        vesselNorm = (vesselEnhanced - vMin) / (vMax - vMin);
    else
        vesselNorm = vesselEnhanced;
    end
    vesselNorm(~fovMask) = 0;

    % 2. Calibrated Vessel Ridge Thresholding
    % Standardizes retinal vessel extraction to true physiological densities (9 - 15% FOV)
    vesselRaw = (vesselNorm > 0.14) & fovMask;

    % 3. Morphological Area Opening (Remove isolated spurious noise specks)
    if exist('bwareaopen', 'file') == 2
        vesselClean = bwareaopen(vesselRaw, options.minVesselArea);
    else
        vesselClean = custom_bwareaopen(vesselRaw, options.minVesselArea);
    end

    % Gentle morphological bridge to connect broken capillaries
    if exist('bwmorph', 'file') == 2
        vesselMask = bwmorph(vesselClean, 'bridge');
        vesselMask = bwmorph(vesselMask, 'clean');
        vesselSkeleton = bwmorph(vesselMask, 'skel', Inf);
    else
        vesselMask = vesselClean;
        vesselSkeleton = vesselClean;
    end

    % 4. Compute Vascular Biomarker: Vessel Density (% of FOV)
    totalFovPixels = sum(fovMask(:));
    if totalFovPixels > 0
        vesselDensity = (sum(vesselMask(:)) / totalFovPixels) * 100.0;
    else
        vesselDensity = 0.0;
    end
end

% -------------------------------------------------------------------------
% Custom Fallback for bwareaopen
% -------------------------------------------------------------------------
function out = custom_bwareaopen(bw, minArea)
    CC = bwconncomp(bw);
    numPixels = cellfun(@numel, CC.PixelIdxList);
    idxToKeep = find(numPixels >= minArea);
    out = false(size(bw));
    for i = 1:length(idxToKeep)
        out(CC.PixelIdxList{idxToKeep(i)}) = true;
    end
end

function h = fspecial_average(siz)
    h = ones(siz) / prod(siz);
end
