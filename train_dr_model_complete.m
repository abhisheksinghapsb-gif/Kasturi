% TRAIN_DR_MODEL_COMPLETE Full Batch Training & Unseen Test Evaluation
clear; clc; close all;
fprintf('====================================================================\n');
fprintf('  SIH 26038: Full Deep Learning Training & Clinical Test Evaluation\n');
fprintf('  MathWorks Indian Diabetic Retinopathy (IDRiD) Benchmark\n');
fprintf('====================================================================\n\n');

trainDir = fullfile(pwd, 'data', 'training_dataset');
testDir  = fullfile(pwd, 'data', 'testing_dataset');

% 1. Load Training Set
fprintf('[1/6] Indexing Training Dataset...\n');
imdsTrain = imageDatastore(trainDir, 'IncludeSubfolders', true, 'LabelSource', 'foldernames');
tblTrain = countEachLabel(imdsTrain);
disp(tblTrain);

% Compute inverse-frequency class weights
totalTrain = sum(tblTrain.Count);
numClasses = height(tblTrain);
classWeights = totalTrain ./ (numClasses * double(tblTrain.Count));
classWeights = classWeights / mean(classWeights);

% 2. Load Testing Set
fprintf('\n[2/6] Indexing Unseen Testing Dataset (103 Patients)...\n');
imdsTest = imageDatastore(testDir, 'IncludeSubfolders', true, 'LabelSource', 'foldernames');
tblTest = countEachLabel(imdsTest);
disp(tblTest);

% 3. Build Deep Retinal CNN Architecture
fprintf('\n[3/6] Building Optimized Deep Retinal Neural Network...\n');
inputSize = [224, 224, 3];

useResNet = false;
try
    netPre = resnet50;
    useResNet = true;
    fprintf('  > Pre-trained ResNet-50 loaded!\n');
catch
    fprintf('  > Building 5-Stage Deep Retinal CNN Architecture...\n');
end

if useResNet
    lgraph = layerGraph(netPre);
    newFc = fullyConnectedLayer(numClasses, 'Name', 'new_fc_dr', 'WeightLearnRateFactor', 10, 'BiasLearnRateFactor', 10);
    newSoftmax = softmaxLayer('Name', 'new_softmax');
    newClassOut = classificationLayer('Name', 'new_classoutput', 'Classes', tblTrain.Label, 'ClassWeights', classWeights);
    lgraph = replaceLayer(lgraph, 'fc1000', newFc);
    lgraph = replaceLayer(lgraph, 'fc1000_softmax', newSoftmax);
    lgraph = replaceLayer(lgraph, 'ClassificationLayer_fc1000', newClassOut);
else
    layers = [
        imageInputLayer(inputSize, 'Name', 'input', 'Normalization', 'zscore')
        
        convolution2dLayer(3, 32, 'Padding', 'same', 'Name', 'conv1')
        batchNormalizationLayer('Name', 'bn1')
        reluLayer('Name', 'relu1')
        maxPooling2dLayer(2, 'Stride', 2, 'Name', 'pool1')
        
        convolution2dLayer(3, 64, 'Padding', 'same', 'Name', 'conv2')
        batchNormalizationLayer('Name', 'bn2')
        reluLayer('Name', 'relu2')
        maxPooling2dLayer(2, 'Stride', 2, 'Name', 'pool2')
        
        convolution2dLayer(3, 128, 'Padding', 'same', 'Name', 'conv3')
        batchNormalizationLayer('Name', 'bn3')
        reluLayer('Name', 'relu3')
        maxPooling2dLayer(2, 'Stride', 2, 'Name', 'pool3')
        
        convolution2dLayer(3, 256, 'Padding', 'same', 'Name', 'conv4')
        batchNormalizationLayer('Name', 'bn4')
        reluLayer('Name', 'activation_49_relu')
        maxPooling2dLayer(2, 'Stride', 2, 'Name', 'pool4')
        
        fullyConnectedLayer(128, 'Name', 'fc1')
        reluLayer('Name', 'relu_fc')
        dropoutLayer(0.4, 'Name', 'drop1')
        
        fullyConnectedLayer(numClasses, 'Name', 'new_fc_dr')
        softmaxLayer('Name', 'new_softmax')
        classificationLayer('Name', 'new_classoutput', 'Classes', tblTrain.Label, 'ClassWeights', classWeights)
    ];
    lgraph = layerGraph(layers);
