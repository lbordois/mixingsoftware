%~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
%
% Process_CTD_hex_Template.m
%
% Script to process raw (.hex) shipboard (Seabird) CTD data. Part of
% ctd_processing folder in OSU mixing software github repo. Originally
% designed to make data needed for CTD-chipod proccesing, but also useful
% for regular CTD processing.
%
% OUTPUT:
% - Processed 24Hz data mat files. These are used in
% the CTD-chipod processing to align the accelerations up in time.
% - Procesed and binned (1m) data. The chipod processing uses N^2
% and dT/dz computed from these.
% - Summary figures.
%
% Instructions:
% - Copy this file to a new script and save as Process_CTD_hex_[cruise
% name]
% - Modify the data directory and output paths
% - Run script!
%
% Modified from original script from Jen MacKinnon @ Scripps. Modified by A. Pickering
%
%---------------------
% 04/21/15 - A. Pickering - apickering@coas.oregonstate.edu
%~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
%%

clear ; close all

BaseDir='/Users/Andy/Cruises_Research/mixingsoftware/ctd_processing'

addpath /Users/Andy/Cruises_Research/mixingsoftware/ctd_processing/

% *** For recording filename used to process data
this_file_name='Process_CTD_hex_Template.m'

% ~ *** identifying string in filename of CTD files ***
% example: CTD file 'TS-cast002.hex', CastString='TS'
CastString='TS'

