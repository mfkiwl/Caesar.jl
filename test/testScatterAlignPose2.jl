# test ScatterAlignPose2

using Test
using Images
using Caesar
using Distributions
using Manifolds

# test plotting helper functions
using Gadfly
using Random

import Rotations as _Rot

println("Starting ScatterAlignPose2 tests...")

##
@testset "Test ScatterAlignPose2" begin
##

x = -15:0.1:15;
y = -15:0.1:15;

σ = 0.1

Σ = Diagonal([σ;σ])
g = (x,y)->pdf(MvNormal([3.;0],Σ),[x;y]) + pdf(MvNormal([8.;0.0],4*Σ),[x;y]) + pdf(MvNormal([0;5.0],Σ),[x;y])

bIM1 = zeros(length(x),length(y))
bIM2 = zeros(length(x),length(y))

oT = [5.; 0]
oΨ =  pi/8

M = SpecialEuclidean(2)
e0 = getPointIdentity(M)
pCq = [oT;oΨ]
qGp = inv(M, exp(M, e0, hat(M, e0, pCq)))
qTp = affine_matrix(M, qGp )

qCp = vee(M, e0, log(M, e0, qGp))

##

for (i,x_) in enumerate(x), (j,y_) in enumerate(y)
  bIM1[i,j] = g(x_,y_)
  v = qTp*[x_;y_;1.0]
  _x_, _y_ = v[1], v[2]
  bIM2[i,j] = g(_x_, _y_)
end

sap = ScatterAlignPose2(bIM1, bIM2, (x,y); sample_count=100, bw=1.0, cvt=(im)->im)

# requires IIF at least v0.25.6
@test sample(sap.align.cloud1,1) isa Tuple
@test sample(sap.align.cloud2,10)[1] isa AbstractArray

## test plotting function

snt = overlayScatterMutate(sap; sample_count=100, bw=0.001, user_coords=[0.;0;oΨ]);  # , user_offset=[0.;0;0.]);
# Gadfly.set_default_plot_size(35cm,25cm)
plotScatterAlign(snt; title="\npCq=$(round.(pCq,digits=2))")

##

# inverse for q --> p
@test isapprox( pCq[1:2], snt.best_coords[1:2]; atol=1.5 )
@test isapprox( pCq[3], rem2pi(snt.best_coords[3], RoundNearest); atol=0.2 )


## check packing and unpacking

psap = convert(PackedScatterAlignPose2, sap);
sap_ = convert(ScatterAlignPose2, psap);

@test sap.align.gridscale == sap_.align.gridscale
@test sap.align.sample_count == sap_.align.sample_count
@test sap.align.bw == sap_.align.bw

@test isapprox(sap.align.cloud1, sap_.align.cloud1, mmd_tol=1e-2)
@test isapprox(sap.align.cloud2, sap_.align.cloud2, mmd_tol=1e-2)


## check that optimize works (using the same tfg)

tfg = initfg()
getSolverParams(tfg).attemptGradients = false
M = getManifold(sap)
e0 = getPointIdentity(M)
# meas = sample(sap.cloud1,100)[1], [ArrayPartition(sample(sap.cloud2,1)[1][1],[1 0; 0 1.]) for _ in 1:100], M
meas = ArrayPartition(oT, log(M.manifold.manifolds[2], submanifold_component(e0,2), _Rot.RotMatrix(oΨ)))

δ(x) = calcFactorResidualTemporary(sap, (Pose2,Pose2), meas, (e0,ArrayPartition(x[1:2],_Rot.RotMatrix(x[3]))) , tfg=tfg)[1]

@show δ([0;0;0.]);
@show δ([1.;0;0.]);

##

@test isapprox(δ([0;0;0.]), δ([0;0;0.]); atol=1e-6)
@test isapprox(δ([10;0;0.]), δ([10;0;0.]); atol=1e-6)
@test !isapprox( δ([0;0;0.]), δ([0.1;0;0.]), atol=1e-6 )
# should be sensitive to rotation offsets
@test_broken !isapprox( δ([0;0;0.]), δ([0;0;0.1]), atol=1e-6 )


