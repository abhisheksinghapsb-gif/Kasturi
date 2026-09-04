function samples = generate_synthetic_fundus(outputDir)
% GENERATE_SYNTHETIC_FUNDUS Procedurally generates realistic synthetic retinal fundus images
% for validating the rural diabetic retinopathy AI screening pipeline.
%
% Syntax:
%   samples = generate_synthetic_fundus()
%   samples = generate_synthetic_fundus(outputDir)
%
% Outputs:
%   samples - Struct containing filepaths to generated test images:
%             .blur   : Severely blurred / low quality (triggers IQA REJECT)
%             .grade0 : Normal healthy retina (Grade 0, Non-referable)
%             .grade2 : Moderate NPDR with microaneurysms & hemorrhages (Grade 2, Referable)
%             .grade4 : Severe PDR with hard exudates, neovascularization (Grade 4, Urgent)
%
% SIH Problem Statement 26038 | MathWorks Sponsored Prototype

    if nargin < 1 || isempty(outputDir)
        baseDir = fileparts(mfilename('fullpath'));
        outputDir = fullfile(baseDir, 'test_samples');
    end

    if ~exist(outputDir, 'dir')
        mkdir(outputDir);
    end

    fprintf('=== Generating Synthetic Fundus Test Dataset ===\n');
    fprintf('Target directory: %s\n', outputDir);

    % Image dimensions (Standard fundus camera resolution for edge triage)
    imgSize = [512, 512];
    
    % 1. Generate Healthy Base Retina (Grade 0)
    imgGrade0 = create_base_retina(imgSize, 0);
    pathGrade0 = fullfile(outputDir, 'sample_grade0_healthy.png');
    imwrite(imgGrade0, pathGrade0);
    fprintf('  [OK] Generated Grade 0 (Healthy): %s\n', pathGrade0);

    % 2. Generate Moderate NPDR (Grade 2: Microaneurysms + Dot Hemorrhages)
    imgGrade2 = create_base_retina(imgSize, 2);
    pathGrade2 = fullfile(outputDir, 'sample_grade2_moderate.png');
    imwrite(imgGrade2, pathGrade2);
    fprintf('  [OK] Generated Grade 2 (Moderate NPDR): %s\n', pathGrade2);

    % 3. Generate Severe / Proliferative DR (Grade 4: Hard Exudates + Neovascularization)
    imgGrade4 = create_base_retina(imgSize, 4);
    pathGrade4 = fullfile(outputDir, 'sample_grade4_severe.png');
    imwrite(imgGrade4, pathGrade4);
    fprintf('  [OK] Generated Grade 4 (Severe PDR): %s\n', pathGrade4);

    % 4. Generate Blurry / Ungradeable Image (Defocus blur + Glare artifact -> IQA REJECT)
    imgBlur = create_blurry_fundus(imgGrade0);
    pathBlur = fullfile(outputDir, 'sample_blur_reject.png');
    imwrite(imgBlur, pathBlur);
    fprintf('  [OK] Generated Blurry/Reject Sample: %s\n', pathBlur);

    % Return struct of paths
    samples.grade0 = pathGrade0;
    samples.grade2 = pathGrade2;
    samples.grade4 = pathGrade4;
    samples.blur   = pathBlur;
    
    fprintf('=== Synthetic Dataset Generation Complete (4 Samples Ready) ===\n\n');
end