% *** Paths to raw and processed data (all assuming we are in /ctd_processing/ ***

% Folder with raw CTD data (.hex and .XMLCON files)
CTD_data_dir=fullfile(BaseDir,'TestData','raw')

% Base directory for all output
CTD_out_dir_root=fullfile(BaseDir,'TestData')

% Folder to save processed 24Hz CTD mat files to
CTD_out_dir_24hz=fullfile(CTD_out_dir_root,'processed','24hz')

% Folder to save processed and binned CTD mat files to
CTD_out_dir_bin=fullfile(CTD_out_dir_root,'processed','binned')

% Folder to save figures to
CTD_out_dir_figs=fullfile(CTD_out_dir_root,'processed','figures')

% % Check if folders exist, and make new if not
% ChkMkDir(CTD_out_dir_figs)
% ChkMkDir(CTD_out_dir_bin)
% ChkMkDir(CTD_out_dir_24hz)

dobin=1;  % bin data

%~~~
% Make list of all ctd files we have
ctdlist = dirs(fullfile(CTD_data_dir, ['*' CastString '*.hex*']))

% Loop through each cast
for icast=1%:length(ctdlist)
    
    close all
    
    clear data1 data2 data3 data4 data5 data6 data7
    clear ctdname outname matname confile cfg d
        
    disp('=============================================================')
        
    % name of file we are working on now
    ctdname = fullfile(CTD_data_dir,ctdlist(icast).name)
    % name for processed matfile
    outname=[sprintf([CastString '_%03d'],icast) '.mat']
    matname=fullfile(CTD_out_dir_bin, outname);
    disp(['CTD file: ' ctdname])
    %~~~
    
    % ~ load calibration info (should be updated for each cruise)
    disp('Loading calibrations')
    
    % *** Load calibration info for CTD sensors
    confile=[ctdname(1:end-3) 'XMLCON']
    cfg=MakeCtdConfigFromXMLCON(confile)
    
    % Load Raw data
    disp(['loading: ' ctdname])
    % include ch4
    d = hex_read(ctdname);
    disp(['parsing: ' ctdname ])
    data1 = hex_parse(d);
    
    % check for modcount errors
    clear dmc mmc fmc
    dmc = diff(data1.modcount);
    mmc = mod(dmc, 256);
    %figure; plot(mmc); title('mod diff modcount')
    fmc = find(mmc - 1);
    if ~isempty(fmc);
        disp(['Warning: ' num2str(length(dmc(mmc > 1))) ' bad modcounts']);
        disp(['Warning: ' num2str(sum(mmc(fmc))) ' missing scans']);
    end
    
    % check for time errors
    clear dt ds np mds
    dt = data1.time(end) - data1.time(1); % total time range of cast (seconds?)
    ds = dt*24; % # expected samples at 24Hz ?
    np = length(data1.p); % # samples
    mds = np - ds;  % difference between expected and actual # samples
    if abs(mds) >= 24; disp(['Warning: ' num2str(mds) ' difference in time scans']); end
    
    % time is discretized
    clear nt time0
    nt=length(data1.time);
    time0=data1.time(1):1/24:data1.time(end);
    
    % convert freq, volatage data
    disp('converting:')
    % *** fl, trans, ch4
    data2 = physicalunits(data1, cfg);
    
    % Plot raw profiles of temp and cond.
    h=PlotRawCTDprofiles(data2,ctdlist,icast)
    print('-dpng',fullfile(CTD_out_dir_figs,[ctdlist(icast).name(1:end-4) '_Raw_Temp_Cond_vsP']))
    %~~~
    
    % add correct time to data
    tlim=now+5*365;
    if data2.time > tlim
        tmp=linspace(data2.time(1),data2.time(end),length(data2.time));
        data2.datenum=tmp'/24/3600+datenum([1970 1 1 0 0 0]);
    end
    
    % output raw data
    disp(['saving: ' matname])
    matname24hz = fullfile(CTD_out_dir_24hz,[outname(1:end - 4) '_24hz.mat'])
    save(matname24hz, 'data2')
    
    % specify the depth range over which t-c lag fitting is done. For deep
    % stations, use data below 500 meters, otherwise use the entire depth
    % range.
    
    if max(data2.p)>800
        data2.tcfit=[500 max(data2.p)];
    else
        data2.tcfit=[200 max(data2.p)];
    end
    
    
    %%
    disp('cleaning:')
    data3 = ctd_cleanup(data2, icast);
    
    %%
    
    disp('correcting:')
    % ***include ch4
    [datad4, datau4] = ctd_correction_updn(data3); % T lag, tau; lowpass T, C, oxygen
    
    disp('calculating:')
    % *** despike oxygen
    datad5 = swcalcs(datad4, cfg); % calc S, theta, sigma, depth
    datau5 = swcalcs(datau4, cfg); % calc S, theta, sigma, depth
    
    %%
    disp('removing loops:')
    % *** Might need to modify based on CTD setup
    wthresh = 0.4   ;
    datad6 = ctd_rmloops(datad5, wthresh, 1);
    datau6 = ctd_rmloops(datau5, wthresh, 0);
    
    %% despike
    
    datad7 = ctd_cleanup2(datad6);
    datau7 = ctd_cleanup2(datau6);
    
    
    %% compute epsilon now, as a test
    doeps=0;
    if doeps
        sigma_t=0.0042; sigma_rho=0.0011;
        
        disp('Calculating epsilon:')
        [Epsout,Lmin,Lot,runlmax,Lttot]=compute_overturns2(datad6.p,datad6.t1,datad6.s1,nanmean(datad6.lat),0,3,sigma_t,1);
        %[epsilon]=ctd_overturns(datad6.p,datad6.t1,datad6.s1,33,5,5e-4);
        datad6.epsilon1=Epsout;
        datad6.Lot=Lot;
    end
    
    
    %% 1-m binning
    
    if dobin
        disp('binning:')
        dz = 1; % m
        zmin = 0; % surface
        [zmax, imax] = max([max(datad7.depth) max(datau7.depth)]);
        zmax = ceil(zmax); % full depth
        datad_1m = ctd_bincast(datad7, zmin, dz, zmax);
        datau_1m = ctd_bincast(datau7, zmin, dz, zmax);
        datad_1m.datenum=datad_1m.time/24/3600+datenum([1970 1 1 0 0 0]);
        datau_1m.datenum=datau_1m.time/24/3600+datenum([1970 1 1 0 0 0]);
        
        
        datad_1m.MakeInfo=['Made ' datestr(now) ' w/ ' this_file_name  ' in Matlab ' version]
        datau_1m.MakeInfo=['Made ' datestr(now) ' w/ ' this_file_name  ' in Matlab ' version]        
        
        datad_1m.source=ctdname;
        datau_1m.source=ctdname;
        
        datad_1m.confile=confile;
        datau_1m.confile=confile;
        
        disp(['saving: ' matname])
        save(matname, 'datad_1m', 'datau_1m')%
        
    end
    
    %% Plot binned profiles
    
    h=PlotBinnedCTDprofiles(datad_1m,datau_1m,ctdlist,icast)
    print('-dpng',fullfile(CTD_out_dir_figs,[ctdlist(icast).name(1:end-4) '_binned_Temp_Sal_vsP']))
    
    
end % cast #
%%
