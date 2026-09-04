function varargout = dr_screening_dashboard(varargin)
% DR_SCREENING_DASHBOARD Root Launcher for SIH DR Screening App
% Smart India Hackathon (SIH) Problem Statement 26038 | MathWorks Sponsored Prototype
%
% Usage:
%   dr_screening_dashboard       % Launches interactive dashboard UI
%   fig = dr_screening_dashboard % Returns figure handle

    rootDir = fileparts(mfilename('fullpath'));
    if isempty(rootDir), rootDir = pwd; end
    addpath(genpath(fullfile(rootDir, 'src')));
    addpath(fullfile(rootDir, 'data'));
    addpath(fullfile(rootDir, 'app'));

    fig = dr_screening_gui(varargin{:});
    if nargout > 0
        varargout{1} = fig;
    end
end
