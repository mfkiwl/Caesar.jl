
@info "Caesar._PCL is loading tools related to Gadfly.jl."

# import ..Gadfly as GF

## =====================================================================================
## _PCL plotting utils
## =====================================================================================

# FIXME move pointcloud plotting to Arena.jl instead
function plotPointCloud(pc::PointCloud)
  x = (s->s.data[1]).(pc.points)
  y = (s->s.data[2]).(pc.points)

  Main.Gadfly.plot(x=x,y=y, Main.Gadfly.Geom.point)
end