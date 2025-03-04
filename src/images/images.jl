
@info "Loading Caesar tools related to Images.jl."

# using Images
# using ImageTransformations

export writevideo
export imhcatPretty, csmAnimationJoinImgs, csmAnimateSideBySide
export makeVideoFromData


"""
    $SIGNATURES

Use ffmpeg to write image sequence to video file.

Notes:
- Requires Images.jl
- https://discourse.julialang.org/t/creating-a-video-from-a-stack-of-images/646/8
"""
function writevideo(fname::AbstractString, 
                    imgstack::AbstractArray{<:Colorant,3};
                    overwrite=true, fps::Int=30, options=``, 
                    player::AbstractString="",
                    pix_fmt="yuv420p" )
  #
  ow = overwrite ? `-y` : `-n`
  h, w, nframes = size(imgstack)
  open(`ffmpeg
      -loglevel warning
      $ow
      -f rawvideo
      -pix_fmt rgb24
      -s:v $(h)x$(w)
      -r $fps
      -i pipe:0
      $options
      -vf "transpose=0"
      -pix_fmt $pix_fmt
      $fname`, "w") do out
    for i = 1:nframes
      write(out, convert.(RGB{N0f8}, clamp01.(imgstack[:,:,i])))
    end
  end
  if 0 < length(player)
    @async run(`$player $fname`)
  end
end

function writevideo(fname::AbstractString,
                    imgs::AbstractVector{<:AbstractArray{<:Colorant,2}};
                    kwargs... )
  #
  @cast imgstack[r,c,k] := imgs[k][r,c]
  writevideo(fname, imgstack; kwargs...)
end


function imhcatPretty(iml::AbstractMatrix{<:Colorant},
                      imr::AbstractMatrix{<:Colorant} )
  #
  imll = similar(iml)
  fill!(imll, RGB{N0f8}(1,1,1))

  # where to place imr
  heightratio, widthratio = size(imll,1)/size(imr,1), size(imll,2)/size(imr,2)   
  minratio = 0.9*minimum([heightratio, widthratio])
  imrr = Images.imresize(imr, ratio=minratio)
  offsr = round.(Int, 0.05*[size(imll)...])
  endir = [size(imrr)...] + offsr
  imll[offsr[1]:endir[1]-1,offsr[2]:endir[2]-1] .= imrr

  hcat(iml,imll)
end

function csmAnimationJoinImgs(folderpath::AbstractString = "/tmp/caesar/csmCompound/";
                              leftname::AbstractString="csm_",
                              rightname::AbstractString="tree_",
                              bothname::AbstractString="both_",
                              ext::AbstractString="png",
                              files::AbstractVector{<:AbstractString} = readdir(folderpath),
                              nrLt::Int = filter(x->occursin(ext,x),filter(x->occursin(leftname,x), files)) |> length,
                              nrRt::Int = filter(x->occursin(ext,x),filter(x->occursin(rightname,x), files)) |> length  )
  #
  # internal thread helper function
  function threadImageSideBySide(idx)
    iml = load(joinpath(folderpath,"$(leftname)$idx.$ext"))
    imr = load(joinpath(folderpath,"$(rightname)$idx.$ext"))
    imb = imhcatPretty(iml, imr)
    # save new side by side image
    save(joinpath(folderpath,"$(bothname)$idx.$ext"), imb)
  end

  # loop over all image pairs
  allFrames = 1:minimum([nrRt,nrLt])
  THRDS = Vector{Task}(undef, allFrames[end])
  @showprogress "Joining side by side $(allFrames[end]) images" for idx in allFrames
    # threading still only single CPU, ImageMagick might lock library to single file read and write.
    threadImageSideBySide(idx)
  end
  joinpath(folderpath,"$(bothname)$(allFrames[end]).$ext")
end


