function lesions = detect_lesions(img, enhancedGray, vesselMask, options)
% DETECT_LESIONS Segments critical diabetic retinopathy lesions:
% 1. Localizes and masks the Optic Disc (OD) to eliminate anatomical false positives.
% 2. Detects Bright Lesions: Hard Exudates (lipid leakage indicative of macular edema).
% 3. Detects Dark Lesions: Microaneurysms & dot hemorrhages (early vascular breakdown).
%
% Syntax:
%   lesions = detect_lesions(img, enhancedGray, vesselMask)
%   lesions = detect_lesions(img, enhancedGray, vesselMask, options)
%
% Inputs:
%   img          - Original RGB fundus image (uint8 or double [0, 1])
%   enhancedGray - Enhanced green channel (double [0, 1])
%   vesselMask   - Binary mask of segmented blood vessels (logical)
%   options      - (Optional) Struct with parameter overrides
%
% Outputs:
%   lesions      - Struct containing:
%                  .odMask             : Optic disc exclusion mask
%                  .odCenter           : [X, Y] optic disc center coordinates
%                  .exudateMask        : Hard exudates binary mask
%                  .microaneurysmMask  : Microaneurysms & hemorrhages binary mask
%                  .lesionOverlay      : RGB image with segmented lesions highlighted
%                  .exudateCount       : Number of detected hard exudate clusters
%                  .exudateArea        : Total hard exudate pixel area
%                  .microaneurysmCount : Count of detected microaneurysms
%                  .hemorrhageCount    : Count of larger blot hemorrhages
%
% SIH Problem Statement 26038 | MathWorks Sponsored Prototype

    if nargin < 4
        options = struct();
    end
    if ~isfield(options, 'odDiskRadius'),       options.odDiskRadius       = 75; end
    if ~isfield(options, 'maDiskRadius'),       options.maDiskRadius       = 6;  end
    if ~isfield(options, 'exudateThreshold'),   options.exudateThreshold   = 0.72; end
    if ~isfield(options, 'minExudateArea'),     options.minExudateArea     = 4;  end
    if ~isfield(options, 'maxExudateArea'),     options.maxExudateArea     = 450; end

    % Standardize input to double [0, 1]
    if isa(img, 'uint8')
        imgDbl = double(img) / 255.0;
    else
        imgDbl = double(img);
        if max(imgDbl(:)) > 1.0
            imgDbl = imgDbl / max(imgDbl(:));
        end
    end

    % Standardize resolution to 512x512 for sub-second execution
    if size(imgDbl, 1) > 512 || size(imgDbl, 2) > 512
        imgDbl = imresize(imgDbl, [512, 512]);
    end
    if size(enhancedGray, 1) > 512 || size(enhancedGray, 2) > 512
        enhancedGray = imresize(enhancedGray, [512, 512]);
    end
    if size(vesselMask, 1) > 512 || size(vesselMask, 2) > 512
        vesselMask = imresize(vesselMask, [512, 512]);
    end

    [H, W, ~] = size(imgDbl);
    R = imgDbl(:,:,1);
    G = imgDbl(:,:,2);
    B = imgDbl(:,:,3);

    % Retinal Field of View mask
    fovMask = (G > 0.04) | (R > 0.04);
    fovMask = imfill(fovMask, 'holes');
    fovMask = imerode(fovMask, strel('disk', 12)); % Margin from boundary

    % ---------------------------------------------------------------------
    % Step 1: Optic Disc (OD) Localization & Masking
    % ---------------------------------------------------------------------
    redBright = R .* double(fovMask);
    hSm = fspecial_gaussian([45, 45], 12.0);
    smoothRed = conv2(redBright, hSm, 'same');
    
    % Find peak intensity cluster
    [~, maxIdx] = max(smoothRed(:));
    [odY, odX] = ind2sub([H, W], maxIdx);

    % Generate circular OD exclusion mask with generous peripapillary buffer
    [gridX, gridY] = meshgrid(1:W, 1:H);
    distToOD = sqrt((gridX - odX).^2 + (gridY - odY).^2);
    odMask = distToOD <= options.odDiskRadius;
    odMaskDilated = distToOD <= (options.odDiskRadius * 1.25); % Safety buffer

    % ---------------------------------------------------------------------
    % Step 2: Bright Lesions (Hard Exudates) Detection
    % ---------------------------------------------------------------------
    % Hard exudates: Bright yellow-white lipid/protein deposits outside optic disc
    gMed = medfilt2(G, [25, 25]);
    diffG = G - gMed;
    brightCand = (diffG > 0.08) & (R > 0.55) & (G > 0.35) & (B < 0.40) & (~odMaskDilated) & fovMask;

    % Area filtering for hard exudates
    CC_ex = bwconncomp(brightCand);
    exudateMask = false(H, W);
    exudateCount = 0;
    for k = 1:CC_ex.NumObjects
        numP = numel(CC_ex.PixelIdxList{k});
        if numP >= options.minExudateArea && numP <= options.maxExudateArea
            exudateMask(CC_ex.PixelIdxList{k}) = true;
            exudateCount = exudateCount + 1;
        end
    end
    exudateArea = sum(exudateMask(:));

    % ---------------------------------------------------------------------
    % Step 3: Dark Lesions (Microaneurysms & Hemorrhages) Detection
    % ---------------------------------------------------------------------
    seMA = strel('disk', options.maDiskRadius);
    bottomHat = imbothat(G, seMA);
    bottomHat(~fovMask) = 0;

    % Relative contrast against local background
    gSmooth = conv2(G, fspecial_gaussian([25, 25], 5.0), 'same');
    relBotHat = bottomHat ./ max(0.04, gSmooth);

    % Gentle vessel buffer (1 pixel) to avoid capturing vessel margins
    seVesselBuf = strel('disk', 1);
    dilatedVessels = imdilate(vesselMask, seVesselBuf);

    % Candidates are dark focal points not belonging to the main vessel tree
    maCand = (relBotHat > 0.12) & (~dilatedVessels) & (~odMaskDilated) & fovMask;

    % Connected component filtering by area and circularity
    CC_ma = bwconncomp(maCand);
    maProps = regionprops(CC_ma, 'Area', 'Eccentricity', 'PixelIdxList');
    
    microaneurysmMask = false(H, W);
    hemorrhageMask = false(H, W);
    maCount = 0;
    hemoCount = 0;

    for k = 1:length(maProps)
        area = maProps(k).Area;
        ecc = maProps(k).Eccentricity;
        % Microaneurysms: Small circular spots (2 <= area <= 40, eccentricity < 0.88)
        if area >= 2 && area <= 45 && ecc < 0.88
            microaneurysmMask(maProps(k).PixelIdxList) = true;
            maCount = maCount + 1;
        % Dot/blot hemorrhages: Medium-sized dark spots (46 <= area <= 300)
        elseif area > 45 && area <= 300
            hemorrhageMask(maProps(k).PixelIdxList) = true;
            hemoCount = hemoCount + 1;
        end
    end

    % ---------------------------------------------------------------------
    % Step 4: Clinical Diagnostic Overlay
    % ---------------------------------------------------------------------
    % Base image: enhanced fundus
    overlay = imgDbl;
    
    % Overlay Vessels in Cyan [0, 0.85, 0.9]
    vDil = imdilate(vesselMask, strel('disk', 1));
    for c = 1:3
        ch = overlay(:,:,c);
        if c == 1, ch(vDil) = 0.0; end
        if c == 2, ch(vDil) = 0.85; end
        if c == 3, ch(vDil) = 0.95; end
        overlay(:,:,c) = ch;
    end

    % Overlay Hard Exudates in High-Visibility Bright Yellow [1, 0.9, 0] with boundary outline
    exDil = imdilate(exudateMask, strel('disk', 2));
    exBound = exDil & ~exudateMask;
    for c = 1:3
        ch = overlay(:,:,c);
        if c == 1, ch(exDil) = 1.0; end
        if c == 2, ch(exDil) = 0.92; end
        if c == 3, ch(exDil) = 0.05; end
        overlay(:,:,c) = ch;
    end

    % Overlay Microaneurysms / Hemorrhages in Intense Magenta/Red [1, 0.1, 0.4]
    darkLesions = microaneurysmMask | hemorrhageMask;
    maDil = imdilate(darkLesions, strel('disk', 2));
    for c = 1:3
        ch = overlay(:,:,c);
        if c == 1, ch(maDil) = 1.0; end
        if c == 2, ch(maDil) = 0.1; end
        if c == 3, ch(maDil) = 0.35; end
        overlay(:,:,c) = ch;
    end

    % Draw Optic Disc contour in Green [0.1, 0.95, 0.2]
    odPerim = bwperim(odMask);
    odPerimDil = imdilate(odPerim, strel('disk', 2));
    for c = 1:3
        ch = overlay(:,:,c);
        if c == 1, ch(odPerimDil) = 0.1; end
        if c == 2, ch(odPerimDil) = 0.95; end
        if c == 3, ch(odPerimDil) = 0.2; end
        overlay(:,:,c) = ch;
    end

    % Package outputs
    lesions.odMask             = odMask;
    lesions.odCenter           = [odX, odY];
    lesions.exudateMask        = exudateMask;
    lesions.microaneurysmMask  = microaneurysmMask;
    lesions.hemorrhageMask     = hemorrhageMask;
    lesions.lesionOverlay      = overlay;
    lesions.exudateCount       = exudateCount;
    lesions.exudateArea        = exudateArea;
    lesions.microaneurysmCount = maCount;
    lesions.hemorrhageCount    = hemoCount;
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