## build into graph

fg = initfg()
getSolverParams(fg).inflateCycles=1

addVariable!(fg, :x0, Pose2)
addVariable!(fg, :x1, Pose2)

addFactor!(fg, [:x0;], PriorPose2(MvNormal([0;0;0.],[0.01;0.01;0.01])))
f = addFactor!(fg, [:x0;:x1], sap, inflation=0.0)

## use in graph

X1 = approxConvBelief(fg, :x0x1f1, :x1)

c1 = AMP.makeCoordsFromPoint(getManifold(Pose2), mean(X1))
@show c1

##

@warn "SAP disabled test"
# @test isapprox( pCq[1:2], c1[1:2], atol=1.5 )
# @test isapprox( pCq[3], rem2pi(c1[3],RoundNearest),   atol=0.5 )

## Check pack and unpacking of the SAP factor

pf = DFG.packFactor(fg, f)
_fg = initfg()
addVariable!(_fg, :x0, Pose2)
addVariable!(_fg, :x1, Pose2)

f_ = DFG.unpackFactor(_fg, pf)


## check save and load of sap

saveDFG("/tmp/caesar/test_sap", fg)
fg_ = loadDFG("/tmp/caesar/test_sap")

Base.rm("/tmp/caesar/test_sap.tar.gz")

##

sap = getFactorType(fg, :x0x1f1).align
sap_ = getFactorType(fg_, :x0x1f1).align

@test isapprox( sap.cloud1, sap_.cloud1)
@test isapprox( sap.cloud2, sap_.cloud2)

@test sap.gridscale == sap_.gridscale
@test sap.sample_count == sap_.sample_count
@test sap.bw == sap_.bw

##
end



@testset "test ScatterAlignPose2 with MKD direct" begin
##

# setup

oT = [2.; 0]
oΨ =  pi/6

M = SpecialEuclidean(2)
e0 = getPointIdentity(M)
pCq = [oT;oΨ]
qTp = affine_matrix(M, exp(M, e0, hat(M, e0, pCq)))

##

# Points in XY only

# g = (x,y)->pdf(MvNormal([3.;0],[σ;σ]),[x;y]) + pdf(MvNormal([8.;0.0],[σ;σ]),[x;y]) + pdf(MvNormal([0;5.0],[σ;σ]),[x;y])
p1 = vcat([0.1*randn(2).+[3;0.] for i in 1:50], [0.1*randn(2)+[8.;0] for i in 1:50], [0.1*randn(2)+[0;5.] for i in 1:50])
# foreach(pt->(pt[1] += 100), p1)
shuffle!(p1)
P1 = manikde!(Point2, p1)

p2 = vcat([0.1*randn(2).+[3;0.] for i in 1:50], [0.1*randn(2)+[8.;0] for i in 1:50], [0.1*randn(2)+[0;5.] for i in 1:50])
# foreach(pt->(pt[1] += 100), p2)
# adjust points
for (i,pt) in enumerate(p2)
  v = qTp*[pt;1.0]
  pt[1:2] .= v[1:2]
end
shuffle!(p2)
P2 = manikde!(Point2, p2)

sap = ScatterAlignPose2(;cloud1=P1, cloud2=P2, sample_count=100, bw=1.0)

## test plotting function

snt = overlayScatterMutate(sap; sample_count=100, bw=2.0, user_coords=[0.;0;0*oΨ]);
# plotScatterAlign(snt; title="\npCq=$(round.(pCq,digits=2))")

# inverse for q --> p
@warn "SAP disabled test"
# @test isapprox( oT, snt.best_coords[1:2]; atol=1.0 )
# @test isapprox( oΨ,   rem2pi(snt.best_coords[3], RoundNearest); atol=0.5 )

##

fg = initfg()
getSolverParams(fg).inflateCycles=1

addVariable!(fg, :x0, Pose2)
addVariable!(fg, :x1, Pose2)

addFactor!(fg, [:x0], PriorPose2(MvNormal([0.01;0.01;0.01])))
addFactor!(fg, [:x0;:x1], sap, inflation=0.0)

