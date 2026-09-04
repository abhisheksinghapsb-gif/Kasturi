function modelName = build_telemed_simulink(outputModelPath)
% BUILD_TELEMED_SIMULINK Programmatically generates and configures the
% Simulink model 'telemed_screening.slx' for rural telemedicine queue analysis.
%
% Architecture Modeled:
% 1. Patient Arrival Source: District load = 100,000 patients/year across 20 PHCs
%    (~400 patients/working day = 50 patients/hour during 8h shifts).
% 2. Rural Bandwidth Bottleneck: 5 MB fundus image upload delay over 512 kbps link
%    (Delta t = 40 Mbits / 0.512 Mbps = 78.125s per uncompressed transmission).
% 3. AI Edge Inference Engine: 0.5s GPU triage latency at PHC.
% 4. AI Triage Filter: 80% non-referable cases cleared autonomously at PHC.
% 5. Doctor Review Queue: Only 20% referable cases forwarded to 1 ophthalmologist
%    (Capacity: 2 min/case = 30 patients/hour).
%
% Syntax:
%   modelName = build_telemed_simulink()
%   modelName = build_telemed_simulink(outputModelPath)
%
% Outputs:
%   modelName - Name or full path of saved .slx model
%
% SIH Problem Statement 26038 | MathWorks Sponsored Prototype

    if nargin < 1 || isempty(outputModelPath)
        baseDir = fileparts(mfilename('fullpath'));
        outputModelPath = fullfile(baseDir, 'telemed_screening.slx');
    end

    [modelDir, modelBaseName, ~] = fileparts(outputModelPath);
    if isempty(modelDir)
        modelDir = pwd;
    end
    modelName = modelBaseName;

    fprintf('=== Building Simulink Telemedicine Model: %s ===\n', modelName);

    % Verify if Simulink is installed and licensed
    hasSimulink = (exist('new_system', 'file') == 2) || (exist('new_system', 'builtin') == 5);

    if ~hasSimulink
        fprintf('  [NOTE] Simulink engine not detected in current environment.\n');
        fprintf('         Generating comprehensive mathematical queueing simulation specification.\n');
        save_model_spec(fullfile(modelDir, [modelName, '_spec.mat']));
        return;
    end

    try
        % Close existing instance if already in memory
        if bdIsLoaded(modelName)
            close_system(modelName, 0);
        end

        % Create new blank Simulink model
        new_system(modelName);
        open_system(modelName);

        % Configure solver settings: Variable-step ODE45 or Fixed-step for deterministic queue
        set_param(modelName, 'Solver', 'ode45', 'StopTime', '2000'); % 2000 operating hours (~1 year)

        % -----------------------------------------------------------------
        % Add Blocks for Baseline (Without AI) Pipeline
        % -----------------------------------------------------------------
        % 1. Patient Arrival Rate (50 patients/hour)
        add_block('simulink/Sources/Constant', [modelName, '/District_Arrivals_50_per_hr'], ...
            'Value', '50.0', 'Position', [60, 80, 120, 110]);

        % 2. 100% forwarded to Doctor (Baseline)
        add_block('simulink/Math Operations/Gain', [modelName, '/Baseline_Forward_Ratio'], ...
            'Gain', '1.0', 'Position', [180, 80, 230, 110]);

        % 3. Doctor Capacity (30 patients/hour)
        add_block('simulink/Sources/Constant', [modelName, '/Doctor_Capacity_30_per_hr'], ...
            'Value', '30.0', 'Position', [180, 140, 230, 170]);

        % 4. Net Queue Rate: Arrival - Capacity
        add_block('simulink/Math Operations/Subtract', [modelName, '/Net_Rate_Baseline'], ...
            'Inputs', '+-', 'Position', [280, 85, 310, 145]);

        % 5. Queue Length Integrator (Initial queue = 0, lower bound = 0)
        add_block('simulink/Continuous/Integrator', [modelName, '/Doctor_Backlog_Without_AI'], ...
            'InitialCondition', '0', ...
            'LimitOutput', 'on', 'LowerSaturationLimit', '0', ...
            'Position', [360, 95, 400, 135]);

        % 6. To Workspace for Baseline Queue
        add_block('simulink/Sinks/To Workspace', [modelName, '/Log_Queue_Without_AI'], ...
            'VariableName', 'queue_without_ai', 'SaveFormat', 'Array', ...
            'Position', [450, 100, 520, 130]);

        % Connect Baseline Subsystem
        add_line(modelName, 'District_Arrivals_50_per_hr/1', 'Baseline_Forward_Ratio/1');
        add_line(modelName, 'Baseline_Forward_Ratio/1', 'Net_Rate_Baseline/1');
        add_line(modelName, 'Doctor_Capacity_30_per_hr/1', 'Net_Rate_Baseline/2');
        add_line(modelName, 'Net_Rate_Baseline/1', 'Doctor_Backlog_Without_AI/1');
        add_line(modelName, 'Doctor_Backlog_Without_AI/1', 'Log_Queue_Without_AI/1');

        % -----------------------------------------------------------------
        % Add Blocks for AI-Triaged Pipeline
        % -----------------------------------------------------------------
        % 1. AI Triage Filter: Only 20% Referable cases forwarded (Gain = 0.20)
        add_block('simulink/Math Operations/Gain', [modelName, '/AI_Triage_20pct_Referable'], ...
            'Gain', '0.20', 'Position', [180, 240, 230, 270]);

        % 2. AI Edge Processing Latency (0.5s per patient = 0.00014 hr)
        add_block('simulink/Continuous/Transport Delay', [modelName, '/AI_Edge_Inference_Delay'], ...
            'DelayTime', '0.00014', 'Position', [260, 240, 300, 270]);

        % 3. Net Queue Rate for AI: 10 arrivals/hr - 30 capacity/hr
        add_block('simulink/Math Operations/Subtract', [modelName, '/Net_Rate_AI'], ...
            'Inputs', '+-', 'Position', [340, 245, 370, 305]);

        % 4. Queue Length Integrator with AI (Lower bound = 0)
        add_block('simulink/Continuous/Integrator', [modelName, '/Doctor_Backlog_With_AI'], ...
            'InitialCondition', '0', ...
            'LimitOutput', 'on', 'LowerSaturationLimit', '0', ...
            'Position', [420, 255, 460, 295]);

        % 5. To Workspace for AI Queue
        add_block('simulink/Sinks/To Workspace', [modelName, '/Log_Queue_With_AI'], ...
            'VariableName', 'queue_with_ai', 'SaveFormat', 'Array', ...
            'Position', [510, 260, 580, 290]);

        % Connect AI Subsystem
        add_line(modelName, 'District_Arrivals_50_per_hr/1', 'AI_Triage_20pct_Referable/1');
        add_line(modelName, 'AI_Triage_20pct_Referable/1', 'AI_Edge_Inference_Delay/1');
        add_line(modelName, 'AI_Edge_Inference_Delay/1', 'Net_Rate_AI/1');
        add_line(modelName, 'Doctor_Capacity_30_per_hr/1', 'Net_Rate_AI/2');
        add_line(modelName, 'Net_Rate_AI/1', 'Doctor_Backlog_With_AI/1');
        add_line(modelName, 'Doctor_Backlog_With_AI/1', 'Log_Queue_With_AI/1');

        % Save the constructed model
        save_system(modelName, outputModelPath);
        close_system(modelName);
        fprintf('  [OK] Successfully constructed and saved Simulink model: %s\n', outputModelPath);

    catch ME
        fprintf('  [Simulink Build Warning]: %s\n', ME.message);
        fprintf('  Saving standalone model specification for simulation analysis.\n');
        save_model_spec(fullfile(modelDir, [modelName, '_spec.mat']));
    end
end

function save_model_spec(specPath)
    telemedSpec = struct();
    telemedSpec.districtPatientsPerYear = 100000;
    telemedSpec.numPHCs = 20;
    telemedSpec.workingDaysPerYear = 250;
    telemedSpec.workingHoursPerDay = 8;
    telemedSpec.arrivalRatePerHour = 50.0;     % 100k / (250 * 8) = 50 pt/hr
    telemedSpec.doctorReviewTimeMinutes = 2.0;
    telemedSpec.doctorCapacityPerHour = 30.0;  % 60 / 2.0 = 30 pt/hr
    telemedSpec.ruralLinkBandwidthKbps = 512;
    telemedSpec.imageSizeMB = 5.0;
    telemedSpec.uploadDelayPerImageSec = (5.0 * 8 * 1024) / 512; % 80 seconds
    telemedSpec.aiInferenceSec = 0.5;
    telemedSpec.aiNonReferableClearedPct = 0.80;
    telemedSpec.aiReferableForwardedPct = 0.20;

    save(specPath, 'telemedSpec');
    fprintf('  [OK] Saved telemedicine simulation specification to: %s\n', specPath);
end
