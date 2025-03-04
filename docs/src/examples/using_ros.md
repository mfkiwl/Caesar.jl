# [ROS Direct](@id ros_direct)

Since 2020, Caesar.jl has native support for ROS via the [RobotOS.jl](https://github.com/jdlangs/RobotOS.jl) package.  

## Load the ROS Environment Variables

The first thing to ensure is that the ROS environment variables are loaded before launching Julia, see ["1.5 Environment setup at ros.org"](https://wiki.ros.org/noetic/Installation/Ubuntu), something similar to:
```
source /opt/ros/noetic/setup.bash
```

### Setup a Catkin Workspace

Assuming you have bespoke msg types, we suggest using a catkin workspace of choice, for example:
```bash
mkdir -p ~/caesar_ws/src
cd ~/caesar_ws/src
git clone https://github.com/pvazteixeira/caesar_ros
```

Now build and configure your workspace

```bash
cd ~/caesar_ws
catkin_make
source devel/setup.sh
```

This last command is important, as you must have the workspace configuration in your environment when you run the julia process, so that you can import the service specifications.

## RobotOS.jl with Correct Python

RobotOS.jl currently uses [PyCall.jl](https://github.com/JuliaPy/PyCall.jl) to interface through the `rospy` system.  After launching Julia, make sure that PyCall is using the correct Python binary on your local system.
```julia
# Assuming multiprocess will be used.
using Distributed
# addprocs(4)

# Prepare python version
using Pkg
Distributed.@everywhere using Pkg

Distributed.@everywhere begin
  ENV["PYTHON"] = "/usr/bin/python3"
  Pkg.build("PyCall")
end

using PyCall
Distributed.@everywhere using PyCall
```

## Load RobotOS.jl along with Caesar.jl

Caesar.jl has native by optional package tools relating to RobotOS.jl (leveraging [Requires.jl](https://github.com/JuliaPackaging/Requires.jl)):
```julia
using RobotOS

@rosimport sensor_msgs.msg: PointCloud2

rostypegen()

using Colors, Caesar
Distributed.@everywhere using Colors, Caesar
```

Colors.jl is added as a conditional requirement to get `Caesar._PCL.PointCloud` support ([see PCL page here](@ref pointclouds_and_pcl)).

!!! note
    Imports and type generation are necessary for RobotOS and Caesar to work properly.

## Prepare Any Outer Objects

Usually a factor graph or detectors, or some more common objects are required.  For the example lets just say a basic SLAMWrapper containing a regular `fg=initfg()`:
```julia
robotslam = SLAMWrapperLocal()
```

### Example Caesar.jl ROS Handler

Some function will also be required to consume the ROS traffic on any particular topic, where for the example we assume extraneous data will only be `fg_`:
```julia
function myHandler(msgdata, slam_::SLAMWrapperLocal)
  # show some header information
  @show "myHandler", msgdata[2].header.seq

  # do stuff
  # addVariable!(slam.dfg, ...)
  # addFactor!(slam.dfg, ...)
  #, etc.

  nothing
end
```

## Read or Write Bagfile Messages 

Assuming that you are working from a bagfile, the following code makes it easy to consume the bagfile directly.  Alternatively, see [RobotOS.jl](https://github.com/jdlangs/RobotOS.jl) for wiring up publishers and subscribers for live data.  Caesar.jl methods to consuming a bagfile are:
```julia
# find the bagfile
bagfile = joinpath(ENV["HOME"],"data/somedata.bag")

# open the file
bagSubscriber = RosbagSubscriber(bagfile)

# subscriber callbacks
bagSubscriber("/zed/left/image_rect_color", myHandler, robotslam)
```

### Run the ROS Loop

Once everything is set up as you need, it's easy to loop over all the traffic in the bagfile (one message at a time):
```julia
maxloops = 1000
rosloops = 0
while loop!(bagSubscriber)
  # plumbing to limit the number of messages
  rosloops += 1
  if maxloops < rosloops
    @warn "reached --msgloops limit of $rosloops"
    break
  end
  # delay progress for whatever reason
  blockProgress(robotslam) # required to prevent duplicate solves occuring at the same time
end
```

!!! note
    See page on [Synchronizing over the Graph](@ref sync_over_graph_solvable)

### Write Msgs to a Bag

Support is also provided for writing messages to bag files with `Caesar.RosbagWriter`:

```julia
# Link with ROSbag infrastructure via rospy
using Pkg
ENV["PYTHON"] = "/usr/bin/python3"
Pkg.build("PyCall")
using PyCall
using RobotOS
@rosimport std_msgs.msg: String
rostypegen()
using Caesar

bagwr = Caesar.RosbagWriter("/tmp/test.bag")
s = std_msgs.msg.StringMsg("test")
bagwr.write_message("/ch1", s)
bagwr.close()
```

This has been tested and use with much more complicated types such as the [`Caesar._PCL.PCLPointCloud2`](@ref).

## Additional Notes

### More Tools for Real-Time

See tools such as 
```julia
ST = manageSolveTree!(robotslam.dfg, robotslam.solveSettings, dbg=false)
```

```@docs
manageSolveTree!
```

for solving a factor graph while the middleware processes are modifying the graph, while documentation is being completed see the code here:
https://github.com/JuliaRobotics/RoME.jl/blob/a662d45e22ae4db2b6ee20410b00b75361294545/src/Slam.jl#L175-L288

To stop or trigger a new solve in the SLAM manager you can just use either of these
```@docs
stopManageSolveTree!
triggerSolve!
```

!!! note
    Native code for consuming rosbags also includes methods:
    ```julia
    RosbagSubscriber, loop!, getROSPyMsgTimestamp, nanosecond2datetime
    ```

!!! note
    Additional notes about tricks that came up during development [is kept in this wiki](https://github.com/JuliaRobotics/Caesar.jl/wiki/ROS-PoC).

!!! note
    See ongoing RobotOS.jl discussion on building a direct C++ interface and skipping PyCall.jl entirely: https://github.com/jdlangs/RobotOS.jl/issues/59
