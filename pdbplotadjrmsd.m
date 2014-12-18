function h = pdbplotadjrmsd(pdbStruct)
%PDBPLOTADJRMSD Plot RMSDs between adjacent models
%   PDBPLOTADJRMSD(pdbStruct) plots RMSDs between adjacent models of
%   PDB structures specified in the cell array pdbStruct.
%
%   See also pdbplotfixedrmsd trmplotadjrmsd trmplotfixedrmsd
%
% PROMPT Toolbox for MATLAB

% By Gaik Tamazian, 2014.
% gaik (dot) tamazian (at) gmail (dot) com

% if a single PDB structure model is specified instead a cell array, then
% create a cell array with a single element from it
if ~iscell(pdbStruct)
    pdbStruct = {pdbStruct};
end

nTrans = length(pdbStruct);
nConf = length(pdbStruct{1}.Model);
rmsdValues = zeros(nTrans, nConf-1);

for i = 1:nTrans
    coords = pdbextractcoords(pdbStruct{i});
    for j = 1:nConf-1
        rmsdValues(i,j) = mean(sqrt(sum((coords{j+1} - coords{j}).^2,2)));
    end
end

h = plot(transpose(rmsdValues),'-o');
xlabel('Configuration Pair');
ylabel('RMSD in AA');

% modify x axis tick labels
ax = gca;
xticks = get(ax,'XTickLabel');
for j = 1:nConf-1
    xticks{j} = [int2str(j),'-',int2str(j+1)];
end
set(ax,'XTickLabel',xticks);

end