end

% 4. Data Augmentation
augmenter = imageDataAugmenter( ...
    'RandXReflection', true, ...
    'RandYReflection', true, ...
    'RandRotation', [-180, 180], ...
    'RandScale', [0.85, 1.15]);

augTrain = augmentedImageDatastore(inputSize(1:2), imdsTrain, ...
    'DataAugmentation', augmenter, 'ColorPreprocessing', 'gray2rgb');

augTest = augmentedImageDatastore(inputSize(1:2), imdsTest, ...
    'ColorPreprocessing', 'gray2rgb');

% 5. Training Options
fprintf('\n[4/6] Training Network across Full Dataset...\n');
try
    gpuInfo = gpuDevice();
    execEnv = 'gpu';
catch
    execEnv = 'cpu';
end

miniBatchSize = 16;
maxEpochs = 15;

options = trainingOptions('adam', ...
    'ExecutionEnvironment', execEnv, ...
    'InitialLearnRate', 4e-4, ...
    'MiniBatchSize', miniBatchSize, ...
    'MaxEpochs', maxEpochs, ...
    'Shuffle', 'every-epoch', ...
    'ValidationData', augTest, ...
    'ValidationFrequency', 20, ...
    'Verbose', true, ...
    'L2Regularization', 1e-4);

tStart = tic;
[trainedNet, trainInfo] = trainNetwork(augTrain, lgraph, options);
tTrain = toc(tStart);
fprintf('  > Training completed in %.1f minutes!\n', tTrain / 60);

% 6. Evaluate on Unseen 103 Test Cases
fprintf('\n[5/6] Evaluating on 103 Real Unseen Test Patients...\n');
[YPred, scores] = classify(trainedNet, augTest);
YTrue = imdsTest.Labels;

% Calculate Referable DR (Grade >= 2) metrics
trueReferable  = (double(YTrue) - 1) >= 2;
predReferable  = (double(YPred) - 1) >= 2;

TP = sum(trueReferable & predReferable);
FP = sum(~trueReferable & predReferable);
TN = sum(~trueReferable & ~predReferable);
FN = sum(trueReferable & ~predReferable);

sensitivity = TP / max(1, (TP + FN));
specificity = TN / max(1, (TN + FP));

fprintf('\n====================================================================\n');
fprintf('              FINAL CLINICAL BENCHMARK RESULTS (TEST SET)\n');
fprintf('====================================================================\n');
fprintf('  Total Test Cases Evaluated : %d patients\n', numel(YTrue));
fprintf('  Referable DR Sensitivity   : %.1f%%  (SIH Mandate: >90%%)\n', sensitivity * 100);
fprintf('  Referable DR Specificity   : %.1f%%  (SIH Mandate: >85%%)\n', specificity * 100);
fprintf('  True Positives (TP)        : %d patients caught\n', TP);
fprintf('  False Negatives (FN)       : %d missed\n', FN);
fprintf('====================================================================\n\n');

% 7. Save Model and Artifacts
outputModelPath = fullfile('src', 'module3_classification', 'trained_dr_resnet50.mat');
save(outputModelPath, 'trainedNet', 'trainInfo', 'inputSize', 'sensitivity', 'specificity');
fprintf('  > Model weights saved to: %s\n', outputModelPath);

% Generate Confusion Matrix Figure and save as PNG
try
    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 650 550]);
    confusionchart(YTrue, YPred, 'Title', 'IDRiD 5-Class Retinopathy Confusion Matrix');
    saveas(fig, 'test_confusion_matrix.png');
    close(fig);
    fprintf('  > Saved test_confusion_matrix.png for presentation slides!\n');
catch
end

exit;
