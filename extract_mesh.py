import argparse
import open3d as o3d
import numpy as np
from pxr import Usd, UsdGeom, UsdPhysics

def cloud_to_physical_usd(input_ply, output_usd):

    print("Loading point cloud...")
    pcd = o3d.io.read_point_cloud(input_ply)

    print("Estimating normals...")
    pcd.estimate_normals(
        search_param=o3d.geometry.KDTreeSearchParamHybrid(
            radius=0.1, max_nn=30
        )
    )

    print("Running Poisson reconstruction...")
    mesh, densities = o3d.geometry.TriangleMesh.create_from_point_cloud_poisson(
        pcd, depth=9
    )

    print("Removing low density vertices...")
    vertices_to_remove = densities < np.quantile(densities, 0.05)
    mesh.remove_vertices_by_mask(vertices_to_remove)

    temp_obj = "temp_room.obj"
    print("Exporting mesh...")
    o3d.io.write_triangle_mesh(temp_obj, mesh)

    print("Creating USD stage...")
    stage = Usd.Stage.CreateNew(output_usd)
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.z)

    room_path = "/World/Room"
    room_mesh = UsdGeom.Mesh.Define(stage, room_path)

    UsdPhysics.CollisionAPI.Apply(room_mesh.GetPrim())
    mesh_collision = UsdPhysics.MeshCollisionAPI.Apply(room_mesh.GetPrim())
    mesh_collision.CreateApproximationAttr().Set("meshSimplification")

    stage.GetRootLayer().Save()

    print(f"Done: {output_usd}")
    print("NOTE: OBJ mesh still needs importing into USD")

if __name__ == "__main__":

    parser = argparse.ArgumentParser()
    parser.add_argument("input", help="Input PLY point cloud")
    parser.add_argument("output", help="Output USD file")

    args = parser.parse_args()

    cloud_to_physical_usd(args.input, args.output)
