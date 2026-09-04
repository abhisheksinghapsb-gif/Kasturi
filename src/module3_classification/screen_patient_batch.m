function [summaryTable, detailedResults] = screen_patient_batch(imagePaths, patientMeta)
% SCREEN_PATIENT_BATCH Bulk / Queue automated screening for multiple fundus images.
% Processes patients sequentially with sub-second latency per patient.
    if nargin < 1 || isempty(imagePaths)
        rootDir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
        samplesDir = fullfile(rootDir, 'data', 'test_samples');
        imagePaths = {
            fullfile(samplesDir, 'idrid_grade0_normal.jpg'),
            fullfile(samplesDir, 'idrid_grade2_moderate.jpg'),
            fullfile(samplesDir, 'idrid_grade4_proliferative.jpg')
        };
    end
    numPatients = length(imagePaths);
    if nargin < 2 || isempty(patientMeta)
        patientMeta = cell(numPatients, 3);
        for k = 1:numPatients
            patientMeta{k, 1} = sprintf('IND-KA-PHC-%04d', 8920 + k);
            patientMeta{k, 2} = randi([48, 68]);
            if mod(k, 2) == 1, g = 'Female'; else, g = 'Male'; end
            patientMeta{k, 3} = g;
        end
    end
    PatientID       = cell(numPatients, 1);
    Filename        = cell(numPatients, 1);
    QualityStatus   = cell(numPatients, 1);
    BRISQUE         = zeros(numPatients, 1);
    PredictedGrade  = zeros(numPatients, 1);
    ClinicalLabel   = cell(numPatients, 1);
    ReferralRisk    = cell(numPatients, 1);
    TriageBadge     = cell(numPatients, 1);
    ActionRequired  = cell(numPatients, 1);
    DurationSec     = zeros(numPatients, 1);
    detailedResults = cell(numPatients, 1);
    for i = 1:numPatients
        tP = tic;
        imgPath = imagePaths{i};
        [~, fName, fExt] = fileparts(imgPath);
        PatientID{i} = patientMeta{i, 1};
        Filename{i}  = [fName, fExt];
        try
            im = imread(imgPath);
            if size(im, 1) > 512 || size(im, 2) > 512, im = imresize(im, [512, 512]); end
            iqa = evaluate_image_quality(im);
            QualityStatus{i} = iqa.status;
            BRISQUE(i)       = round(iqa.brisqueScore, 1);
            if strcmp(iqa.status, 'REJECT')
                PredictedGrade(i)  = -1;
                ClinicalLabel{i}   = 'Ungradeable Scan';
                ReferralRisk{i}    = '--';
                TriageBadge{i}     = 'RECAPTURE REQUIRED';
                ActionRequired{i}  = iqa.feedback;
                det = struct(); det.patientId = PatientID{i}; det.image = im; det.iqa = iqa; det.prediction = []; detailedResults{i} = det;
            else
                [eg, ~] = enhance_fundus(im);
                [vm, vd] = segment_vessels(eg);
                ls = detect_lesions(im, eg, vm);
                pred = classify_dr(im, [], ls);
                PredictedGrade(i)  = pred.grade;
                ClinicalLabel{i}   = pred.gradeName;
                ReferralRisk{i}    = sprintf('%.1f%%', pred.referableScore * 100);
                switch pred.grade
                    case 0, TriageBadge{i} = 'CLEARED: ROUTINE ANNUAL'; ActionRequired{i} = 'Rescreen in 12 mo at PHC.';
                    case 1, TriageBadge{i} = 'PHC MONITORING (NON-REF)'; ActionRequired{i} = 'Microaneurysms only. Rescreen 6-12 mo.';
                    case 2, TriageBadge{i} = 'MODERATE REFERRAL (30d)'; ActionRequired{i} = 'Secondary Eye Clinic within 30 days.';
                    case 3, TriageBadge{i} = 'HIGH RISK REFERRAL (<14d)'; ActionRequired{i} = 'Severe NPDR. Specialist within 2 weeks.';
                    case 4, TriageBadge{i} = 'URGENT REFERRAL (<48h)'; ActionRequired{i} = 'Proliferative DR. Tertiary Care ASAP.';
                end
                det = struct(); det.patientId = PatientID{i}; det.image = im; det.enhanced = eg; det.vesselMask = vm; det.vesselDensity = vd; det.lesions = ls; det.iqa = iqa; det.prediction = pred; detailedResults{i} = det;
            end
        catch ME
            QualityStatus{i} = 'ERROR'; ClinicalLabel{i} = ME.message; TriageBadge{i} = 'PIPELINE ERROR'; ActionRequired{i} = 'Check image format.';
        end
        DurationSec(i) = round(toc(tP), 3);
    end
    summaryTable = table(PatientID, Filename, QualityStatus, BRISQUE, PredictedGrade, ClinicalLabel, ReferralRisk, TriageBadge, ActionRequired, DurationSec, 'VariableNames', {'Patient_ID', 'Image_File', 'Quality', 'BRISQUE', 'Grade', 'Diagnosis', 'Referral_Risk', 'Triage_Status', 'Action_Prescribed', 'Latency_sec'});
end