//
//  ViewController+ARSCNViewDelegate.swift
//  NeverMind
//
//  Created by Sarah Yan on 1/4/19.
//  Copyright © 2019 MIT Media Labs: Fluid Interfaces. All rights reserved.
//

import ARKit

extension ViewController: ARSCNViewDelegate, ARSessionDelegate {
    // - MARK: ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let isAnyObjectInView = virtualObjectLoader.obj_loaded.contains { object in
            return sceneView.isNode(object, insideFrustumOf: sceneView.pointOfView!)
        }
        
        DispatchQueue.main.async {
            self.virtualObjectInteraction.updateObjectToCurrentTrackingPosition()
            self.updateFocusSquare(isObjectVisible: isAnyObjectInView)
        }
        
        // If the object selection menu is open, update availability of items
        if objectsViewController != nil {
            let planeAnchor = focusSquare.currentPlaneAnchor
            objectsViewController?.updateObjectAvailability(for: planeAnchor)
        }
        
        // If light estimation is enabled, update the intensity of the directional lights
        if let lightEstimate = session.currentFrame?.lightEstimate {
            sceneView.updateDirectionalLighting(intensity: lightEstimate.ambientIntensity, queue: updateQueue)
        } else {
            sceneView.updateDirectionalLighting(intensity: 1000, queue: updateQueue)
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let plane_anchor = anchor as? ARPlaneAnchor else { return }
        
        DispatchQueue.main.async {
            self.statusViewController.cancelScheduledMessage(for: .planeEstimation)
            self.statusViewController.showMessage("surface detected")
            
            if self.virtualObjectLoader.obj_loaded.isEmpty {
                self.statusViewController.scheduleMessage("Tap + to place an object", inSeconds: 8.0, messageType: .contentPlacement)
            }
        }
        
        updateQueue.async {
            for obj in self.virtualObjectLoader.obj_loaded {
                obj.adjustOntoPlaneAnchor(plane_anchor, using: node)
            }
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        updateQueue.async {
            if let plane_anchor = anchor as? ARPlaneAnchor {
                for obj in self.virtualObjectLoader.obj_loaded {
                    obj.adjustOntoPlaneAnchor(plane_anchor, using: node)
                }
            } else {
                if let obj_at_anchor = self.virtualObjectLoader.obj_loaded.first(where: { $0.anchor == anchor }) {
                    obj_at_anchor.simdPosition = anchor.transform.translation
                    obj_at_anchor.anchor = anchor
                }
            }
        }
    }
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        statusViewController.showTrackingQualityInfo(for: camera.trackingState, autoHide: true)
        
        switch camera.trackingState {
        case .notAvailable, .limited:
            statusViewController.escalateFeedback(for: camera.trackingState, inSeconds: 3.0)
        case .normal:
            statusViewController.cancelScheduledMessage(for: .trackingStateEscalation)
            
            // unhide content after successful relocalization
            virtualObjectLoader.obj_loaded.forEach { $0.isHidden = false }
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        guard error is ARError else { return }
        
        let error_with_info = error as NSError
        let messages = [
            error_with_info.localizedDescription,
            error_with_info.localizedFailureReason,
            error_with_info.localizedRecoverySuggestion
        ]
        
        let error_message = messages.compactMap({ $0 }).joined(separator: "\n")
        
        DispatchQueue.main.async {
            self.displayErrorMessage(title: "The AR Session failed.", message: error_message)
        }
    }
    
    // hide content before going into the background
    func sessionWasInterrupted(_ session: ARSession) {
        virtualObjectLoader.obj_loaded.forEach { $0.isHidden = true }
    }
    
    
    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
        return true
    }
    
}
