# using Distributed
# addprocs(5)

using Caesar, RoME
using RoMEPlotting, Gadfly, KernelDensityEstimatePlotting, Cairo, Fontconfig
using KernelDensityEstimate
using IncrementalInference
using DocStringExtensions
using DelimitedFiles, JLD
# using TransformUtils

include(joinpath(@__DIR__,"slamUtils.jl"))

function main(savedir::String, windowstart::Int, windowend::Int, gap_in::Int, gps_gap_in::Int)
    ## Default parameters
    println("Start Script\n")
    N = 100
    symbolstart = 1;
    # windowstart = 70; windowend = 170;
    # windowstart = 55; windowend = 350;
    totalposes = windowend-windowstart;
    saswindow = 8;
    sas_gap = saswindow+gap_in;
    sas_gap_counter = 0;
    totalposes = windowend-windowstart;
    tstart = 1_000_000;
    element = 2
    savedirheader = savedir * "/dock_fgap$(gap_in)_gpsgap$(gps_gap_in)";

    poses = Dict{Int,Array}();
    nav = Dict{Int,Array}();
    errorinds = [];
    allsasframes = Dict{Int,Array}();
    saveBF = Dict();

    allframes = collect(windowstart:1:windowend);
    posData = importdata_nav(allframes);
    navchecked, errorind = sanitycheck_nav(posData)

    dposData = deepcopy(posData)
    i=1
    gps_gap = gps_gap_in;
    while i+gps_gap < size(dposData,1)
        cumulativeDrift!(@view(dposData[i:i+gps_gap-1,:]),[0.0;0],[0.2,0.2])
         i+=gps_gap
        if i+gps_gap > size(dposData,1)
            cumulativeDrift!(@view(dposData[i-gps_gap:end,:]),[0.0;0],[0.2,0.2])
        end
    end

    posPl = Gadfly.plot(layer(x=posData[:,1],y=posData[:,2], Geom.path, Theme(default_color=colorant"green")), layer(x=dposData[:,1],y=dposData[:,2],Geom.path)); posPl |> PDF(savedirheader*"_posPL.pdf")

    dataDir = joinpath("/media","data1","data","kayaks","20_gps_pos")
    chirpFile = joinpath("/media","data1","data","kayaks","chirp250.txt");
    cfgFile = joinpath("/media","data1","data","kayaks","SAS2D.yaml")
    cfgd=loadConfigFile(cfgFile)

    fg = initfg();
    beacon = :l1
    addVariable!(fg, beacon, Point2 )
    tree=emptyBayesTree();

    pose_counter = 1
    sas_counter = 1

    while pose_counter < totalposes
        current_symbol = Symbol("x$pose_counter")
        addVariable!(fg, current_symbol, DynPoint2(ut=tstart))
        println("Adding Variable x$pose_counter")
        sas_gap_counter += 1
        tstart += 1_000_000

        #Interpolate velocity from GPS ground truth every gps_gap poses
       if pose_counter == 1 || mod(pose_counter,gps_gap) == 0
           xdotp = posData[pose_counter+1,1] - posData[pose_counter,1];
           ydotp = posData[pose_counter+1,2] - posData[pose_counter,2];
            dpμ = [posData[pose_counter,1];posData[pose_counter,2];xdotp;ydotp];
            dpσ = Matrix(Diagonal([0.1;0.1;0.2;0.2].^2))

            pp = DynPoint2VelocityPrior(MvNormal(dpμ,dpσ))
            addFactor!(fg, [current_symbol;], pp, autoinit=false)
            # manualinit!(fg,current_symbol,kde!(rand(MvNormal(dpμ,dpσ),100)))
       end

       #odo factors
       if pose_counter > 1
           xdotp = dposData[pose_counter-1,1] - dposData[pose_counter,1];
           ydotp = dposData[pose_counter-1,2] - dposData[pose_counter,2];
           dpμ = [xdotp;ydotp;0;0];
           dpσ = Matrix(Diagonal([0.2;0.2;0.2;0.2].^2))
           vp = VelPoint2VelPoint2(MvNormal(dpμ,dpσ))
           addFactor!(fg, [Symbol("x$(pose_counter-1)");current_symbol], vp, autoinit=false)
           # manualinit!(fg,current_symbol,kde!(rand(MvNormal(dpμ,dpσ),100)))
       end

       if sas_gap_counter >= sas_gap
           println("Trying to add SAS at pose:$pose_counter")
           navframes = collect(pose_counter-saswindow+1:1:pose_counter)
           navtemp = posData[navframes,:];
           navchecked, errorind = sanitycheck_nav(navtemp);
           push!(errorinds,errorind);

           if navchecked
               poses[sas_counter] = [Symbol("x$i") for i in pose_counter-saswindow+1:pose_counter]
               currentstart = windowstart+pose_counter-saswindow
               println("Adding SAS at pose:$currentstart")
               sasframes = collect(currentstart:1:currentstart+saswindow-1);
               allsasframes[sas_counter] = sasframes;
               waveformData = importdata_waveforms(sasframes,element);
               sas2d = prepareSAS2DFactor(saswindow, waveformData, rangemodel=:Correlator,cfgd=cfgd, chirpFile=chirpFile)
               addFactor!(fg, [beacon;poses[sas_counter]], sas2d, autoinit=false)

               getSolverParams(fg).drawtree = true
               getSolverParams(fg).showtree = false

               if sas_counter > 1
                   tree, smt, hist = solveTree!(fg,tree)
               else
                   tree, smt, hist = solveTree!(fg)
               end

               plk= [];

             for i in pose_counter-saswindow+1:pose_counter
                   X1 = getKDEMean(getVertKDE(fg,Symbol("x$i")))
                   push!(plk, layer(x=[X1[1];],y=[X1[2];], Geom.point), Theme(default_color=colorant"red",point_size = 1.5pt,highlight_width = 0pt))
              end

              for i in 1:pose_counter
                    X1 = getKDEMean(getVertKDE(fg,Symbol("x$i")))
                    push!(plk, layer(x=[X1[1];],y=[X1[2];], Geom.point), Theme(point_size = 1.5pt,highlight_width = 0pt))
               end

               push!(plk,layer(x=posData[:,1],y=posData[:,2], Geom.path, Theme(default_color=colorant"green")))

               igt = [17.0499;1.7832];
               push!(plk,layer(x=[igt[1];],y=[igt[2];], label=String["Beacon";],Geom.point,Geom.label(hide_overlaps=false), order=2, Theme(default_color=colorant"red")));

               L1 = getVal(getVariable(fg, beacon))
               K1 = plotKDEContour(getVertKDE(fg,:l1),xlbl="X (m)", ylbl="Y (m)",levels=5,layers=true);
               push!(plk,K1...)
               push!(plk,Gadfly.Theme(key_position = :none));
               push!(plk, Coord.cartesian(xmin=-40, xmax=140, ymin=-150, ymax=75,fixed=true))

               plkplot = Gadfly.plot(plk...); plkplot |> PDF(savedirheader*"_sasframe$sas_counter.pdf");
               # plkplot |> SVG("sasframe$sas_counter.svg")

               l1fit = getKDEMean(getVertKDE(fg,:l1))
               meanerror = sqrt((igt[1]-l1fit[1])^2+(igt[2]-l1fit[2])^2)

               l1max = getKDEMax(getVertKDE(fg,:l1))
               maxerror = sqrt((igt[1]-l1max[1])^2+(igt[2]-l1max[2])^2)

               mykde = getVertKDE(fg,:l1)
               mynorm = kde!(rand(fit(MvNormal,L1),200))
               kld = min(abs(KernelDensityEstimate.kld(mynorm,mykde)),abs(KernelDensityEstimate.kld(mykde,mynorm)))

               jldname2 = savedirheader * "_solve_$(sas_counter).jld"
               JLD.save(jldname2,"beacon",L1,"posData",posData,"dposData", dposData,"gps_gap", gps_gap, "poses",poses,"sasframes", allsasframes, "l1fit",l1fit, "meanerror",meanerror,"l1max",l1max,"maxerror",maxerror,"kld",kld)

               sas_counter +=1
               sas_gap_counter = 0
           end
       end
       pose_counter+=1
   end
end