"""
    $SIGNATURES

Extension of `IIF.csmAnimate` that draws the `solveTree!(...; recordhists=..)` 
Bayes tree development alongside the CSM animation.

Example
-------

```julia
fg = generateGraph_Hexagonal()
tree = solveTree!(fg, recordcliqs=ls(fg))

# now generate all the video frames at default `folderpath=/tmp/caesar/csmCompound/`
csmAnimateSideBySide(tree, hists)

# and render the video using ffmpeg
run(`ffmpeg -r 10 -i /tmp/caesar/csmCompound/both_%d.png -c:v libtheora -vf fps=5 -pix_fmt yuv420p -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -q 10 /tmp/caesar/csmCompound/out.ogv`)
@async run(`totem /tmp/caesar/csmCompound/out.ogv`)
```

DevNotes
- Likely possible to use `writevideo` or something similar.
- `folderpath` not fully populated everywhere so likely not working properly yet (help requested pls)
- `tree` not strictly needed, since `autohists` already has the tree structure stored inside it.
- use `dpi` to set quality and speed.

Related

IIF.csmAnimate, Caesar.writevideo
"""
function csmAnimateSideBySide(tree::AbstractBayesTree,
                              autohists::Dict{Int, T};
                              frames::Int=100,
                              interval::Int=2,
                              dpi::Int=100,
                              rmfirst::Bool=true, 
                              fsmColors::Dict{Symbol,String}=Dict{Symbol,String}(),
                              defaultColor::AbstractString="gray",
                              folderpath::AbstractString="/tmp/caesar/csmCompound/",
                              videopath = joinLogPath(autohists[collect(keys(autohists))[1]][1][4].dfg, "csmAnimate_"*string(Dates.now())),
                              encode::Bool=false,
                              fps::Int=5,
                              nvenc::Bool=false,
                              BITRATE = 2000,
                              show::Bool=false   ) where T <: AbstractVector
  #
  csmAnimate( tree, 
              autohists, 
              interval=interval, 
              frames=frames, 
              dpi=dpi, 
              rmfirst=rmfirst, 
              folderpath=folderpath, 
              fsmColors=fsmColors, 
              defaultColor=defaultColor )
  #
  csmAnimationJoinImgs(folderpath)

  # vid export to videopath
  # firstkey = collect(keys(autohists))[1]

  @info "reruns of `csmAnimate` will by default clear $folderpath and thereby remove any previous work done in that folder (including previously generated videos)."
  if encode
    cmd = if !nvenc
      # known to work properly with resolution and image size
      # `ffmpeg -r 10 -i /tmp/caesar/csmCompound/both_%d.png -c:v libtheora -vf fps=$fps -pix_fmt yuv420p -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -q 10 /tmp/caesar/csmCompound/out.ogv`
      `ffmpeg -r 10 -i $folderpath/both_%d.png -c:v libtheora -vf fps=$fps -pix_fmt yuv420p -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -q 10 $videopath.ogv`
    else
      # something about this particular call order preserves the input image resolution
      # `ffmpeg -r 10 -i /tmp/caesar/csmCompound/both_%d.png -c:v h264_nvenc -preset medium -b:v $(BITRATE)k -bufsize $(BITRATE*2)k -profile:v high -bf 3 -rc-lookahead 20 -vsync 0 -vf fps=$fps -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -pix_fmt yuv420p /tmp/caesar/csmCompound/out.mp4`
      `ffmpeg -r 10 -i $folderpath/both_%d.png -c:v h264_nvenc -preset slow -b:v $(BITRATE)k -bufsize $(BITRATE*2)k -profile:v high -rc vbr_hq -cq 1 -bf 3 -vsync 0 -pix_fmt yuv420p -vf fps=$fps -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" $videopath.mp4`
    end
    run(cmd)
    show && @async run(nvenc ? `totem $videopath.mp4` : `totem $videopath.ogv`)
  end

  @info videopath
  return videopath
end





"""
    $SIGNATURES

Helper function to assemble `Entry=>Data` into a video file.

Example

```julia
# fg object with datastore containing images on subset of variables, e.g. :HEADPOSE

makeVideoFromData("/tmp/test.avi", fg, :LEFT_CAMERA, ls(fg, tags=[:HEADPOSE;]))
```

Related

fetchDataImage
"""
function makeVideoFromData( fname::AbstractString,
                            dfg::AbstractDFG,
                            dataLabel::Symbol,
                            varSym::AbstractVector{Symbol}=ls(dfg, tags=[:POSE;]) |> sortDFG;
                            fps::Int=30,
                            options=`` )
  #
  imgs = fetchDataImage.(dfg, varSym, dataLabel)
  writevideo(fname, imgs, fps=fps, options=options)
end


#