using Revise
using JSON, ZMQ
using Base.Test
using Caesar
using Distributions, RoME, IncrementalInference
using Unmarshal

addOdo2DJson = "{\n  \"covariance\": [\n    [\n      0.1,\n      0.0,\n      0.1\n    ],\n    [\n      0.1,\n      0.0,\n      0.1\n    ],\n    [\n      0.1,\n      0.0,\n      0.1\n    ]\n  ],\n  \"measurement\": [\n    10.0,\n    0.0,\n    1.0471975511965976\n  ],\n  \"robot_id\": \"Hexagonal\",\n  \"session_id\": \"cjz002\",\n  \"type\": \"addOdometry2D\"\n}";
addLandmark2DJson = "{\n  \"landmark_id\": \"l1\",\n  \"robot_id\": \"Hexagonal\",\n  \"session_id\": \"cjz002\",\n  \"type\": \"addLandmark2D\"\n}";
addOdo2DCmd = JSON.parse(addOdo2DJson)
addLandmark2DCmd = JSON.parse(addLandmark2DJson)

fg = Caesar.initfg()
config = Dict{String, String}()

# Send a command locally.
function sendCmd(config, fg, cmd::Dict{String, Any})::String
    callback = getfield(Caesar, Symbol(cmd["type"]))
    resp = callback(config, fg, cmd)
    return JSON.json(resp)
end

# Add an initial variable.
addVariableCmd = Dict{String, Any}("type" => "addVariable", "variable" => JSON.parse(JSON.json(VariableRequest("x0", "Pose2", 100, ["TEST"]))))
@test sendCmd(config, fg, addVariableCmd) == "{\"status\":\"OK\",\"id\":\"x0\"}"

# ls to see that it is added to the graph.
lsCmd = Dict{String, Any}("type" => "ls", "filter" => JSON.parse(JSON.json(lsRequest("true", "true"))))
@test sendCmd(config, fg, lsCmd) == "{\"variables\":[{\"factors\":[],\"id\":\"x0\"}]}"

# Add a prior factor
dist = Dict{String, Any}("distType" => "MvNormal", "mean" => Array{Float64}(3), "cov" => [1.0,0,0,0,1.0,0,0,0,1.0])
priorFactCmd = Dict{String, Any}("type" => "addFactor", "factor" => JSON.parse(JSON.json(FactorRequest("Prior", ["x0"], [dist]))))
@test sendCmd(config, fg, priorFactCmd) == "{\"status\":\"OK\",\"id\":\"x0f1\"}"

@test sendCmd(config, fg, lsCmd) == "{\"variables\":[{\"factors\":[\"x0f1\"],\"id\":\"x0\"}]}"

# Now let's add all 6 hexagonal nodes
odo = Dict{String, Any}(
    "distType" => "MvNormal",
    "mean" => [10.0,0,pi/3.0],
    "cov" => [0.1,0,0,0,0.1,0,0,0,0.1])
for i in 1:6
    # Add variable
    addVariableCmd = Dict{String, Any}("type" => "addVariable", "variable" => JSON.parse(JSON.json(VariableRequest("x$i", "Pose2", 100, ["TEST"]))))
    @test sendCmd(config, fg, addVariableCmd) == "{\"status\":\"OK\",\"id\":\"x$i\"}"

    # Now adding odo factor
    @show odoFactCmd = Dict{String, Any}("type" => "addFactor", "factor" => JSON.parse(JSON.json(FactorRequest("Pose2Pose2", ["x$(i-1)", "x$i"], [odo]))))
    @test sendCmd(config, fg, odoFactCmd) == "{\"status\":\"OK\",\"id\":\"x$(i-1)x$(i)f1\"}"
end

@test sendCmd(config, fg, lsCmd) == "{\"variables\":[{\"factors\":[\"x0f1\",\"x0x1f1\"],\"id\":\"x0\"},{\"factors\":[\"x0x1f1\",\"x1x2f1\"],\"id\":\"x1\"},{\"factors\":[\"x1x2f1\",\"x2x3f1\"],\"id\":\"x2\"},{\"factors\":[\"x2x3f1\",\"x3x4f1\"],\"id\":\"x3\"},{\"factors\":[\"x3x4f1\",\"x4x5f1\"],\"id\":\"x4\"},{\"factors\":[\"x4x5f1\",\"x5x6f1\"],\"id\":\"x5\"},{\"factors\":[\"x5x6f1\"],\"id\":\"x6\"}]}"

# Set all variables ready
setReadyCmd = Dict{String, Any}("type" => "setReady", "params" => JSON.parse(JSON.json(SetReadyRequest(nothing, 1))))
@test sendCmd(config, fg, setReadyCmd) == "{\"status\":\"OK\"}"

# Call batch solve
batchSolveCmd = Dict{String, Any}("type" => "batchSolve")
result = sendCmd(config, fg, batchSolveCmd)
@test JSON.parse(result)["status"] == "OK"

# Just for fun
getNodeCmd = Dict{String, Any}("type" => "getNode", "id" => "x0")
x0Ret = JSON.parse(sendCmd(config, fg, getNodeCmd))

#######
### STATE OF THE ART. BEYOND HERE THERE BE KRAKENS (AND EXCEPTIONS, YAAARGH!)
#######

# Get a node to make sure it's all good.
# getNodeCmd = Dict{String, Any}("type" => "ls", "id" => "x0")
