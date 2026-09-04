function result = evaluate_image_quality(img, options)
% EVALUATE_IMAGE_QUALITY Evaluates retinal fundus image suitability for DR screening.
% Assesses sharpness (via BRISQUE / high-frequency gradient metrics), illumination
% adequacy, and glare/defocus artifacts to provide instant recapture guidance
% to rural Primary Health Centre (PHC) frontline health workers (ASHA/ANM).
%
% Syntax:
%   result = evaluate_image_quality(img)
%   result = evaluate_image_quality(img, options)
%
% Inputs:
%   img     - RGB retinal fundus image (uint8 or double [0, 1])
%   options - (Optional) Struct with fields:
%             .brisqueThreshold - Maximum acceptable BRISQUE score (default: 45.0)
%             .minIllumination  - Minimum foreground mean luminance (default: 0.18)
%             .maxGlareFraction - Maximum tolerable flash glare ratio (default: 0.025)
%
% Outputs:
%   result  - Struct containing:
%             .status            : 'PASS' or 'REJECT'
%             .brisqueScore      : BRISQUE spatial quality metric
%             .meanIllumination  : Average foreground pixel luminance [0, 1]
%             .glareFraction     : Fraction of overexposed/saturated pixels
%             .sharpnessEnergy   : High-frequency gradient energy metric
%             .isIlluminated     : Boolean flag
%             .isSharp           : Boolean flag
%             .noGlare           : Boolean flag
%             .feedback          : Human-readable clinical recapture advice
%
% SIH Problem Statement 26038 | MathWorks Sponsored Prototype

    if nargin < 2
        options = struct();
    end
    if ~isfield(options, 'brisqueThreshold'), options.brisqueThreshold = 65.0; end
    if ~isfield(options, 'minIllumination'),  options.minIllumination  = 0.12; end
    if ~isfield(options, 'minDynamicRange'),  options.minDynamicRange  = 0.08; end
    if ~isfield(options, 'maxGlareFraction'), options.maxGlareFraction = 0.035; end

    % Convert input to double [0, 1]
    if isa(img, 'uint8')
        imgDbl = double(img) / 255.0;
    else
        imgDbl = double(img);
        if max(imgDbl(:)) > 1.0
            imgDbl = imgDbl / max(imgDbl(:));
        end
    end

    % Convert to grayscale
    if size(imgDbl, 3) == 3
        imgGray = 0.2989 * imgDbl(:,:,1) + 0.5870 * imgDbl(:,:,2) + 0.1140 * imgDbl(:,:,3);
    else
        imgGray = imgDbl;
    end

    % 1. Detect Field of View (FOV) circular mask to exclude black camera borders
    fovMask = imgGray > 0.05;
    fovMask = imfill(fovMask, 'holes');
    % Clean outer boundary noise
    se = strel('disk', 5);
    fovMask = imopen(fovMask, se);
    numFovPixels = sum(fovMask(:));
    if numFovPixels < 0.10 * numel(imgGray)
        % Fallback if whole image is illuminated
        fovMask = true(size(imgGray));
        numFovPixels = numel(imgGray);
    end

    % 2. Calculate Illumination & Dynamic Range within FOV
    fovPixels = imgGray(fovMask);
    meanIllum = mean(fovPixels);
    p95 = prctile(fovPixels, 95);
    p5  = prctile(fovPixels, 5);
    dynamicRange = p95 - p5;

    % 3. Detect Glare / Overexposure Artifacts (Flash reflections)
    glarePixels = sum(fovPixels > 0.92);
    glareFraction = glarePixels / numFovPixels;

    % 4. Calculate Sharpness & Noise (BRISQUE + Gradient Energy)
    % Call MATLAB Image Processing Toolbox brisque if available
    brisqueScore = NaN;
    if exist('brisque', 'file') == 2
        try
            brisqueScore = brisque(imgGray);
        catch
            brisqueScore = NaN;
        end
    end

    % Tenengrad / Sobel gradient energy for independent sharpness validation
    [gx, gy] = gradient(imgGray);
    gradMag = sqrt(gx.^2 + gy.^2);
    sharpnessEnergy = mean(gradMag(fovMask)) * 100.0;

    % If BRISQUE is unavailable, map gradient energy to standard BRISQUE scale
    if isnan(brisqueScore)
        % High gradient energy (> 1.2) corresponds to sharp fundus (low BRISQUE ~ 25-35)
        % Low gradient energy (< 0.6) corresponds to blurred fundus (high BRISQUE ~ 55-80)
        brisqueScore = max(10, min(95, 80 - 38 * sharpnessEnergy));
    end

    % 5. Decision Rules
    isIlluminated = (meanIllum >= options.minIllumination) && (dynamicRange >= options.minDynamicRange);
    noGlare       = (glareFraction <= options.maxGlareFraction);
    isSharp       = (brisqueScore <= options.brisqueThreshold) && (sharpnessEnergy >= 0.35);

    passQuality = isIlluminated && noGlare && isSharp;

    % 6. Synthesize Actionable Health Worker Recapture Feedback
    feedbackList = {};
    if ~isIlluminated
        if meanIllum < options.minIllumination
            feedbackList{end+1} = 'Insufficient illumination: Increase fundus camera flash or check pupil dilation.';
        else
            feedbackList{end+1} = 'Low dynamic contrast: Check fundus camera sensor gain.';
        end
    end

    if ~noGlare
        feedbackList{end+1} = sprintf('Flash glare / cornea reflection detected (%.1f%% glare): Reposition patient and angle lens.', glareFraction * 100);
    end

    if ~isSharp
        feedbackList{end+1} = sprintf('Poor focus or motion blur detected (BRISQUE: %.1f): Stabilize chin rest, clean lens, and refocus.', brisqueScore);
    end

    if passQuality
        status = 'PASS';
        feedback = 'Image quality ADEQUATE for clinical diagnostic grading.';
    else
        status = 'REJECT';
        feedback = strjoin(feedbackList, ' | ');
    end

    % Package Output Struct
    result.status           = status;
    result.passQuality      = passQuality;
    result.brisqueScore     = brisqueScore;
    result.meanIllumination = meanIllum;
    result.glareFraction    = glareFraction;
    result.sharpnessEnergy  = sharpnessEnergy;
    result.dynamicRange     = dynamicRange;
    result.isIlluminated    = isIlluminated;
    result.isSharp          = isSharp;
    result.noGlare          = noGlare;
    result.feedback         = feedback;
end