% -------------------------------------------------------------------------
% Helper: Create Base Retina with Optic Disc, Macula, Vessels & Lesions
% -------------------------------------------------------------------------
function img = create_base_retina(imgSize, grade)
    H = imgSize(1);
    W = imgSize(2);
    [X, Y] = meshgrid(1:W, 1:H);

    % Circular Field of View (FOV) mask
    centerX = W / 2;
    centerY = H / 2;
    radiusFOV = 0.46 * min(H, W);
    distFromCenter = sqrt((X - centerX).^2 + (Y - centerY).^2);
    fovMask = distFromCenter <= radiusFOV;
    
    % Smooth edge fall-off (vignetting at FOV border)
    edgeFalloff = min(1, max(0, (radiusFOV - distFromCenter) / 8));

    % Base background color gradient (Choroidal vascular glow: reddish-orange)
    R = 0.82 - 0.12 * (distFromCenter / radiusFOV) + 0.02 * sin(X / 20) .* cos(Y / 20);
    G = 0.42 - 0.10 * (distFromCenter / radiusFOV) + 0.015 * cos(X / 25);
    B = 0.10 - 0.04 * (distFromCenter / radiusFOV);

    % Optic Disc (Nasal side, bright yellowish-orange circular/oval structure)
    odX = centerX - 0.24 * W;
    odY = centerY - 0.02 * H;
    odRadius = 0.075 * min(H, W);
    distOD = sqrt((X - odX).^2 + (Y - odY).^2);
    odWeight = exp(- (distOD / (0.85 * odRadius)).^2) .* (distOD <= odRadius * 1.1);

    % Optic Cup (Paler center of optic disc)
    cupRadius = 0.4 * odRadius;
    distCup = sqrt((X - odX).^2 + (Y - odY).^2);
    cupWeight = exp(- (distCup / (0.7 * cupRadius)).^2) .* (distCup <= cupRadius);

    % Blend Optic Disc into retina
    R = R .* (1 - 0.3 * odWeight) + 0.98 * odWeight + 0.15 * cupWeight;
    G = G .* (1 - 0.6 * odWeight) + 0.85 * odWeight + 0.20 * cupWeight;
    B = B .* (1 - 0.7 * odWeight) + 0.45 * odWeight + 0.15 * cupWeight;

    % Macula & Fovea Centralis (Temporal side, avascular dark pigmented zone)
    maculaX = centerX + 0.16 * W;
    maculaY = centerY + 0.01 * H;
    distMacula = sqrt((X - maculaX).^2 + (Y - maculaY).^2);
    maculaWeight = exp(- (distMacula / (0.12 * min(H, W))).^2);
    foveaWeight  = exp(- (distMacula / (0.03 * min(H, W))).^2);

    % Darken macular region
    R = R .* (1 - 0.22 * maculaWeight - 0.15 * foveaWeight);
    G = G .* (1 - 0.30 * maculaWeight - 0.20 * foveaWeight);
    B = B .* (1 - 0.20 * maculaWeight);

    % Retinal Blood Vessel Tree (Branching arcs from Optic Disc)
    vesselTree = zeros(H, W);
    
    % Primary Superior & Inferior Arcade vessels
    arcades = [
        % [startAngle, endAngle, curvature, radiusX, radiusY, thickness]
        -0.85*pi, -0.15*pi,  0.4, 0.35*W, 0.38*H, 3.2;  % Superior temporal arcade
         0.15*pi,  0.85*pi, -0.4, 0.35*W, 0.38*H, 3.0;  % Inferior temporal arcade
        -0.95*pi, -0.55*pi, -0.3, 0.18*W, 0.25*H, 2.4;  % Superior nasal branch
         0.55*pi,  0.95*pi,  0.3, 0.18*W, 0.25*H, 2.2;  % Inferior nasal branch
    ];

    for a = 1:size(arcades, 1)
        ang = linspace(arcades(a, 1), arcades(a, 2), 200);
        curv = arcades(a, 3);
        thick = arcades(a, 6);
        ithick = ceil(thick);
        rx = arcades(a, 4);
        ry = arcades(a, 5);
        vx = odX + rx * cos(ang) + curv * rx * sin(ang).^2;
        vy = odY + ry * sin(ang);

        for pt = 1:length(vx)
            px = round(vx(pt));
            py = round(vy(pt));
            if px > ithick && px <= W - ithick && py > ithick && py <= H - ithick
                for dx = -ithick:ithick
                    for dy = -ithick:ithick
                        if dx^2 + dy^2 <= thick^2
                            vesselTree(py + dy, px + dx) = max(vesselTree(py + dy, px + dx), 1 - sqrt(dx^2 + dy^2)/(thick + 0.5));
                        end
                    end
                end
            end
        end
    end

    % Vessel absorption (Blood absorbs green channel strongly, moderate red)
    vesselTree = min(1, vesselTree);
    R = R .* (1 - 0.25 * vesselTree);
    G = G .* (1 - 0.65 * vesselTree);  % Green absorbs strongly (high vessel contrast)
    B = B .* (1 - 0.40 * vesselTree);

    % Add pathological lesions based on DR grade
    rng(42); % Deterministic seed for reproducible testing
    switch grade
        case 0
            % Grade 0: Normal retina, zero lesions
            
        case 2
            % Grade 2: Moderate NPDR
            % Features: Microaneurysms (tiny dark red dots) + few dot/blot hemorrhages
            numMA = 25;
            for i = 1:numMA
                maX = round(maculaX + (rand() - 0.5) * 0.45 * W);
                maY = round(centerY + (rand() - 0.5) * 0.45 * H);
                maRad = randi([2, 4]);
                if maX > 15 && maX < W-15 && maY > 15 && maY < H-15 && fovMask(maY, maX)
                    [mx, my] = meshgrid(-maRad:maRad, -maRad:maRad);
                    d = sqrt(mx.^2 + my.^2);
                    mMask = d <= maRad;
                    subR = R(maY-maRad:maY+maRad, maX-maRad:maX+maRad);
                    subG = G(maY-maRad:maY+maRad, maX-maRad:maX+maRad);
                    subB = B(maY-maRad:maY+maRad, maX-maRad:maX+maRad);
                    
                    % Dark red/burgundy microaneurysm
                    subR(mMask) = subR(mMask) * 0.50;
                    subG(mMask) = subG(mMask) * 0.15;
                    subB(mMask) = subB(mMask) * 0.10;
                    
                    R(maY-maRad:maY+maRad, maX-maRad:maX+maRad) = subR;
                    G(maY-maRad:maY+maRad, maX-maRad:maX+maRad) = subG;
                    B(maY-maRad:maY+maRad, maX-maRad:maX+maRad) = subB;
                end
            end
            
        case 4
            % Grade 4: Severe Proliferative DR (PDR)
            % Features: Clusters of Hard Exudates (bright yellow lipid deposits),
            % extensive hemorrhages, and abnormal neovascular loops
            numExudates = 60;
            for i = 1:numExudates
                exAng = rand() * 2 * pi;
                exDist = (0.08 + 0.14 * rand()) * min(H, W);
                exX = round(maculaX + exDist * cos(exAng));
                exY = round(maculaY + exDist * sin(exAng));
                exRad = randi([3, 7]);
                
                if exX > 10 && exX < W-10 && exY > 10 && exY < H-10 && fovMask(exY, exX) && distOD(exY, exX) > odRadius * 1.3
                    [mx, my] = meshgrid(-exRad:exRad, -exRad:exRad);
                    d = sqrt(mx.^2 + my.^2);
                    eMask = d <= exRad;
                    
                    subR = R(exY-exRad:exY+exRad, exX-exRad:exX+exRad);
                    subG = G(exY-exRad:exY+exRad, exX-exRad:exX+exRad);
                    subB = B(exY-exRad:exY+exRad, exX-exRad:exX+exRad);
                    
                    % Bright yellow-white lipid deposit
                    subR(eMask) = min(1.0, subR(eMask) * 0.3 + 0.95);
                    subG(eMask) = min(1.0, subG(eMask) * 0.3 + 0.92);
                    subB(eMask) = min(1.0, subB(eMask) * 0.3 + 0.50);
                    
                    R(exY-exRad:exY+exRad, exX-exRad:exX+exRad) = subR;
                    G(exY-exRad:exY+exRad, exX-exRad:exX+exRad) = subG;
                    B(exY-exRad:exY+exRad, exX-exRad:exX+exRad) = subB;
                end
            end

            % Extensive Blot Hemorrhages
            numHemorrhages = 20;
            for i = 1:numHemorrhages
                hX = round(centerX + (rand() - 0.5) * 0.6 * W);
                hY = round(centerY + (rand() - 0.5) * 0.6 * H);
                hRad = randi([6, 12]);
                if hX > 15 && hX < W-15 && hY > 15 && hY < H-15 && fovMask(hY, hX)
                    [mx, my] = meshgrid(-hRad:hRad, -hRad:hRad);
                    d = sqrt(mx.^2 + (1.3*my).^2);
                    hMask = d <= hRad;
                    
                    subR = R(hY-hRad:hY+hRad, hX-hRad:hX+hRad);
                    subG = G(hY-hRad:hY+hRad, hX-hRad:hX+hRad);
                    subB = B(hY-hRad:hY+hRad, hX-hRad:hX+hRad);
                    
                    subR(hMask) = subR(hMask) * 0.35;
                    subG(hMask) = subG(hMask) * 0.10;
                    subB(hMask) = subB(hMask) * 0.05;
                    
                    R(hY-hRad:hY+hRad, hX-hRad:hX+hRad) = subR;
                    G(hY-hRad:hY+hRad, hX-hRad:hX+hRad) = subG;
                    B(hY-hRad:hY+hRad, hX-hRad:hX+hRad) = subB;
                end
            end
    end

    % Apply FOV boundary mask and soft edge falloff
    R = R .* edgeFalloff .* fovMask;
    G = G .* edgeFalloff .* fovMask;
    B = B .* edgeFalloff .* fovMask;

    % Add subtle sensor noise
    noise = 0.015 * randn(H, W) .* fovMask;
    R = min(1, max(0, R + noise));
    G = min(1, max(0, G + noise));
    B = min(1, max(0, B + noise));

    img = cat(3, R, G, B);
