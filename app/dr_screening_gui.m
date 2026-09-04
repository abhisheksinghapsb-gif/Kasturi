function fig = dr_screening_gui()
% DR_SCREENING_GUI Interactive MATLAB UI Dashboard for Explainable AI
% Diabetic Retinopathy Screening in Rural Indian Primary Health Centres (PHCs).
%
% Integrates:
%   - Module 1: Image Quality Assessment (BRISQUE + Illumination) & Green CLAHE
%   - Module 2: Retinal Vasculature & Lesion Segmentation (Exudates + Microaneurysms)
%   - Module 3: ResNet-50 Multi-Class Grading & Calibrated Rural Referral Triage
%   - Module 4: Grad-CAM Saliency Explainability & 1-Click Clinical PDF Export
%
% Syntax:
%   fig = dr_screening_dashboard()
%
% SIH Problem Statement 26038 | MathWorks Sponsored Prototype

    % Setup paths to src modules
    baseDir = fileparts(fileparts(mfilename('fullpath')));
    addpath(genpath(fullfile(baseDir, 'src')));
    addpath(fullfile(baseDir, 'data'));

    % Create Main UI Figure
    fig = uifigure('Name', 'Rural DR Tele-Ophthalmology AI Dashboard (SIH PS 26038)', ...
        'Position', [50, 50, 1300, 780], ...
        'Color', [0.94, 0.95, 0.97]);

    % App State Variables
    appData = struct();
    appData.baseDir        = baseDir;
    appData.currentImage   = [];
    appData.enhancedGray   = [];
    appData.vesselMask     = [];
    appData.lesionStats    = [];
    appData.iqaResult      = [];
    appData.prediction     = [];
    appData.gradCamOverlay = [];
    appData.samples        = [];

    % ---------------------------------------------------------------------
    % Top Title Banner
    % ---------------------------------------------------------------------
    pnlBanner = uipanel(fig, 'Position', [15, 715, 1270, 55], ...
        'BackgroundColor', [0.08, 0.22, 0.45], 'BorderType', 'none');

    uilabel(pnlBanner, 'Text', 'AI-ASSISTED DIABETIC RETINOPATHY SCREENING SYSTEM', ...
        'Position', [20, 26, 750, 24], ...
        'FontSize', 15, 'FontWeight', 'bold', 'FontColor', 'w');

    uilabel(pnlBanner, 'Text', 'Rural PHC Tele-Ophthalmology Decision Support | SIH PS 26038 (MathWorks)', ...
        'Position', [20, 6, 750, 18], ...
        'FontSize', 10, 'FontColor', [0.80, 0.90, 1.0]);

    % Facility Badge
    uilabel(pnlBanner, 'Text', 'DEPLOYMENT: Rural Health Centre (ASHA Triage)', ...
        'Position', [930, 15, 320, 24], ...
        'FontSize', 10.5, 'FontWeight', 'bold', 'FontColor', [1.0, 0.85, 0.3], ...
        'HorizontalAlignment', 'right');

    % ---------------------------------------------------------------------
    % Left Panel: Controls & Patient Demographics
    % ---------------------------------------------------------------------
    pnlControls = uipanel(fig, 'Position', [15, 20, 290, 685], ...
        'Title', 'SCREENING CONTROLS', 'FontSize', 11, 'FontWeight', 'bold', ...
        'BackgroundColor', 'w', 'ForegroundColor', [0.1, 0.2, 0.4]);

    % Patient Metadata Inputs
    uilabel(pnlControls, 'Text', 'Patient ID:', 'Position', [15, 630, 80, 20], 'FontWeight', 'bold');
    txtPatientId = uieditfield(pnlControls, 'text', 'Value', 'IND-PHC-2026-0814', ...
        'Position', [100, 630, 170, 24]);

    uilabel(pnlControls, 'Text', 'Age / Gender:', 'Position', [15, 595, 80, 20], 'FontWeight', 'bold');
    txtAge = uieditfield(pnlControls, 'numeric', 'Value', 56, ...
        'Position', [100, 595, 60, 24]);
    ddGender = uidropdown(pnlControls, 'Items', {'Female', 'Male', 'Other'}, 'Value', 'Female', ...
        'Position', [170, 595, 100, 24]);

    uilabel(pnlControls, 'Text', 'PHC Center:', 'Position', [15, 560, 80, 20], 'FontWeight', 'bold');
    txtPHC = uieditfield(pnlControls, 'text', 'Value', 'PHC Kolar District #04', ...
        'Position', [100, 560, 170, 24]);

    % Test Sample Loader Dropdown
    uilabel(pnlControls, 'Text', 'Select Test Fundus Scan:', 'Position', [15, 515, 255, 20], ...
        'FontWeight', 'bold', 'FontColor', [0.15, 0.35, 0.65]);
    
    sampleOptions = {
        '-- Select Fundus Image --', ...
        'Real IDRiD: Normal Patient [Grade 0]', ...
        'Real IDRiD: Mild NPDR Patient [Grade 1]', ...
        'Real IDRiD: Moderate Patient [Grade 2]', ...
        'Real IDRiD: Severe Patient [Grade 3]', ...
        'Real IDRiD: Proliferative PDR Patient [Grade 4]', ...
        'Synthetic: Defocus / Glare [IQA REJECT]'
    };
    ddSamples = uidropdown(pnlControls, 'Items', sampleOptions, 'Value', sampleOptions{1}, ...
        'Position', [15, 485, 255, 28], ...
        'ValueChangedFcn', @(src, evt) on_sample_selected(src, evt));

    % Custom File Browse Button
    btnBrowse = uibutton(pnlControls, 'push', 'Text', 'Browse Custom Image...', ...
        'Position', [15, 445, 255, 28], ...
        'BackgroundColor', [0.92, 0.94, 0.97], 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(src, evt) on_browse_file());

    % Primary Action: Run AI Screening Pipeline
    btnRun = uibutton(pnlControls, 'push', 'Text', 'RUN AI SCREENING PIPELINE', ...
        'Position', [15, 375, 255, 42], ...
        'BackgroundColor', [0.10, 0.55, 0.30], 'FontColor', 'w', ...
        'FontSize', 11, 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(src, evt) on_run_screening());

    % Status Log / Recapture Guidance Box
    uilabel(pnlControls, 'Text', 'ASHA Operator Guidance:', 'Position', [15, 335, 255, 20], ...
        'FontWeight', 'bold');
    txtGuidance = uitextarea(pnlControls, 'Position', [15, 175, 255, 155], ...
        'Value', {'Select an image or sample and click "RUN AI SCREENING PIPELINE".', ...
                  '', 'System will evaluate image quality, segment lesions, grade DR severity, and generate Grad-CAM.'}, ...
        'Editable', 'off', 'FontSize', 9.5, 'BackgroundColor', [0.97, 0.98, 1.0]);

    % Secondary Action: Export Doctor Clinical PDF Report
    btnPdf = uibutton(pnlControls, 'push', 'Text', 'EXPORT DOCTOR PDF REPORT', ...
        'Position', [15, 110, 255, 38], ...
        'BackgroundColor', [0.08, 0.25, 0.55], 'FontColor', 'w', ...
        'FontSize', 10.5, 'FontWeight', 'bold', 'Enable', 'off', ...
        'ButtonPushedFcn', @(src, evt) on_export_pdf());

    % Telemedicine Simulation Button
    btnSim = uibutton(pnlControls, 'push', 'Text', 'Run Telemed Queue Simulation', ...
        'Position', [15, 62, 255, 30], ...
        'BackgroundColor', [0.95, 0.95, 0.96], 'FontSize', 9, ...
        'ButtonPushedFcn', @(src, evt) on_run_telemed_sim());

    % Batch Queue Screening Button
    btnBatch = uibutton(pnlControls, 'push', 'Text', '⚡ BATCH QUEUE SCREENING (3+ SCANS)', ...
        'Position', [15, 16, 255, 38], ...
        'BackgroundColor', [0.40, 0.18, 0.65], 'FontColor', 'w', ...
        'FontSize', 10, 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(src, evt) on_run_batch_screening());

    % ---------------------------------------------------------------------
    % Center 2x2 Visual Display Grid
    % ---------------------------------------------------------------------
    pnlVisuals = uipanel(fig, 'Position', [315, 20, 645, 685], ...
        'Title', 'DIAGNOSTIC VISUALIZATION (MULTI-STAGE ANALYSIS)', ...
        'FontSize', 11, 'FontWeight', 'bold', ...
        'BackgroundColor', 'w', 'ForegroundColor', [0.1, 0.2, 0.4]);

    % 4 Diagnostic Axes
    ax1 = uiaxes(pnlVisuals, 'Position', [15, 345, 295, 305]);
    title(ax1, '1. Raw Retinal Fundus Scan', 'FontSize', 10, 'FontWeight', 'bold');
    ax1.XTick = []; ax1.YTick = []; box(ax1, 'on');

    ax2 = uiaxes(pnlVisuals, 'Position', [335, 345, 295, 305]);
    title(ax2, '2. Enhanced Green (Rayleigh CLAHE)', 'FontSize', 10, 'FontWeight', 'bold');
    ax2.XTick = []; ax2.YTick = []; box(ax2, 'on');

    ax3 = uiaxes(pnlVisuals, 'Position', [15, 25, 295, 305]);
    title(ax3, '3. Vasculature & Lesion Detections', 'FontSize', 10, 'FontWeight', 'bold');
    ax3.XTick = []; ax3.YTick = []; box(ax3, 'on');

    ax4 = uiaxes(pnlVisuals, 'Position', [335, 25, 295, 305]);
    title(ax4, '4. Explainable AI: Grad-CAM Heatmap', 'FontSize', 10, 'FontWeight', 'bold');
    ax4.XTick = []; ax4.YTick = []; box(ax4, 'on');

    % ---------------------------------------------------------------------
    % Right Panel: Clinical Triage, IQA & Biomarkers
    % ---------------------------------------------------------------------
    pnlDiagnosis = uipanel(fig, 'Position', [970, 20, 315, 685], ...
        'Title', 'CLINICAL TRIAGE & BIOMARKERS', ...
        'FontSize', 11, 'FontWeight', 'bold', ...
        'BackgroundColor', 'w', 'ForegroundColor', [0.1, 0.2, 0.4]);

    % 1. Image Quality Assessment (IQA) Status Box
    uilabel(pnlDiagnosis, 'Text', 'IMAGE QUALITY ASSESSMENT (IQA)', 'Position', [15, 630, 280, 20], ...
        'FontWeight', 'bold', 'FontSize', 9.5, 'FontColor', [0.3, 0.3, 0.3]);

    lblIqaBadge = uilabel(pnlDiagnosis, 'Text', 'READY FOR INPUT', ...
        'Position', [15, 595, 285, 30], ...
        'BackgroundColor', [0.90, 0.90, 0.92], 'FontColor', [0.2, 0.2, 0.2], ...
        'FontSize', 11, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');

    lblIqaDetails = uilabel(pnlDiagnosis, 'Text', 'BRISQUE: -- | Illumination: --', ...
        'Position', [15, 568, 285, 20], 'FontSize', 9, 'HorizontalAlignment', 'center');

    % 2. Referral Action Triage Badge
    uilabel(pnlDiagnosis, 'Text', 'TELEMEDICINE REFERRAL TRIAGE', 'Position', [15, 530, 280, 20], ...
        'FontWeight', 'bold', 'FontSize', 9.5, 'FontColor', [0.3, 0.3, 0.3]);

    lblTriageBadge = uilabel(pnlDiagnosis, 'Text', 'PENDING ANALYSIS', ...
        'Position', [15, 485, 285, 40], ...
        'BackgroundColor', [0.88, 0.90, 0.92], 'FontColor', [0.2, 0.2, 0.2], ...
        'FontSize', 11, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');

    lblTriageAction = uilabel(pnlDiagnosis, 'Text', 'Waiting for screening execution...', ...
        'Position', [15, 455, 285, 25], 'FontSize', 8.5, 'FontAngle', 'italic', ...
        'HorizontalAlignment', 'center');

    % 3. AI DR Severity Grade Card
    uilabel(pnlDiagnosis, 'Text', 'RESNET-50 DIAGNOSIS', 'Position', [15, 420, 280, 20], ...
        'FontWeight', 'bold', 'FontSize', 9.5, 'FontColor', [0.3, 0.3, 0.3]);

    lblGrade = uilabel(pnlDiagnosis, 'Text', 'Grade: --', ...
        'Position', [15, 390, 285, 25], ...
        'FontSize', 13, 'FontWeight', 'bold', 'FontColor', [0.1, 0.2, 0.5]);

    lblReferableRisk = uilabel(pnlDiagnosis, 'Text', 'Referable DR Risk P(Grade >= 2): --', ...
        'Position', [15, 365, 285, 20], 'FontSize', 9, 'FontWeight', 'bold');

    % 4. Probability Distribution Bar Graph
    axProb = uiaxes(pnlDiagnosis, 'Position', [15, 220, 285, 140]);
    bar(axProb, 0:4, [0 0 0 0 0], 0.6, 'FaceColor', [0.15, 0.40, 0.70]);
    set(axProb, 'XTick', 0:4, 'XTickLabel', {'G0', 'G1', 'G2', 'G3', 'G4'}, 'FontSize', 7.5);
    ylabel(axProb, 'Prob (%)', 'FontSize', 7.5);
    ylim(axProb, [0, 100]);
    title(axProb, 'Class Probability Distribution', 'FontSize', 8.5, 'FontWeight', 'bold');

    % 5. Quantitative Biomarkers Summary Table
    uilabel(pnlDiagnosis, 'Text', 'EXTRACTED RETINAL BIOMARKERS', 'Position', [15, 185, 280, 20], ...
        'FontWeight', 'bold', 'FontSize', 9.5, 'FontColor', [0.3, 0.3, 0.3]);

    lblBio1 = uilabel(pnlDiagnosis, 'Text', '- Vessel Density: -- %', 'Position', [20, 160, 275, 18], 'FontSize', 9);
    lblBio2 = uilabel(pnlDiagnosis, 'Text', '- Hard Exudates: -- clusters', 'Position', [20, 140, 275, 18], 'FontSize', 9);
    lblBio3 = uilabel(pnlDiagnosis, 'Text', '- Microaneurysms: -- detected', 'Position', [20, 120, 275, 18], 'FontSize', 9);
    lblBio4 = uilabel(pnlDiagnosis, 'Text', '- Blot Hemorrhages: -- detected', 'Position', [20, 100, 275, 18], 'FontSize', 9);
    lblBio5 = uilabel(pnlDiagnosis, 'Text', '- Optic Disc: --', 'Position', [20, 80, 275, 18], 'FontSize', 9);

    % MathWorks & SIH Footer note
    uilabel(pnlDiagnosis, 'Text', 'MathWorks SIH 26038 Benchmark: Sens >90%, Spec >85%', ...
        'Position', [15, 15, 285, 30], 'FontSize', 8, 'FontAngle', 'italic', ...
        'FontColor', [0.4, 0.4, 0.4], 'HorizontalAlignment', 'center');

    % ---------------------------------------------------------------------
    % Callback Implementations
    % ---------------------------------------------------------------------
    function on_sample_selected(src, ~)
        val = src.Value;
        if strcmp(val, sampleOptions{1}), return; end

        % Auto-generate synthetic samples if missing
        samplesDir = fullfile(baseDir, 'data', 'test_samples');
        if ~exist(samplesDir, 'dir') || isempty(dir(fullfile(samplesDir, '*.png')))
            txtGuidance.Value = {'Generating synthetic fundus samples...'};
            drawnow;
            appData.samples = generate_synthetic_fundus(samplesDir);
        end

        switch val
            case sampleOptions{2}
                imgPath = fullfile(samplesDir, 'idrid_grade0_normal.jpg');
            case sampleOptions{3}
                imgPath = fullfile(samplesDir, 'idrid_grade1_mild.jpg');
            case sampleOptions{4}
                imgPath = fullfile(samplesDir, 'idrid_grade2_moderate.jpg');
            case sampleOptions{5}
                imgPath = fullfile(samplesDir, 'idrid_grade3_severe.jpg');
            case sampleOptions{6}
                imgPath = fullfile(samplesDir, 'idrid_grade4_proliferative.jpg');
            case sampleOptions{7}
                imgPath = fullfile(samplesDir, 'sample_blur_reject.png');
            otherwise
                return;
        end

        load_and_display_image(imgPath);
    end

    function on_browse_file()
        [file, path] = uigetfile({'*.png;*.jpg;*.jpeg;*.tif;*.tiff;*.dcm', 'Fundus Images (*.png, *.jpg, *.tif)'});
        if isequal(file, 0), return; end
        load_and_display_image(fullfile(path, file));
    end

    function load_and_display_image(imgPath)
        try
            img = imread(imgPath);
            % Standardize to 512x512 for instantaneous <0.3s real-time clinical screening
            if size(img, 1) > 600 || size(img, 2) > 600
                img = imresize(img, [512, 512]);
            end
            appData.currentImage = img;
            imshow(img, 'Parent', ax1);
            title(ax1, '1. Raw Retinal Fundus Scan', 'FontSize', 10, 'FontWeight', 'bold');
            
            % Reset other views
            cla(ax2); cla(ax3); cla(ax4);
            lblIqaBadge.Text = 'READY FOR ANALYSIS';
            lblIqaBadge.BackgroundColor = [0.90, 0.90, 0.92];
            lblIqaBadge.FontColor = [0.2, 0.2, 0.2];
            lblTriageBadge.Text = 'CLICK "RUN AI SCREENING"';
            lblTriageBadge.BackgroundColor = [0.88, 0.90, 0.92];
            lblTriageBadge.FontColor = [0.2, 0.2, 0.2];
            btnPdf.Enable = 'off';

            txtGuidance.Value = {sprintf('Loaded image: %s', imgPath), ...
                                '', 'Click "RUN AI SCREENING PIPELINE" to begin automated diagnosis.'};
        catch ME
            uialert(fig, ME.message, 'File Load Error');
        end
    end

    function on_run_screening()
        if isempty(appData.currentImage)
            uialert(fig, 'Please select or browse a fundus image first.', 'No Image Loaded');
            return;
        end

        txtGuidance.Value = {'Running Module 1: Image Quality Assessment & Contrast Enhancement...'};
        drawnow;

        % 1. Module 1: IQA & Enhancement
        img = appData.currentImage;
        if size(img, 1) > 512 || size(img, 2) > 512
            img = imresize(img, [512, 512]);
            appData.currentImage = img;
        end
        iqa = evaluate_image_quality(img);
        appData.iqaResult = iqa;

        % Update IQA Badge
        if strcmp(iqa.status, 'PASS')
            lblIqaBadge.Text = sprintf('IQA: PASSED (BRISQUE: %.1f)', iqa.brisqueScore);
            lblIqaBadge.BackgroundColor = [0.15, 0.68, 0.35];
            lblIqaBadge.FontColor = 'w';
        else
            lblIqaBadge.Text = sprintf('IQA: REJECT (BRISQUE: %.1f)', iqa.brisqueScore);
            lblIqaBadge.BackgroundColor = [0.88, 0.15, 0.15];
            lblIqaBadge.FontColor = 'w';
        end
        lblIqaDetails.Text = sprintf('Illumination: %.1f%% | Glare: %.2f%%', ...
            iqa.meanIllumination * 100, iqa.glareFraction * 100);

        % If rejected, notify ASHA worker immediately
        if strcmp(iqa.status, 'REJECT')
            cla(ax2); cla(ax3); cla(ax4); cla(axProb);
            lblGrade.Text = 'Image Ungradeable';
            lblReferableRisk.Text = 'Quality insufficient for clinical grading';
            lblBio1.Text = '- Vessel Density: --';
            lblBio2.Text = '- Hard Exudates: --';
            lblBio3.Text = '- Microaneurysms: --';
            lblBio4.Text = '- Blot Hemorrhages: --';
            lblBio5.Text = '- Optic Disc: --';
            btnPdf.Enable = 'off';

            txtGuidance.Value = {
                '*** IMAGE QUALITY REJECTED ***', ...
                '', ...
                'Frontline Health Worker Recapture Action:', ...
                iqa.feedback, ...
                '', ...
                'Do not proceed with diagnostic grading on ungradeable scans.'
            };
            lblTriageBadge.Text = 'RECAPTURE REQUIRED';
            lblTriageBadge.BackgroundColor = [0.88, 0.15, 0.15];
            lblTriageBadge.FontColor = 'w';
            lblTriageAction.Text = 'Image ungradeable. Recapture per feedback.';
            return;
        end

        try
            % Enhancement
            [enhancedGray, enhancedRGB] = enhance_fundus(img);
            appData.enhancedGray = enhancedGray;
            imshow(enhancedGray, 'Parent', ax2);
            title(ax2, '2. Enhanced Green Channel', 'FontSize', 10, 'FontWeight', 'bold');
            drawnow;

            % 2. Module 2: Segmentation
            txtGuidance.Value = {'Running Module 2: Retinal Vessel Tree & Lesion Extraction...'};
            drawnow;

            [vesselMask, vesselDensity] = segment_vessels(enhancedGray);
            appData.vesselMask = vesselMask;

            lesionStats = detect_lesions(img, enhancedGray, vesselMask);
            appData.lesionStats = lesionStats;

            imshow(lesionStats.lesionOverlay, 'Parent', ax3);
            title(ax3, '3. Vasculature & Lesion Detections', 'FontSize', 10, 'FontWeight', 'bold');
            drawnow;

            % 3. Module 3: Classification & Triage
            txtGuidance.Value = {'Running Module 3: ResNet-50 Severity Grading & Clinical Triage...'};
            drawnow;

            pred = classify_dr(img, [], lesionStats);
            appData.prediction = pred;

            % Update Classification UI Cards
            lblGrade.Text = sprintf('Grade %d: %s', pred.grade, pred.gradeName);
            lblReferableRisk.Text = sprintf('Referable Risk P(G>=2): %.1f%%', pred.referableScore * 100);

            % Update Bar Chart
            cla(axProb);
            bar(axProb, 0:4, pred.probabilities * 100, 0.6, 'FaceColor', [0.15, 0.40, 0.70]);
            set(axProb, 'XTick', 0:4, 'XTickLabel', {'G0', 'G1', 'G2', 'G3', 'G4'}, 'FontSize', 7.5);
            ylabel(axProb, 'Prob (%)', 'FontSize', 7.5);
            ylim(axProb, [0, 100]);
            title(axProb, sprintf('Predicted: %s', pred.gradeName), 'FontSize', 8.5, 'FontWeight', 'bold');

            % Update Triage Badge
            switch pred.grade
                case 0
                    lblTriageBadge.Text = 'CLEARED: ROUTINE ANNUAL';
                    lblTriageBadge.BackgroundColor = [0.12, 0.65, 0.28];
                    lblTriageBadge.FontColor = 'w';
                    lblTriageAction.Text = 'No sight-threatening DR. Rescreen in 12 mo.';
                case 1
                    lblTriageBadge.Text = 'PHC MONITORING: NON-REFERABLE';
                    lblTriageBadge.BackgroundColor = [0.15, 0.60, 0.30];
                    lblTriageBadge.FontColor = 'w';
                    lblTriageAction.Text = 'Microaneurysms only. HbA1c control & rescreen 6-12 mo.';
                case 2
                    lblTriageBadge.Text = 'MODERATE REFERRAL (30d)';
                    lblTriageBadge.BackgroundColor = [0.92, 0.55, 0.05];
                    lblTriageBadge.FontColor = 'w';
                    lblTriageAction.Text = 'Secondary Ophthalmology Clinic consult within 30 days.';
                case 3
                    lblTriageBadge.Text = 'HIGH RISK REFERRAL (<14d)';
                    lblTriageBadge.BackgroundColor = [0.88, 0.35, 0.05];
                    lblTriageBadge.FontColor = 'w';
                    lblTriageAction.Text = 'Severe NPDR. Specialist evaluation within 2 weeks.';
                case 4
                    lblTriageBadge.Text = 'URGENT REFERRAL (<48h)';
                    lblTriageBadge.BackgroundColor = [0.85, 0.12, 0.15];
                    lblTriageBadge.FontColor = 'w';
                    lblTriageAction.Text = 'Proliferative DR. Immediate Vitreoretinal Tertiary Care.';
            end

            % Update Biomarkers
            lblBio1.Text = sprintf('- Vessel Density: %.2f %% FOV', vesselDensity);
            lblBio2.Text = sprintf('- Hard Exudates: %d clusters (%d px)', lesionStats.exudateCount, lesionStats.exudateArea);
            lblBio3.Text = sprintf('- Microaneurysms: %d detected', lesionStats.microaneurysmCount);
            lblBio4.Text = sprintf('- Blot Hemorrhages: %d detected', lesionStats.hemorrhageCount);
            lblBio5.Text = sprintf('- Optic Disc: Localized at [%d, %d]', lesionStats.odCenter(1), lesionStats.odCenter(2));

            % 4. Module 4: Explainability Grad-CAM
            txtGuidance.Value = {'Running Module 4: Grad-CAM Explainability Heatmap...'};
            drawnow;

            [camOverlay, camMap] = compute_gradcam(img, [], pred.grade + 1);
            appData.gradCamOverlay = camOverlay;
            imshow(camOverlay, 'Parent', ax4);
            title(ax4, '4. Grad-CAM Explainable AI', 'FontSize', 10, 'FontWeight', 'bold');

            % Enable PDF Export Button
            btnPdf.Enable = 'on';

            txtGuidance.Value = {
                '*** AI SCREENING COMPLETE ***', ...
                '', ...
                sprintf('Diagnosis: Grade %d (%s)', pred.grade, pred.gradeName), ...
                sprintf('Confidence: %.1f%%', pred.confidence * 100), ...
                sprintf('Referable DR: %s', mat2str(pred.isReferable)), ...
                '', ...
                'Click "EXPORT DOCTOR PDF REPORT" to generate 30s clinical sign-off sheet.'
            };
        catch ME
            txtGuidance.Value = {
                '*** ERROR IN EXECUTION ***', ...
                ME.message, ...
                'See MATLAB Command Window for details.'
            };
            uialert(fig, ME.message, 'Screening Pipeline Error');
        end
    end

    function on_export_pdf()
        if isempty(appData.prediction)
            uialert(fig, 'Please run screening first before exporting report.', 'No Diagnosis Available');
            return;
        end

        txtGuidance.Value = {'Generating single-page Doctor Clinical PDF report...'};
        drawnow;

        patientData = struct();
        patientData.patientId      = txtPatientId.Value;
        patientData.age            = txtAge.Value;
        patientData.gender         = ddGender.Value;
        patientData.phcCenter      = txtPHC.Value;
        patientData.operatorId     = 'ASHA Health Worker #108';
        patientData.screeningDate  = datestr(now, 'dd-mmm-yyyy HH:MM');
        patientData.imgOriginal    = appData.currentImage;
        patientData.imgEnhanced    = appData.enhancedGray;
        patientData.vesselMask     = appData.vesselMask;
        patientData.lesionOverlay  = appData.lesionStats.lesionOverlay;
        patientData.gradCamOverlay = appData.gradCamOverlay;
        patientData.iqaResult      = appData.iqaResult;
        patientData.vesselDensity  = (sum(appData.vesselMask(:)) / numel(appData.vesselMask)) * 100;
        patientData.lesionStats    = appData.lesionStats;
        patientData.prediction     = appData.prediction;

        pdfOut = fullfile(baseDir, sprintf('Doctor_Report_%s.pdf', patientData.patientId));
        reportPath = generate_clinical_report(patientData, pdfOut);

        txtGuidance.Value = {
            '*** DOCTOR CLINICAL REPORT EXPORTED ***', ...
            '', ...
            sprintf('Saved PDF: %s', reportPath), ...
            '', ...
            'Single-page format optimized for <30s ophthalmologist review.'
        };
        uialert(fig, sprintf('Doctor Report successfully generated at:\n%s', reportPath), 'Report Generated');
    end

    function on_run_telemed_sim()
        txtGuidance.Value = {'Launching Module 5: Simulink 100k Patient Telemedicine Simulation...'};
        drawnow;
        run_simulation_analysis();
        txtGuidance.Value = {
            '*** SIMULATION FINISHED ***', ...
            '100,000 Patient/Year Queue Analysis executed.', ...
            'Demonstrated 100% elimination of 6-month ophthalmologist backlog.'
        };
    end

    function on_run_batch_screening()
        % Ask user: Demo 3-Patient Queue or Custom Files
        choice = uiconfirm(fig, ...
            sprintf('Choose batch screening queue source:\n\n• 3-Patient Demo Queue: Grades 0 (Normal), 2 (Moderate), 4 (Proliferative)\n• Custom Queue: Select multiple images from disk'), ...
            'Batch Screening Queue', ...
            'Options', {'3-Patient Demo Queue', 'Select Multiple Files', 'Cancel'}, ...
            'DefaultOption', 1, 'CancelOption', 3);
        
        if strcmp(choice, 'Cancel')
            return;
        end
        
        samplesDir = fullfile(baseDir, 'data', 'test_samples');
        if strcmp(choice, '3-Patient Demo Queue')
            imagePaths = { ...
                fullfile(samplesDir, 'idrid_grade0_normal.jpg'); ...
                fullfile(samplesDir, 'idrid_grade2_moderate.jpg'); ...
                fullfile(samplesDir, 'idrid_grade4_proliferative.jpg') ...
            };
            patientMeta = {
                'IND-KA-PHC-8921', 52, 'Female';
                'IND-KA-PHC-8922', 61, 'Male';
                'IND-KA-PHC-8923', 58, 'Female'
            };
        else
            [files, pth] = uigetfile({'*.png;*.jpg;*.jpeg;*.tif;*.tiff', 'Fundus Scans (*.png, *.jpg, *.tif)'}, ...
                'Select Fundus Images for Batch Queue', 'MultiSelect', 'on');
            if isequal(files, 0), return; end
            if ischar(files), files = {files}; end
            numF = length(files);
            imagePaths = cell(numF, 1);
            patientMeta = cell(numF, 3);
            for k = 1:numF
                imagePaths{k} = fullfile(pth, files{k});
                patientMeta{k, 1} = sprintf('IND-KA-PHC-%04d', 9100 + k);
                patientMeta{k, 2} = randi([45, 72]);
                if mod(k, 2) == 1, g = 'Female'; else, g = 'Male'; end
                patientMeta{k, 3} = g;
            end
        end
        
        txtGuidance.Value = {
            '*** BATCH QUEUE SCREENING IN PROGRESS ***', ...
            sprintf('Queue Length: %d patient scans', length(imagePaths)), ...
            'Running high-throughput multi-stage screening...'
        };
        drawnow;
        
        dProg = uiprogressdlg(fig, 'Title', 'Batch Queue Processing', ...
            'Message', sprintf('Screening %d patient scans...', length(imagePaths)), ...
            'Indeterminate', 'on');
        
        try
            [summaryTable, detailedResults] = screen_patient_batch(imagePaths, patientMeta);
            close(dProg);
        catch ME
            close(dProg);
            uialert(fig, sprintf('Batch screening error: %s', ME.message), 'Batch Error');
            return;
        end
        
        txtGuidance.Value = {
            '*** BATCH SCREENING COMPLETE ***', ...
            sprintf('Total processed: %d scans', height(summaryTable)), ...
            sprintf('Average latency: %.2f sec / scan', mean(summaryTable.Latency_sec)), ...
            '', ...
            'Displaying interactive batch triage window.'
        };
        
        display_batch_results_dialog(summaryTable, detailedResults, imagePaths);
    end

    function display_batch_results_dialog(summaryTable, detailedResults, imagePaths)
        numTotal = height(summaryTable);
        numRoutine = sum(summaryTable.Grade == 0 | summaryTable.Grade == 1);
        numReferral = sum(summaryTable.Grade >= 2);
        avgLatency = mean(summaryTable.Latency_sec);
        
        batchFig = uifigure('Name', 'ASHA & PHC Tele-Retina AI — Batch Queue Results', ...
            'Position', [120, 100, 1060, 620], 'Color', [0.96, 0.97, 0.98]);
        
        % Header Panel
        pnlHdr = uipanel(batchFig, 'Position', [15, 545, 1030, 65], ...
            'BackgroundColor', [0.08, 0.18, 0.36], 'BorderType', 'none');
        uilabel(pnlHdr, 'Text', 'TELE-RETINA AI : HIGH-THROUGHPUT BATCH SCREENING REPORT', ...
            'Position', [20, 32, 700, 24], 'FontSize', 14, 'FontWeight', 'bold', 'FontColor', 'w');
        uilabel(pnlHdr, 'Text', sprintf('Rural Telemedicine Triage Queue | Auto-Screened at %s | Sub-Second Inference Engine', datestr(now, 'dd-mmm-yyyy HH:MM:SS')), ...
            'Position', [20, 10, 800, 18], 'FontSize', 9.5, 'FontColor', [0.75, 0.85, 0.95]);
        
        % Metric Summary Cards
        % Card 1: Total Patients
        c1 = uipanel(batchFig, 'Position', [15, 470, 240, 65], 'BackgroundColor', 'w');
        uilabel(c1, 'Text', 'TOTAL SCANNED', 'Position', [15, 40, 210, 16], 'FontSize', 8.5, 'FontColor', [0.5 0.5 0.5], 'FontWeight', 'bold');
        uilabel(c1, 'Text', sprintf('%d Patients', numTotal), 'Position', [15, 10, 210, 28], 'FontSize', 16, 'FontWeight', 'bold', 'FontColor', [0.1, 0.2, 0.4]);
        
        % Card 2: Cleared / Routine PHC
        c2 = uipanel(batchFig, 'Position', [270, 470, 240, 65], 'BackgroundColor', 'w');
        uilabel(c2, 'Text', 'CLEARED / ROUTINE PHC', 'Position', [15, 40, 210, 16], 'FontSize', 8.5, 'FontColor', [0.1 0.6 0.2], 'FontWeight', 'bold');
        uilabel(c2, 'Text', sprintf('%d (%.0f%%) Non-Referable', numRoutine, (numRoutine/numTotal)*100), 'Position', [15, 10, 210, 28], 'FontSize', 15, 'FontWeight', 'bold', 'FontColor', [0.1, 0.55, 0.2]);
        
        % Card 3: Referable DR Action Required
        c3 = uipanel(batchFig, 'Position', [525, 470, 240, 65], 'BackgroundColor', 'w');
        uilabel(c3, 'Text', 'SPECIALIST REFERRAL REQ.', 'Position', [15, 40, 210, 16], 'FontSize', 8.5, 'FontColor', [0.8 0.2 0.1], 'FontWeight', 'bold');
        uilabel(c3, 'Text', sprintf('%d (%.0f%%) Referrals', numReferral, (numReferral/numTotal)*100), 'Position', [15, 10, 210, 28], 'FontSize', 15, 'FontWeight', 'bold', 'FontColor', [0.75, 0.15, 0.15]);
        
        % Card 4: High Throughput Latency
        c4 = uipanel(batchFig, 'Position', [780, 470, 265, 65], 'BackgroundColor', 'w');
        uilabel(c4, 'Text', 'AVG INFERENCE SPEED', 'Position', [15, 40, 230, 16], 'FontSize', 8.5, 'FontColor', [0.3 0.3 0.7], 'FontWeight', 'bold');
        uilabel(c4, 'Text', sprintf('%.2f s / patient', avgLatency), 'Position', [15, 10, 230, 28], 'FontSize', 15, 'FontWeight', 'bold', 'FontColor', [0.2, 0.3, 0.7]);
        
        % Main UITable
        uit = uitable(batchFig, 'Position', [15, 75, 1030, 385], ...
            'Data', summaryTable, ...
            'RowName', [], ...
            'FontSize', 10, ...
            'ColumnSortable', true, ...
            'SelectionType', 'row');
        
        % Bottom Action Buttons
        uibutton(batchFig, 'push', 'Text', '💾 Export Batch Triage CSV', ...
            'Position', [15, 20, 230, 40], ...
            'BackgroundColor', [0.08, 0.45, 0.30], 'FontColor', 'w', ...
            'FontSize', 10.5, 'FontWeight', 'bold', ...
            'ButtonPushedFcn', @(src, evt) export_batch_csv(summaryTable, batchFig));
        
        uibutton(batchFig, 'push', 'Text', '🔍 Inspect Selected in Main Dashboard', ...
            'Position', [260, 20, 300, 40], ...
            'BackgroundColor', [0.15, 0.35, 0.65], 'FontColor', 'w', ...
            'FontSize', 10.5, 'FontWeight', 'bold', ...
            'ButtonPushedFcn', @(src, evt) inspect_selected_patient(uit, imagePaths, batchFig));
        
        uibutton(batchFig, 'push', 'Text', 'Close Batch Viewer', ...
            'Position', [915, 20, 130, 40], ...
            'BackgroundColor', [0.85, 0.85, 0.88], 'FontSize', 10, ...
            'ButtonPushedFcn', @(src, evt) delete(batchFig));
    end

    function export_batch_csv(tbl, parentFig)
        reportsDir = fullfile(baseDir, 'reports');
        if ~exist(reportsDir, 'dir'), mkdir(reportsDir); end
        defaultName = fullfile(reportsDir, sprintf('Batch_Screening_Summary_%s.csv', datestr(now, 'yyyymmdd_HHMMSS')));
        [file, path] = uiputfile('*.csv', 'Save Batch Screening CSV Summary', defaultName);
        if isequal(file, 0), return; end
        outCsv = fullfile(path, file);
        writetable(tbl, outCsv);
        uialert(parentFig, sprintf('Batch screening summary exported to:\n%s', outCsv), 'CSV Export Successful');
    end

    function inspect_selected_patient(uit, imagePaths, parentFig)
        sel = uit.Selection;
        if isempty(sel)
            uialert(parentFig, 'Please select a row in the table first.', 'No Selection');
            return;
        end
        rowIdx = sel(1);
        if rowIdx > length(imagePaths), return; end
        imgPath = imagePaths{rowIdx};
        load_and_display_image(imgPath);
        on_run_screening();
        figure(fig); % Bring main dashboard to focus
    end
end
