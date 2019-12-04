# AUV msg slam client model

using Distributed
addprocs(4)

using DistributedFactorGraphs
using Caesar, RoME
@everywhere using Caesar, RoME
using LCMCore, BotCoreLCMTypes
using Dates
using DataStructures

# mute LCM broadcasting beyond this computer
run(`$(ENV["HOME"])/mutelcm.sh`)


# Precompile large swath of the solver functions
warmUpSolverJIT()
warmUpSolverJIT() # twice to ensure larger footprint for multiprocess



# bring required utilities and handlers into context
include(joinpath(@__DIR__, "MsgHandlers.jl"))
include(joinpath(@__DIR__, "SandsharkUtils.jl"))
include(joinpath(@__DIR__, "Plotting.jl"))


function main(;lcm=LCM(), logSpeed::Float64=1.0)

  # data containers
  dashboard = Dict{Symbol,Any}()
  lblDict = Dict{DateTime,Vector{Float64}}()
  magDict = Dict{DateTime,Float64}()

  # fg object and initialization
  fg = initfg()
  initializeAUV_noprior(fg, dashboard)

  # prepare the solver in the background
  manageSolveTree!(fg, dashboard, dbg=true)

  # middleware handlers
  # start with LBL and magnetometer
  subscribe(lcm, "AUV_LBL_INTERPOLATED", (c,d)->lbl_hdlr(c,d,dashboard,lblDict), pose_t)
  subscribe(lcm, "AUV_MAGNETOMETER",     (c,d)->mag_hdlr(c,d,dashboard,magDict), pose_t)

  @info "get a starting position and mag orientation"
  while length(lblDict) == 0 || length(magDict) == 0
    handle(lcm)
  end
  lblKeys = keys(lblDict) |> collect |> sort
  magKeys = keys(magDict) |> collect |> sort
  initPose = [lblDict[lblKeys[1]];magDict[magKeys[1]]]
  dashboard[:odoTime] = lblKeys[1]
  @show startT = lblKeys[1]

  setTimestamp!(getVariable(fg, :x0), lblKeys[1])

  # add starting prior
  addFactor!(fg, [:x0;], PriorPose2(MvNormal(initPose,Matrix(Diagonal([0.1; 0.1; 0.1].^2)))), autoinit=false)

  @info "Start with the real-time tracking aspect..."
  subscribe(lcm, "AUV_ODOMETRY",         (c,d)->pose_hdlr(c,d,fg,dashboard), pose_t)
  # subscribe(lcm, "AUV_ODOMETRY_GYROBIAS", (c,d)->pose_hdlr(c,d,fg,dashboard), pose_t)
  subscribe(lcm, "AUV_RANGE_CORRL",      (c,d)->range_hdlr(c,d,fg,dashboard), raw_t)
  # subscribe(lcm, "AUV_BEARING_CORRL",callback, raw_t)

  # run handler
  holdTimeRTS = now()
  offsetT = now() - startT
  dashboard[:doDelay] = lcm isa LCMLog
  for i in 1:5000
      handle(lcm)
      # slow down in case of using an LCMLog object
      if dashboard[:doDelay]
        # might be delaying the solver -- ie real time slack grows above zero
        holdTimeRTS = now()
        while dashboard[:canTakePoses] == 0
          @info "delay for solver to catch up with new poses, dashboard[:realTimeSlack]=$(dashboard[:realTimeSlack])"
          sleep(0.5)
        end
        # real time slack update -- this is the compute overrun
        dashboard[:realTimeSlack] += now()-holdTimeRTS

        dt = (dashboard[:lastMsgTime]-startT)
        # TODO add real-time-slack time
        nMsgT = startT + typeof(dt)(round(Int, dt.value/logSpeed)) + dashboard[:realTimeSlack]
        # @show now() < (nMsgT + offsetT), now(), (nMsgT + offsetT)
        while now() < (nMsgT + offsetT)
          # @info "delay"
          sleep(0.01)
        end
      end
  end
  # close UDP listening on LCM
  close(lcm)

  # close out solver
  dashboard[:loopSolver] = false

  # return last factor graph as built and solved
  return fg, dashboard
end