end

% -------------------------------------------------------------------------
% Helper: Create Defocused, Blurry, Ungradeable Fundus Image
% -------------------------------------------------------------------------
function imgBlur = create_blurry_fundus(imgClean)
    % 1. Severe optical defocus blur (Gaussian convolution with large sigma)
    hBlur = fspecial_gaussian([25, 25], 7.0);
    imgBlur = zeros(size(imgClean));
    for c = 1:3
        imgBlur(:,:,c) = conv2(imgClean(:,:,c), hBlur, 'same');
    end

    % 2. Wash out contrast (fogging/cataract or dirty lens)
    imgBlur = imgBlur * 0.45 + 0.15;

    % 3. Overexposure glare artifact (Flash corneal reflection)
    [H, W, ~] = size(imgClean);
    [X, Y] = meshgrid(1:W, 1:H);
    glareX = 0.62 * W;
    glareY = 0.32 * H;
    glareDist = sqrt((X - glareX).^2 + (Y - glareY).^2);
    glare = 0.98 * (glareDist <= 0.12 * W) + 0.95 * exp(- (glareDist / (0.15 * W)).^2);

    for c = 1:3
        imgBlur(:,:,c) = min(1.0, imgBlur(:,:,c) + glare);
    end

    % 4. Secondary smooth defocus (eliminating retinal sharp edges)
    hBlur2 = fspecial_gaussian([31, 31], 8.0);
    for c = 1:3
        imgBlur(:,:,c) = conv2(imgBlur(:,:,c), hBlur2, 'same');
    end
end

% -------------------------------------------------------------------------
% Local 2D Gaussian Kernel
% -------------------------------------------------------------------------
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
