//
//  VirtualObjectARView.swift
//  NeverMindTests
//
//  Created by Sarah Yan on 12/30/18.
//  Copyright © 2018 MIT Media Labs: Fluid Interfaces. All rights reserved.
// This functionality allows user to place objects on plane surfaces

import Foundation
import ARKit

class VirtualObjectARView: ARSCNView {
    
    // - MARK: position testing
    
    // function to find an object at the provided point
    func virtualObject(at point: CGPoint) -> VirtualObject? {
        let hitTestOptions: [SCNHitTestOption: Any] = [.boundingBoxOnly: true]
        let hitTestResults = hitTest(point, options: hitTestOptions)
        
        return hitTestResults.lazy.compactMap { result in
            return VirtualObject.existingObjectContainingNode(result.node)
        }.first
    }
    
    func smartHitTest(_ point: CGPoint, infinitePlane: Bool = false, objectPosition: float3? = nil, allowedAlignments: [ARPlaneAnchor.Alignment] = [.horizontal, .vertical]) -> ARHitTestResult? {
        
        // Perform the hit testing here using the plane geometry
        let results = hitTest(point, types: [.existingPlaneUsingGeometry, .estimatedVerticalPlane, .estimatedHorizontalPlane])
        
        // Check for a result on an existing plane using geometry
        if let currentPlaneUsingGeometryResult = results.first(where: { $0.type == .existingPlaneUsingGeometry }),
            let anchor = currentPlaneUsingGeometryResult.anchor as? ARPlaneAnchor, allowedAlignments.contains(anchor.alignment) {
            return currentPlaneUsingGeometryResult
        }
        
        // Check for the result on an existing plane, assuming that the dimensions are infinite
        // Loop through all hits against infinite existing planes and either return the nearest
        // one (vertical planes) or return the nearest one which is within 5cm of the obj's position
        if infinitePlane {
            let infinitePlaneResults = hitTest(point, types: .existingPlane)
            for infinitePlaneResult in infinitePlaneResults{
                if let anchor_plane = infinitePlaneResult.anchor as? ARPlaneAnchor, allowedAlignments.contains(anchor_plane.alignment) {
                    // return the first vertical plane hit test result
                    if anchor_plane.alignment == .vertical {
                        return infinitePlaneResult
                    } else {
                        // if the horizontal plane is close to the current object's position
                        // return a hit test result
                        if let objY = objectPosition?.y {
                            let planeY = infinitePlaneResult.worldTransform.translation.y
                            if objY > planeY - 0.05 && objY < planeY + 0.05 {
                                return infinitePlaneResult
                            }
                        } else {
                            return infinitePlaneResult
                        }
                    }
                }
            }
        }
        // if the above doesn't work, check for a result on estimated planes for vertical and horizontal
        let vertical_result = results.first(where: { $0.type == .estimatedVerticalPlane })
        let horizontal_result = results.first(where: { $0.type == .estimatedHorizontalPlane })
        switch (allowedAlignments.contains(.horizontal), allowedAlignments.contains(.vertical)){
            // allow fallback to horizontal plane
            // assume objects are meant for vertical placement
            case(true, false):
                return horizontal_result
            case(false, true):
                return vertical_result ?? horizontal_result
            case (true, true):
                if horizontal_result != nil && vertical_result != nil {
                    return horizontal_result!.distance < vertical_result!.distance ? horizontal_result! : vertical_result!
                } else {
                    return horizontal_result ?? vertical_result
                }
            default:
                return nil
        }
    }
    
    // - MARK: anchor object
    func addOrUpdateAnchor(for object: VirtualObject){
        // if the anchor is not nil, remove it from the session
        if let anchor = object.anchor {
            session.remove(anchor: anchor)
        }
        
        // create a new anchor with current object transform
        // then add to the session
        let new_anchor = ARAnchor(transform: object.simdWorldTransform)
        object.anchor = new_anchor
        session.add(anchor: new_anchor)
    }
    
    // - MARK: Lighting
    var lighting_root_node: SCNNode? {
        return scene.rootNode.childNode(withName: "lighting_root_node", recursively: true)
    }
    
    func setupDirectionaLighting(queue: DispatchQueue){
        guard self.lighting_root_node == nil else {
            return
        }
        
        // add directional lighting for dynamic highlights as well as ambient lighting
        guard let lighting_scene = SCNScene(named: "lighting.scn", inDirectory: "Models.scnassets", options: nil) else {
            print("Error setting up directional lights: could not find lighting scene in resources.")
            return
        }
        
        let lighting_root_node = SCNNode()
        lighting_root_node.name = "lighting_root_node"
        
        for node in lighting_scene.rootNode.childNodes where node.light != nil {
            lighting_root_node.addChildNode(node)
        }
        
        queue.sync {
            self.scene.rootNode.addChildNode(lighting_root_node)
        }
    }
    
    // make sure to update the directional light
    func updateDirectionalLighting(intensity: CGFloat, queue: DispatchQueue){
        guard let lighting_root_node = self.lighting_root_node else {
            return
        }
        
        queue.async {
            for node in lighting_root_node.childNodes {
                node.light?.intensity = intensity
            }
        }
    }
}


extension SCNView {
    func unprojectPoint(_ point: float3) -> float3 {
        return float3(unprojectPoint(SCNVector3(point)))
    }
}
