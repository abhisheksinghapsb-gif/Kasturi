% EVALUATE_REAL_TESTSET Evaluates 103 unseen IDRiD test cases
clear; clc;
addpath(genpath('g:\sih\src'));
addpath('g:\sih\data');

testDir = 'g:\sih\data\testing_dataset';
imds = imageDatastore(testDir, 'IncludeSubfolders', true, 'LabelSource', 'foldernames');
numImages = length(imds.Files);

yTrue = zeros(numImages, 1);
yPred = zeros(numImages, 1);
scores = zeros(numImages, 1);

fprintf('Evaluating %d unseen test cases across complete clinical pipeline...\n', numImages);
for i = 1:numImages
    im = imread(imds.Files{i});
    if size(im, 1) > 512 || size(im, 2) > 512, im = imresize(im, [512, 512]); end
    
    lblStr = char(imds.Labels(i));
    yTrue(i) = str2double(lblStr);
    
    [eg, ~] = enhance_fundus(im);
    [vm, vd] = segment_vessels(eg);
    ls = detect_lesions(im, eg, vm);
    pred = classify_dr(im, [], ls);
    
    yPred(i) = pred.grade;
    scores(i) = pred.referableScore;
end

% Binary Referable DR (Grade >= 2)
binTrue = yTrue >= 2;
binPred = yPred >= 2;

TP = sum(binTrue & binPred);
FP = sum(~binTrue & binPred);
TN = sum(~binTrue & ~binPred);
FN = sum(binTrue & ~binPred);

sens = TP / max(1, (TP + FN));
spec = TN / max(1, (TN + FP));
acc  = (TP + TN) / numImages;
prec = TP / max(1, (TP + FP));
npv  = TN / max(1, (TN + FN));
f1   = 2 * (prec * sens) / max(1e-5, (prec + sens));
balAcc = (sens + spec) / 2;

% AUC calculation
[~, sortIdx] = sort(scores, 'descend');
sortedTrue = binTrue(sortIdx);
cumTP = cumsum(sortedTrue) / max(1, sum(sortedTrue));
cumFP = cumsum(~sortedTrue) / max(1, sum(~sortedTrue));
auc = trapz([0; cumFP; 1], [0; cumTP; 1]);

% Multi-class Confusion Matrix
confMat = confusionmat(yTrue, yPred);

fprintf('\n====================================================================\n');
fprintf('        OFFICIAL CLINICAL BENCHMARK EVALUATION (IDRiD TEST SET)\n');
fprintf('====================================================================\n');
fprintf('  Total Test Cases Evaluated    : %d patients\n', numImages);
fprintf('  Normal / Mild (G0-1, Non-Ref) : %d patients\n', sum(~binTrue));
fprintf('  Referable DR (G2-4, Vision Risk): %d patients\n', sum(binTrue));
fprintf('--------------------------------------------------------------------\n');
fprintf('  CONFUSION MATRIX (Binary Referable DR - Grade 2+):\n');
fprintf('                    Predicted Non-Ref   Predicted Referable\n');
fprintf('    Actual Non-Ref :      %3d (TN)              %3d (FP)\n', TN, FP);
fprintf('    Actual Referable:     %3d (FN)              %3d (TP)\n', FN, TP);
fprintf('--------------------------------------------------------------------\n');
fprintf('  KEY CLINICAL METRICS:\n');
fprintf('    SENSITIVITY (Recall)       : %6.2f%%   (SIH Target: > 90.0%%)\n', sens*100);
fprintf('    SPECIFICITY                : %6.2f%%   (SIH Target: > 85.0%%)\n', spec*100);
fprintf('    OVERALL ACCURACY           : %6.2f%%\n', acc*100);
fprintf('    BALANCED ACCURACY          : %6.2f%%\n', balAcc*100);
fprintf('    PRECISION (PPV)            : %6.2f%%\n', prec*100);
fprintf('    NEGATIVE PRED VALUE (NPV)  : %6.2f%%\n', npv*100);
fprintf('    F1-SCORE                   : %6.4f\n', f1);
fprintf('    AREA UNDER ROC (AUC)       : %6.4f\n', auc);
fprintf('====================================================================\n');
fprintf('  MULTI-CLASS CONFUSION MATRIX (Grade 0 to 4):\n');
disp(array2table(confMat, 'VariableNames', {'Pred_G0','Pred_G1','Pred_G2','Pred_G3','Pred_G4'}, ...
    'RowNames', {'True_G0','True_G1','True_G2','True_G3','True_G4'}));
fprintf('====================================================================\n\n');
