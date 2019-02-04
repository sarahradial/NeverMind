//
//  VirtualObject.swift
//  NeverMind
//
//  Created by Sarah Yan on 12/30/18.
//  Copyright © 2018 MIT Media Labs: Fluid Interfaces. All rights reserved.
//

import Foundation
import SceneKit
import ARKit

class VirtualObject: SCNReferenceNode {
    var model_name: String {
        return referenceURL.lastPathComponent.replacingOccurrences(of: ".scn", with: "")
    }
    
    // to avoid rapid changes in object scale, use average of recent virtual object distances
    private var recentVirtualObjectDistances = [Float]()
    
    // allowed aignments for virtual object
    var allowed_alignments: [ARPlaneAnchor.Alignment] {
        if model_name == "sticky note" {
            return [.horizontal, .vertical]
        } else if model_name == "painting" {
            return [.vertical]
        } else {
            return [.horizontal]
        }
    }
    
    // current alignment of the virtual object
    var curr_alignment: ARPlaneAnchor.Alignment = .horizontal
    private var is_changing_alignment: Bool = false
    
    // to rotate correctly, rotate around local y rather than world y
    var object_rotation: Float {
        get {
            return childNodes.first!.eulerAngles.y
        }
        set (newValue) {
            var normalized = newValue.truncatingRemainder(dividingBy: 2 * .pi)
            normalized = (normalized + 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi)
            if normalized > .pi {
                normalized -= 2 * .pi
            }
            childNodes.first!.eulerAngles.y = normalized
            if curr_alignment == .horizontal {
                rotationWhenAlignedHorizontally = normalized
            }
        }
    }
    
    // remember last rotation for horizontal alignment
    var rotationWhenAlignedHorizontally: Float = 0
    
    // corresponding ARAnchor
    var anchor: ARAnchor?
    
    // reset object position smoothing
    func reset(){
        recentVirtualObjectDistances.removeAll()
    }
    
    // - MARK: helper functions to determine supported placement options
    func isPlacementValid(on planeAnchor: ARPlaneAnchor?) -> Bool {
        if let anchor = planeAnchor {
            return allowed_alignments.contains(anchor.alignment)
        }
        return true
    }
    
    // set the object's position based on the provided position relative to the "cameraTransform"
    // if smoothmovement is active, the new position will be avergaed ith previous position to avoid large jumps
    func setTransform(_ newTransform: float4x4, relativeTo cameraTransform: float4x4, smoothMovement: Bool,
                      alignment: ARPlaneAnchor.Alignment, allowAnimation: Bool){
        let camera_world_pos = cameraTransform.translation
        var position_offset_camera = newTransform.translation - camera_world_pos
        
        // limit distance of the object from the camera to a max of 10 meters
        if simd_length(position_offset_camera) > 10 {
            position_offset_camera = simd_normalize(position_offset_camera)
            position_offset_camera *= 10
        }
        
        // compute object average distance from the camera over the last ten updates
        if smoothMovement {
            let distance_hit_test_result = simd_length(position_offset_camera)
            
            // add the latest position and keep up to 10 recent distance to smooth with
            recentVirtualObjectDistances.append(distance_hit_test_result)
            recentVirtualObjectDistances = Array(recentVirtualObjectDistances.suffix(10))
            
            let average_dist = recentVirtualObjectDistances.average!
            let averaged_dist_pos = simd_normalize(position_offset_camera) * average_dist
            simdPosition = camera_world_pos + averaged_dist_pos
        } else {
            simdPosition = camera_world_pos + position_offset_camera
        }
        
        updateAlignment(to: alignment, transform: newTransform, allowAnimation: allowAnimation)
    }
    
    // - MARK: setting the object's alignment
    func updateAlignment(to new_alignment: ARPlaneAnchor.Alignment, transform: float4x4, allowAnimation: Bool) {
        if is_changing_alignment {
            return
        }
        // only animate if the alignment has change.
        let dur_animation = (new_alignment != curr_alignment && allowAnimation) ? 0.5 : 0
        
        var new_object_rotation: Float?
        switch (new_alignment, curr_alignment) {
            case (.horizontal, .horizontal):
                return
            case (.horizontal, .vertical):
                new_object_rotation = rotationWhenAlignedHorizontally
            case (.vertical, .horizontal):
                new_object_rotation = 0.0001
            default:
                break
        }
        
        curr_alignment = new_alignment
        
        SCNTransaction.begin()
        SCNTransaction.animationDuration = dur_animation
        SCNTransaction.completionBlock = {
            self.is_changing_alignment = false
        }
        is_changing_alignment = true
        
        // use the filtered position rather than the exact one from transform
        var mutable_transform = transform
        mutable_transform.translation = simdWorldPosition
        simdTransform = mutable_transform
        
        if new_object_rotation != nil {
            object_rotation = new_object_rotation!
        }
        
        SCNTransaction.commit()
    }
    
    func adjustOntoPlaneAnchor(_ anchor: ARPlaneAnchor, using node: SCNNode) {
        // check for alignment of the plane is compatible with the object's allowed placement
        if !allowed_alignments.contains(anchor.alignment){
            return
        }
        
        // get object position in plane's coordinate system
        let plane_pos = node.convertPosition(position, from: parent)
        
        // check that the object isn't already on the plane
        guard plane_pos.y != 0 else { return }
        
        // add some tolerance to the corners of the plane
        let tolerance: Float = 0.1
        
        let x_min: Float = anchor.center.x - anchor.extent.x/2 - anchor.extent.x * tolerance
        let x_max: Float = anchor.center.x + anchor.extent.x/2 + anchor.extent.x * tolerance
        let z_min: Float = anchor.center.z - anchor.extent.z/2 - anchor.extent.z * tolerance
        let z_max: Float = anchor.center.z + anchor.extent.z/2 + anchor.extent.z * tolerance
        
        guard (x_min...x_max).contains(plane_pos.x) && (z_min...z_max).contains(plane_pos.z) else {
            return
        }
        
        // move onto plane if it is near it (about 5 cms)
        let allow_vertical: Float = 0.05
        let epsilon: Float = 0.001
        let plane_dist = abs(plane_pos.y)
        if plane_dist > epsilon && plane_dist < allow_vertical {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = CFTimeInterval(plane_dist * 500)
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut)
            position.y = anchor.transform.columns.3.y
            updateAlignment(to: anchor.alignment, transform: simdWorldTransform, allowAnimation: false)
            SCNTransaction.commit()
        }
    }
}

extension VirtualObject {
    // loads all the model objects within 'Models.scnassets'
    static let available_objs: [VirtualObject] = {
        let URL_models = Bundle.main.url(forResource: "Models.scnassets", withExtension: nil)!
        
        let file_enum = FileManager().enumerator(at: URL_models, includingPropertiesForKeys: [])!
        
        return file_enum.compactMap { element in
            let url = element as! URL
            guard url.pathExtension == "scn" && !url.path.contains("lighting") else { return nil }
            return VirtualObject(url: url)
        }
    }()
    
    // returns a VirtualObjects if one exists as an ancestor to the given node
    static func existingObjectContainingNode(_ node: SCNNode) -> VirtualObject? {
        if let root_virtual_obj = node as? VirtualObject {
            return root_virtual_obj
        }
        
        guard let parent = node.parent else { return nil }
        
        return existingObjectContainingNode(parent)
    }
}

extension Collection where Element == Float, Index == Int {
    // return the mean of a list of floats
    var average: Float? {
        guard !isEmpty else {
            return nil
        }
        
        let sum = reduce(Float(0)) { current, next -> Float in
            return current + next
        }
        
        return sum / Float(count)
    }
}
