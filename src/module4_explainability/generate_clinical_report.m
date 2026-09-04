function reportPath = generate_clinical_report(patientData, outputPdfPath)
% GENERATE_CLINICAL_REPORT Assembles an automated, standardized single-page
% clinical decision-support report for rapid (<30 second) ophthalmologist validation.
%
% Features:
%   - Multi-panel visual diagnostic grid (Original, Enhanced, Vessels, Lesions, Grad-CAM)
%   - Prominent color-coded Referral Urgency Badge
%   - Quantitative lesion & vascular biomarkers
%   - High-fidelity single-page PDF generation via exportgraphics
%
% Syntax:
%   reportPath = generate_clinical_report(patientData)
%   reportPath = generate_clinical_report(patientData, outputPdfPath)
%
% Inputs:
%   patientData   - Struct containing clinical data:
%                   .patientId    : String (e.g. 'IND-PHC-2026-0481')
%                   .age          : Integer (e.g. 54)
%                   .gender       : String (e.g. 'Female')
%                   .phcCenter    : String (e.g. 'PHC Mulbagal, Kolar District')
%                   .operatorId   : String (e.g. 'ASHA-ANM-104')
%                   .screeningDate: String (e.g. '04-Sep-2026')
%                   .imgOriginal  : Original RGB fundus
%                   .imgEnhanced  : CLAHE-enhanced fundus
%                   .vesselMask   : Binary vessel tree
%                   .lesionOverlay: Lesion highlight image
%                   .gradCamOverlay: Grad-CAM blended heatmap image
%                   .iqaResult    : Struct from evaluate_image_quality
%                   .vesselDensity: Scalar percentage
%                   .lesionStats  : Struct from detect_lesions
%                   .prediction   : Struct from classify_dr
%   outputPdfPath - (Optional) Destination PDF path (default: 'Doctor_Screening_Report.pdf')
%
% Outputs:
%   reportPath    - Absolute filepath to generated PDF
%
% SIH Problem Statement 26038 | MathWorks Sponsored Prototype

    if nargin < 2 || isempty(outputPdfPath)
        outputPdfPath = fullfile(pwd, 'Doctor_Screening_Report.pdf');
    end

    % Set default patient metadata if omitted
    if ~isfield(patientData, 'patientId'),     patientData.patientId     = 'IND-KA-PHC-8921'; end
    if ~isfield(patientData, 'age'),           patientData.age           = 58; end
    if ~isfield(patientData, 'gender'),        patientData.gender        = 'Female'; end
    if ~isfield(patientData, 'phcCenter'),     patientData.phcCenter     = 'PHC Devanahalli, Rural Cluster 4'; end
    if ~isfield(patientData, 'operatorId'),    patientData.operatorId    = 'ASHA Worker #108'; end
    if ~isfield(patientData, 'screeningDate'), patientData.screeningDate = datestr(now, 'dd-mmm-yyyy HH:MM'); end

    % Create invisible figure for clean PDF rendering
    fig = figure('Name', 'Doctor Screening Report', ...
        'Color', 'w', ...
        'Units', 'inches', ...
        'Position', [0.5, 0.5, 8.5, 11], ... % Standard US Letter 8.5 x 11 in
        'Visible', 'off');

    % ---------------------------------------------------------------------
    % Section 1: Header & Facility Branding Banner
    % ---------------------------------------------------------------------
    % Top title banner
    annotation(fig, 'rectangle', [0.05, 0.90, 0.90, 0.08], ...
        'FaceColor', [0.08, 0.22, 0.45], 'EdgeColor', 'none');
    
    annotation(fig, 'textbox', [0.06, 0.935, 0.88, 0.04], ...
        'String', 'NATIONAL TELE-OPHTHALMOLOGY AI SCREENING PROGRAM', ...
        'Color', 'w', 'FontSize', 14, 'FontWeight', 'bold', ...
        'EdgeColor', 'none', 'HorizontalAlignment', 'left');

    annotation(fig, 'textbox', [0.06, 0.905, 0.88, 0.03], ...
        'String', 'Explainable AI Clinical Decision Support System | Rural PHC Triage (SIH PS 26038)', ...
        'Color', [0.85, 0.92, 1.0], 'FontSize', 9.5, ...
        'EdgeColor', 'none', 'HorizontalAlignment', 'left');

    % Patient Details Panel (Box)
    annotation(fig, 'rectangle', [0.05, 0.805, 0.90, 0.085], ...
        'FaceColor', [0.96, 0.97, 0.99], 'EdgeColor', [0.80, 0.85, 0.92], 'LineWidth', 1);

    patientMetaStr = {
        sprintf('\\bfPatient ID:\\rm  %s        \\bfAge/Sex:\\rm  %d / %s        \\bfScreening Date:\\rm  %s', ...
            patientData.patientId, patientData.age, patientData.gender, patientData.screeningDate), ...
        sprintf('\\bfPHC Health Centre:\\rm  %s        \\bfFrontline Operator:\\rm  %s', ...
            patientData.phcCenter, patientData.operatorId)
    };
    annotation(fig, 'textbox', [0.065, 0.81, 0.87, 0.075], ...
        'String', patientMetaStr, ...
        'FontSize', 9.5, 'EdgeColor', 'none', 'Interpreter', 'tex');

    % ---------------------------------------------------------------------
    % Section 2: AI Triage Recommendation & Urgency Badge
    % ---------------------------------------------------------------------
    pred = patientData.prediction;
    if pred.grade >= 4 || pred.referableScore >= 0.75
        badgeColor = [0.85, 0.12, 0.15]; % Urgent Red
        badgeTitle = 'URGENT SPECIALIST REFERRAL REQUIRED (<48 HOURS)';
        badgeDesc  = 'High risk of irreversible vision loss. Tertiary Vitreoretinal evaluation mandatory.';
    elseif pred.isReferable
        badgeColor = [0.92, 0.55, 0.05]; % Amber Warning
        badgeTitle = 'SECONDARY OPHTHALMOLOGY REFERRAL (WITHIN 30 DAYS)';
        badgeDesc  = 'Clinically significant Diabetic Retinopathy detected. Comprehensive dilated fundus exam advised.';
    else
        badgeColor = [0.12, 0.65, 0.28]; % Green Pass
        badgeTitle = 'NON-REFERABLE: ROUTINE ANNUAL SCREENING';
        badgeDesc  = 'No sight-threatening diabetic retinopathy detected. Schedule follow-up in 12 months at PHC.';
    end

    % Triage Badge Box
    annotation(fig, 'rectangle', [0.05, 0.705, 0.90, 0.085], ...
        'FaceColor', badgeColor, 'EdgeColor', 'none');
    annotation(fig, 'textbox', [0.06, 0.745, 0.88, 0.04], ...
        'String', sprintf('TRIAGE ACTION:  %s', badgeTitle), ...
        'Color', 'w', 'FontSize', 11.5, 'FontWeight', 'bold', ...
        'EdgeColor', 'none', 'HorizontalAlignment', 'center');
    annotation(fig, 'textbox', [0.06, 0.71, 0.88, 0.035], ...
        'String', badgeDesc, ...
        'Color', [1.0, 1.0, 0.95], 'FontSize', 9.5, ...
        'EdgeColor', 'none', 'HorizontalAlignment', 'center');

    % ---------------------------------------------------------------------
    % Section 3: Multi-Panel Visual Diagnostic Grid
    % ---------------------------------------------------------------------
    % 5 image views: [Original, Enhanced Green, Vessels, Lesion Overlay, Grad-CAM]
    axW = 0.165;
    axH = 0.165;
    axY = 0.505;
    spacing = 0.016;
    startX = 0.05;

    % Subplot 1: Original Fundus
    ax1 = axes(fig, 'Position', [startX, axY, axW, axH]);
    imshow(patientData.imgOriginal, 'Parent', ax1);
    title(ax1, '1. Raw Fundus Scan', 'FontSize', 8.5, 'FontWeight', 'bold');

    % Subplot 2: Enhanced Green (Rayleigh CLAHE)
    ax2 = axes(fig, 'Position', [startX + (axW + spacing)*1, axY, axW, axH]);
    imshow(patientData.imgEnhanced, 'Parent', ax2);
    title(ax2, '2. Enhanced Green', 'FontSize', 8.5, 'FontWeight', 'bold');

    % Subplot 3: Segmented Vasculature
    ax3 = axes(fig, 'Position', [startX + (axW + spacing)*2, axY, axW, axH]);
    imshow(patientData.vesselMask, 'Parent', ax3);
    title(ax3, '3. Retinal Vessels', 'FontSize', 8.5, 'FontWeight', 'bold');

    % Subplot 4: Lesion Overlay
    ax4 = axes(fig, 'Position', [startX + (axW + spacing)*3, axY, axW, axH]);
    imshow(patientData.lesionOverlay, 'Parent', ax4);
    title(ax4, '4. Lesion Detections', 'FontSize', 8.5, 'FontWeight', 'bold');

    % Subplot 5: Grad-CAM Heatmap
    ax5 = axes(fig, 'Position', [startX + (axW + spacing)*4, axY, axW, axH]);
    imshow(patientData.gradCamOverlay, 'Parent', ax5);
    title(ax5, '5. Grad-CAM XAI', 'FontSize', 8.5, 'FontWeight', 'bold');

    % Visual legend under images
    annotation(fig, 'textbox', [0.05, 0.465, 0.90, 0.03], ...
        'String', 'Legend: [Cyan]: Vascular Tree | [Yellow]: Hard Exudates (Lipids) | [Magenta]: Microaneurysms/Hemorrhages | [Jet Colormap]: AI Focus Regions', ...
        'FontSize', 8, 'FontAngle', 'italic', 'Color', [0.3, 0.3, 0.3], ...
        'EdgeColor', 'none', 'HorizontalAlignment', 'center');

    % ---------------------------------------------------------------------
    % Section 4: Quantitative Biomarkers & Diagnostic Probability Distribution
    % ---------------------------------------------------------------------
    % Left Panel: Quantitative Biomarkers Table
    annotation(fig, 'rectangle', [0.05, 0.20, 0.44, 0.25], ...
        'FaceColor', [0.98, 0.98, 0.99], 'EdgeColor', [0.82, 0.85, 0.88], 'LineWidth', 1);

    annotation(fig, 'textbox', [0.06, 0.41, 0.42, 0.03], ...
        'String', 'QUANTITATIVE BIOMARKER ANALYSIS', ...
        'FontSize', 9.5, 'FontWeight', 'bold', 'Color', [0.08, 0.22, 0.45], 'EdgeColor', 'none');

    biomarkerStr = {
        sprintf('\\bfImage Quality Assessment (IQA):\\rm  %s (BRISQUE: %.1f)', ...
            patientData.iqaResult.status, patientData.iqaResult.brisqueScore), ...
        sprintf('\\bfMean Illumination Level:\\rm  %.1f%%  (Dynamic Range: %.2f)', ...
            patientData.iqaResult.meanIllumination * 100, patientData.iqaResult.dynamicRange), ...
        sprintf('\\bfVascular Density (Coverage):\\rm  %.2f%% of FOV', ...
            patientData.vesselDensity), ...
        sprintf('\\bfHard Exudates (Bright Lesions):\\rm  %d clusters (%d px area)', ...
            patientData.lesionStats.exudateCount, patientData.lesionStats.exudateArea), ...
        sprintf('\\bfMicroaneurysms (Early NPDR):\\rm  %d detected foci', ...
            patientData.lesionStats.microaneurysmCount), ...
        sprintf('\\bfRetinal Blot Hemorrhages:\\rm  %d detected sites', ...
            patientData.lesionStats.hemorrhageCount), ...
        sprintf('\\bfOptic Disc Status:\\rm  Localized (Center: [%d, %d])', ...
            patientData.lesionStats.odCenter(1), patientData.lesionStats.odCenter(2))
    };
    annotation(fig, 'textbox', [0.06, 0.21, 0.42, 0.19], ...
        'String', biomarkerStr, ...
        'FontSize', 8.5, 'EdgeColor', 'none', 'Interpreter', 'tex');

    % Right Panel: AI Class Probabilities Bar Chart
    axBar = axes(fig, 'Position', [0.55, 0.24, 0.39, 0.16]);
    barLabels = {'Grade 0', 'Grade 1', 'Grade 2', 'Grade 3', 'Grade 4'};
    b = bar(axBar, 0:4, pred.probabilities * 100, 0.55, 'FaceColor', [0.15, 0.40, 0.70]);
    grid(axBar, 'on');
    set(axBar, 'XTick', 0:4, 'XTickLabel', barLabels, 'FontSize', 8);
    ylabel(axBar, 'Probability (%)', 'FontSize', 8, 'FontWeight', 'bold');
    title(axBar, sprintf('AI DR Severity: %s (Conf: %.1f%%)', pred.gradeName, pred.confidence * 100), ...
        'FontSize', 9, 'FontWeight', 'bold');
    ylim(axBar, [0, 105]);

    annotation(fig, 'textbox', [0.55, 0.20, 0.39, 0.03], ...
        'String', sprintf('Referable DR Risk Score P(Grade >= 2) = %.1f%%  (Operating Cutoff: 35.0%%)', pred.referableScore * 100), ...
        'FontSize', 8.2, 'FontWeight', 'bold', 'Color', [0.75, 0.15, 0.15], ...
        'EdgeColor', 'none', 'HorizontalAlignment', 'center');

    % ---------------------------------------------------------------------
    % Section 5: Doctor Sign-Off & Rural Telemedicine Audit Footer
    % ---------------------------------------------------------------------
    annotation(fig, 'rectangle', [0.05, 0.05, 0.90, 0.13], ...
        'FaceColor', [0.95, 0.96, 0.97], 'EdgeColor', [0.82, 0.85, 0.88], 'LineWidth', 1);

    doctorSignStr = {
        '\bfOPHTHALMOLOGIST TELEMEDICINE REVIEW & VALIDATION (Time required: under 30 seconds)\rm', ...
        'Clinical Impression: [  ] Concordant with AI diagnosis      [  ] Upgrade Severity      [  ] Downgrade / Artefact', ...
        'Action Prescribed:    [  ] Tele-Consultation Booked       [  ] Anti-VEGF / Laser Referral       [  ] PHC Annual Rescreen', ...
        'Reviewing Ophthalmologist Signature: _______________________      Date/Time: _____________________'
    };
    annotation(fig, 'textbox', [0.06, 0.055, 0.88, 0.115], ...
        'String', doctorSignStr, ...
        'FontSize', 8.5, 'EdgeColor', 'none', 'Interpreter', 'tex');

    % Save Report to PDF using exportgraphics
    drawnow;
    try
        exportgraphics(fig, outputPdfPath, 'ContentType', 'vector');
        fprintf('  [OK] Clinical Doctor Report successfully exported to PDF: %s\n', outputPdfPath);
    catch
        % Fallback print command
        print(fig, outputPdfPath, '-dpdf', '-r300');
        fprintf('  [OK] Clinical Doctor Report printed to PDF: %s\n', outputPdfPath);
    end

    % Also save a companion PNG image preview of the report
    [pDir, pName, ~] = fileparts(outputPdfPath);
    pngPreviewPath = fullfile(pDir, [pName, '_preview.png']);
    try
        exportgraphics(fig, pngPreviewPath, 'Resolution', 180);
    catch
        print(fig, pngPreviewPath, '-dpng', '-r180');
    end

    close(fig);
    reportPath = outputPdfPath;
end
