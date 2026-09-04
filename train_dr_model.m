% TRAIN_DR_MODEL Train / Fine-tune Deep Learning Model for Diabetic Retinopathy
% Optimized specifically for NVIDIA RTX 4050 (6 GB VRAM) & CPU
%
% Smart India Hackathon (SIH) Problem Statement 26038 | MathWorks
%
% This script:
%   1. Automatically checks and enables your NVIDIA RTX 4050 GPU / CPU.
%   2. Loads IDRiD dataset from data/training_dataset/ (413 images).
%   3. Solves class imbalance using Clinical Inverse-Frequency Class Weights.
%   4. Applies retinal data augmentation (flips, rotations, zoom).
%   5. Uses Pre-trained ResNet-50 (if add-on present) OR Native Deep Retinal CNN (Zero downloads).
%   6. Trains using ADAM (~1-2 mins).
%   7. Saves the trained network as 'trained_dr_resnet50.mat'.

clear; clc; close all;
fprintf('====================================================================\n');
fprintf('  SIH 26038: Deep Learning Training Script for Diabetic Retinopathy\n');
fprintf('  Target Hardware: NVIDIA RTX 4050 / CPU | MathWorks Pipeline\n');
fprintf('====================================================================\n\n');

% -------------------------------------------------------------------------
% 1. CONFIGURE DATASET PATH
% -------------------------------------------------------------------------
datasetDir = fullfile(pwd, 'data', 'training_dataset');

if ~exist(datasetDir, 'dir')
    error('Dataset path not found: %s', datasetDir);
end

% -------------------------------------------------------------------------
% 2. VERIFY GPU / CPU HARDWARE
% -------------------------------------------------------------------------
fprintf('[1/5] Checking Compute Acceleration...\n');
try
    gpuInfo = gpuDevice();
    fprintf('  > Active GPU: %s (%.1f GB VRAM Available)\n', ...
        gpuInfo.Name, gpuInfo.AvailableMemory / (1024^3));
    executionEnv = 'gpu';
catch
    fprintf('  > Active Compute: Multi-Core CPU.\n');
    executionEnv = 'cpu';
end

% -------------------------------------------------------------------------
% 3. LOAD IMAGES & COMPUTE INVERSE-FREQUENCY CLASS WEIGHTS
% -------------------------------------------------------------------------
fprintf('\n[2/5] Scanning and Indexing IDRiD Dataset...\n');
imds = imageDatastore(datasetDir, ...
    'IncludeSubfolders', true, ...
    'LabelSource', 'foldernames');

tbl = countEachLabel(imds);
disp(tbl);

% Compute inverse-frequency class weights to balance minority classes
totalImgs = sum(tbl.Count);
numClasses = height(tbl);
classWeights = totalImgs ./ (numClasses * double(tbl.Count));
classWeights = classWeights / mean(classWeights); % Normalize to mean=1.0

fprintf('  > Balanced Clinical Class Weights (Tackling Minority Imbalance):\n');
for i = 1:numClasses
    fprintf('      Grade %s: Count = %3d | Weight = %.2fx\n', ...
        string(tbl.Label(i)), tbl.Count(i), classWeights(i));
end

% Stratified 80% Train / 20% Validation split
[imdsTrain, imdsVal] = splitEachLabel(imds, 0.8, 'randomized');
fprintf('\n  > Training partition  : %d images\n', numel(imdsTrain.Files));
fprintf('  > Validation partition: %d images\n', numel(imdsVal.Files));

% -------------------------------------------------------------------------
% 4. BUILD NETWORK ARCHITECTURE (ResNet-50 or Native Deep Retinal CNN)
% -------------------------------------------------------------------------
fprintf('\n[3/5] Initializing Deep Learning Network...\n');
inputSize = [224, 224, 3];
useResNet = false;

try
    netPre = resnet50;
    useResNet = true;
    fprintf('  > Loaded Pre-trained ResNet-50 successfully!\n');
catch
    fprintf('  > [INFO] ResNet-50 add-on not downloaded.\n');
    fprintf('  > Auto-switching to Native 5-Stage Deep Retinal CNN (Zero downloads required!).\n');
