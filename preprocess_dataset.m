% PREPROCESS_DATASET Standardize all raw IDRiD images to 512x512
fprintf('Standardizing all dataset images to 512x512...\n');

dirs = {
    fullfile(pwd, 'data', 'training_dataset'), ...
    fullfile(pwd, 'data', 'testing_dataset'), ...
    fullfile(pwd, 'data', 'test_samples')
};

totalResized = 0;
for dIdx = 1:numel(dirs)
    targetDir = dirs{dIdx};
    if ~exist(targetDir, 'dir'), continue; end
    
    imgFiles = dir(fullfile(targetDir, '**', '*.jpg'));
    imgFiles = [imgFiles; dir(fullfile(targetDir, '**', '*.png'))];
    
    for i = 1:numel(imgFiles)
        fpath = fullfile(imgFiles(i).folder, imgFiles(i).name);
        info = imfinfo(fpath);
        if info.Height > 600 || info.Width > 600
            img = imread(fpath);
            imgResized = imresize(img, [512, 512]);
            imwrite(imgResized, fpath, 'Quality', 95);
            totalResized = totalResized + 1;
        end
    end
end

fprintf('Completed! Resized %d images to 512x512.\n', totalResized);
exit;