## check residual calculation

# see #1415
# Mr = M.manifold.manifolds[2]
meas = ArrayPartition([0;0.], zeros(2,2)) # sample(P1,100)[1], [ArrayPartition([0;0.],[1 0; 0 1.]) for _ in 1:100], M
δ1 = calcFactorResidualTemporary(sap, (Pose2,Pose2), meas, (e0,e0))

meas = ArrayPartition([1;0.], zeros(2,2)) # sample(P1,100)[1] , [ArrayPartition(sample(P2,1)[1][1],[1 0; 0 1.]) for _ in 1:100], M
δ2 = calcFactorResidualTemporary(sap, (Pose2,Pose2), meas, (e0,e0))

# check different cloud samplings produce different residual values
@test !isapprox(δ1, δ2,  atol=1e-4)

## check that optimize works (using the same tfg)

tfg = initfg()
# meas = sample(P1,100)[1], [ArrayPartition(sample(P2,1)[1][1],[1 0; 0 1.]) for _ in 1:100], M
meas = sampleFactor(fg, :x0x1f1)[1]
δ(x) = calcFactorResidualTemporary(sap, (Pose2,Pose2), meas, (e0,ArrayPartition(x[1:2],_Rot.RotMatrix(x[3]))), tfg=tfg)[1]

@show δ([0;0;0.])
@show δ([1.;0;0.])

@test !isapprox( δ([0;0;0.]), δ([1.;0;0.]), atol=1e-6 )


##

X1 = approxConvBelief(fg, :x0x1f1, :x1)
c1 = AMP.makeCoordsFromPoint(getManifold(Pose2), mean(X1))
@show c1

##

@warn "Disabled a SAP test"
# @test isapprox( pCq[1:2], c1[1:2], atol=1.0 )
# @test isapprox( pCq[3], rem2pi(c1[3], RoundNearest),   atol=0.75 )


##
end



@testset "test ScatterAlignPose3 with MKD direct" begin
##

# setup

oT = [2.; 0;2]
oΨ =  [0;0;pi/10]

M = SpecialEuclidean(3)
e0 = getPointIdentity(M)
pCq = [oT;oΨ]
qTp = affine_matrix(M, exp(M, e0, hat(M, e0, pCq)))

##

# Points in XYZ only

# g = (x,y)->pdf(MvNormal([3.;0],[σ;σ]),[x;y]) + pdf(MvNormal([8.;0.0],[σ;σ]),[x;y]) + pdf(MvNormal([0;5.0],[σ;σ]),[x;y])
p1 = vcat([0.1*randn(3).+[3;0.;0] for i in 1:50], [0.1*randn(3)+[8.;0;0] for i in 1:50], [0.1*randn(3)+[0;5.;0] for i in 1:50])
# foreach(pt->(pt[1] += 100), p1)
shuffle!(p1)
P1 = manikde!(Point3, p1)

p2 = vcat([0.1*randn(3).+[3;0.;0.] for i in 1:50], [0.1*randn(3)+[8.;0;0] for i in 1:50], [0.1*randn(3)+[0;5.;0] for i in 1:50])
# foreach(pt->(pt[1] += 100), p2)
# adjust points
for (i,pt) in enumerate(p2)
  v = qTp*[pt;1.0]
  pt[1:3] .= v[1:3]
end
shuffle!(p2)
P2 = manikde!(Point3, p2)

sap = ScatterAlignPose3(;cloud1=P1, cloud2=P2, sample_count=100, bw=1.0)

## sample from ScatterAlignPose3

fg = initfg()
getSolverParams(fg).inflateCycles=1

addVariable!(fg, :x0, Pose3)
addVariable!(fg, :x1, Pose3)

addFactor!(fg, [:x0], PriorPose3( MvNormal(Diagonal(map(abs2,0.1*ones(6)))) ))
addFactor!(fg, [:x0;:x1], sap, inflation=0.0)

##

Xsmpl = sampleFactor(fg, :x0x1f1)

@test Xsmpl[1] isa ArrayPartition
@test length(Xsmpl[1]) === 12

##
end



#