end

if useResNet
    lgraph = layerGraph(netPre);
    newFcLayer = fullyConnectedLayer(numClasses, ...
        'Name', 'new_fc_dr', ...
        'WeightLearnRateFactor', 10, ...
        'BiasLearnRateFactor', 10);
    newSoftmax = softmaxLayer('Name', 'new_softmax');
    newClassOut = classificationLayer('Name', 'new_classoutput', ...
        'Classes', tbl.Label, ...
        'ClassWeights', classWeights);

    lgraph = replaceLayer(lgraph, 'fc1000', newFcLayer);
    lgraph = replaceLayer(lgraph, 'fc1000_softmax', newSoftmax);
    lgraph = replaceLayer(lgraph, 'ClassificationLayer_fc1000', newClassOut);
else
    % Native 5-Stage Deep Retinal CNN
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
        reluLayer('Name', 'activation_49_relu') % Matches Grad-CAM layer name!
        maxPooling2dLayer(2, 'Stride', 2, 'Name', 'pool4')
        
        fullyConnectedLayer(128, 'Name', 'fc1')
        reluLayer('Name', 'relu_fc')
        dropoutLayer(0.4, 'Name', 'drop1')
        
        fullyConnectedLayer(numClasses, 'Name', 'new_fc_dr')
        softmaxLayer('Name', 'new_softmax')
        classificationLayer('Name', 'new_classoutput', ...
            'Classes', tbl.Label, ...
            'ClassWeights', classWeights)
    ];
    lgraph = layerGraph(layers);
    fprintf('  > Native Deep Retinal CNN assembled with %d layers.\n', numel(layers));
end

% Retinal-specific data augmentation (random flips, rotations, scaling)
augmenter = imageDataAugmenter( ...
    'RandXReflection', true, ...
    'RandYReflection', true, ...
    'RandRotation', [-180, 180], ...
    'RandScale', [0.85, 1.15]);

augTrain = augmentedImageDatastore(inputSize(1:2), imdsTrain, ...
    'DataAugmentation', augmenter, ...
    'ColorPreprocessing', 'gray2rgb');

augVal = augmentedImageDatastore(inputSize(1:2), imdsVal, ...
    'ColorPreprocessing', 'gray2rgb');

% -------------------------------------------------------------------------
% 5. CONFIGURE TRAINING OPTIONS
% -------------------------------------------------------------------------
fprintf('\n[4/5] Configuring Training Hyperparameters...\n');

miniBatchSize = 16;
maxEpochs = 8;
initLearnRate = 3e-4;

options = trainingOptions('adam', ...
    'ExecutionEnvironment', executionEnv, ...
    'InitialLearnRate', initLearnRate, ...
    'MiniBatchSize', miniBatchSize, ...
    'MaxEpochs', maxEpochs, ...
    'Shuffle', 'every-epoch', ...
    'ValidationData', augVal, ...
    'ValidationFrequency', 15, ...
    'Plots', 'training-progress', ...
    'Verbose', true, ...
    'L2Regularization', 1e-4);

% -------------------------------------------------------------------------
% 6. TRAIN THE NETWORK
% -------------------------------------------------------------------------
fprintf('\n[5/5] Training in Progress... Watch the live training curve!\n');
tStart = tic;
[trainedNet, trainInfo] = trainNetwork(augTrain, lgraph, options);
tElapsed = toc(tStart);

fprintf('\n>>> Training completed in %.1f minutes! <<<\n', tElapsed / 60);

% -------------------------------------------------------------------------
% 7. SAVE WEIGHTS FOR TOMORROW'S PRESENTATION
% -------------------------------------------------------------------------
outputModelPath = fullfile('src', 'module3_classification', 'trained_dr_resnet50.mat');
save(outputModelPath, 'trainedNet', 'trainInfo', 'inputSize');
fprintf('  > Trained model saved successfully to: %s\n', outputModelPath);
fprintf('  > Tomorrow, main_demo and dr_screening_dashboard will automatically\n');
fprintf('    load and use this trained model for instant inference in front of judges!\n\n');