## Do the actual run -- on traffic
# fg = main()

## from file

# fg, dashboard = main(logSpeed=0.25, lcm=LCMLog(joinpath(ENV["HOME"],"data","sandshark","lcmlog","lcmlog-2019-11-26.01")) )
fg, dashboard = main(logSpeed=0.25, lcm=LCMLog(joinpath(ENV["HOME"],"data","sandshark","lcmlog","lcm-sandshark-med.log")) )
# fg, dashboard = main(logSpeed=0.25, lcm=LCMLog(joinpath(ENV["HOME"],"data","sandshark","lcmlog","sandshark-long.lcmlog")) )



##


drawGraph(fg)


# pla = drawPosesLandmarksAndOdo(fg, ppbrDict, navkeys, X, Y, lblkeys, lblX, lblY)

plb = plotSandsharkFromDFG(fg)



map(x->setSolvable!(fg, x, 1), setdiff(ls(fg), ls(fg, r"drt_\d")))

map(x->setSolvable!(fg, x, 1 ), [lsf(fg, Pose2Pose2);
lsf(fg, Pose2Point2Range);
lsfPriors(fg)])

getLogPath(fg)

ensureAllInitialized!(fg)

getSolverParams(fg).async = true
tree, smt, hist = solveTree!(fg)


reportFactors(fg, Pose2Point2Range)

0

## whats the deal with ranges

d1 = dashboard[:rangesBuffer][1][2]

Gadfly.plot(x=d1[:,1], y=d1[:,2], Geom.line)
Gadfly.plot(y=d1[:,1], Geom.line)
Gadfly.plot(y=d1[:,2], Geom.line)


Gadfly.plot(x=d1[:][1:2:end], Geom.histogram)
Gadfly.plot(x=d1[:][2:2:end], Geom.histogram)


## test data transcription to log

msgdata = dashboard[:lastRangeMsg]

msgdata.utime*1000

ppbrDict[ep].range.domain


reinterpret(Float64, msgdata.data)

rda = reshape(, :, 2)


# mock recode

rmsg = raw_t()

epT = ep
rdata = zeros(length(ppbrDict[epT].range.domain),2)
rdata[:,1] = ppbrDict[epT].range.domain
rdata[:,2] = ppbrDict[epT].range.weights.values
rmsg.data = reinterpret(UInt8, vec(reshape(rdata,:,1))) |> collect
rmsg.length = length(rmsg.data)
bytes = encode(rmsg)



## Temporary development code below


# # get sorted pose timestamps
# posesym = ls(fg, r"x\d") |> sortDFG
# # get sorted factor timestamps
# sortF = union( (x->ls(fg,x)).(posesym)... )
# fctsym = intersect(sortF, lsf(fg, Pose2Point2Range))
#
# vartim = posesym .|> x->(timestamp(getVariable(fg, x)),x)
# rantim = fctsym .|> x->(timestamp(getFactor(fg,x)),x)
#
#
# findClosestTimestamp(vartim, rantim)
#
#
#
# ## compare variable factor timestamp descrepencies
#
# ppr = ls(fg, Pose2Point2Range)
#
# vs_fsA = map(x->(x,intersect(ls(fg, x),ppr)...), posesym)
# mask = length.(vs_fsA) .== 2
#
# vs_fs = vs_fsA[mask]
#
# map(x->timestamp(getVariable(fg, x[1]))-timestamp(getFactor(fg, x[2])), vs_fs)
#
#
#
#
# # variables and ranges
# lastvars = getLastPoses(fg, filterLabel=r"x\d", number=dashboard[:RANGESTRIDE]+5) |> sortDFG
# rantim = dashboard[:rangesBuffer] |> y->map(x->(x[1], x[3][1]),y)
# vartim = map(x->(timestamp(getVariable(fg, x)), x), lastvars)
#
# findClosestTimestamp(vartim, rantim)



# dashboard[:rangeClkOffset]


## Debugging code below




# drawGraph(fg)
# getSolverParams(fg).dbg = true
# tree, smt, hist = solveTree!(fg, recordcliqs=ls(fg))


#
# using RoMEPlotting
# # drawPoses(fg)
#
# plotPose(fg, :x0)

#
