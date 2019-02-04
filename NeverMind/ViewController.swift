//
//  ViewController.swift
//  NeverMind
//
//  Created by Sarah Yan on 12/25/18.
//  Copyright © 2018 MIT Media Labs: Fluid Interfaces. All rights reserved.
//

import UIKit
import SceneKit
import ARKit

class ViewController: UIViewController {

    @IBOutlet var sceneView: VirtualObjectARView!
    
    @IBOutlet weak var addObjectButton: UIButton!
    
    @IBOutlet weak var blurView: UIVisualEffectView!
    
    @IBOutlet weak var spinner: UIActivityIndicatorView!
    
    var focusSquare = FocusSquare()
    
    /// The view controller that displays the status and "restart experience" UI.
    lazy var statusViewController: StatusViewController = {
        return children.lazy.compactMap({ $0 as? StatusViewController }).first!
    }()
    
    /// The view controller that displays the virtual object selection menu.
    var objectsViewController: VirtualObjectSelectionViewController?
    
    // MARK: - ARKit Configuration Properties
    
    /// A type which manages gesture manipulation of virtual content in the scene.
    lazy var virtualObjectInteraction = VirtualObjectInteraction(sceneView: sceneView)
    
    /// Coordinates the loading and unloading of reference nodes for virtual objects.
    let virtualObjectLoader = VirtualObjectLoader()
    
    /// Marks if the AR experience is available for restart.
    var isRestartAvailable = true
    
    /// A serial queue used to coordinate adding or removing nodes from the scene.
    let updateQueue = DispatchQueue(label: "com.example.apple-samplecode.arkitexample.serialSceneKitQueue")
    
    var screenCenter: CGPoint {
        let bounds = sceneView.bounds
        return CGPoint(x: bounds.midX, y: bounds.midY)
    }
    
    var session: ARSession {
        return sceneView.session
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view's delegate
        sceneView.delegate = self
        sceneView.session.delegate = self
        
        // set up scene content
        setupCamera()
        sceneView.scene.rootNode.addChildNode(focusSquare)
        
        sceneView.setupDirectionalLighting(queue: updateQueue)
        
        // hook up status view controller callback(s)
        statusViewController.restartExperienceHandler = { [unowned self] in
            self.restartExperience()
        }
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(showVirtualObjectSelectionViewController))
        // set the delegate to ensure this gesture is only used when there are no virtual objects in the scene.
        tapGesture.delegate = self
        sceneView.addGestureRecognizer(tapGesture)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // prevent the screen from being dimmed to avoid interuptions during the AR experience
        UIApplication.shared.isIdleTimerDisabled = true
        
        resetTracking() // start ARSession
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        session.pause()
    }

    func setupCamera() {
        guard let camera = sceneView.pointOfView?.camera else {
            fatalError("Expected a valid 'point of view' from the scene.")
        }
        
        // now enable HDR camera settings for the most realistic apperance with environmental lighting and physically based materials
        camera.wantsHDR = true
        camera.exposureOffset = -1
        camera.minimumExposure = -1
        camera.maximumExposure = 3
    }
    
    // creates a new AR configuration to run on the session
    func resetTracking() {
        VirtualObjectInteraction.selectedObject = nil
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        if #available(iOS 12.0, *) {
            configuration.environmentTexturing = .automatic
        }
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        
        statusViewController.scheduleMessage("Find a surface to place an object", inSeconds: 8, messageType: .planeEstimation)
    }
    
    // - MARK: focus square
    func updateFocusSquare(isObjectVisible: Bool) {
        if isObjectVisible {
            focusSquare.hide()
        } else {
            focusSquare.unhide()
            statusViewController.scheduleMessage("Try moving left or right", inSeconds: 5.0, messageType: .focusSquare)
        }
        
        // perform hit testing only when ARKit tracking is in a good state
        if let camera = session.currentFrame?.camera, case .normal = camera.trackingState, let result = self.sceneView.smartHitTest(screenCenter) {
            updateQueue.async {
                self.sceneView.scene.rootNode.addChildNode(self.focusSquare)
                self.focusSquare.satte = .detecting(hitTestResult: result, camera: camera)
            }
            addObjectButton.isHidden = false
            statusViewController.cancelScheduleMessage(for: .focusSquare)
        } else {
            updateQueue.async {
                self.focusSquare.state = .initializing
                self.sceneView.pointOfView?.addChildNode(self.focusSquare)
                addObjectButton.isHidden = true
            }
        }
    }
    
    // - MARK: error handling
    func displayErrorMessage(title: String, message: String) {
        // blur background
        blurView.isHidden = false
        
        // present an alert about error
        let alert_controller = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let restart_action = UIAlertAction(title: "restart session", style: .default) {
            _ in alertController.dismiss(animated: true, completion: nil)
            self.blurView.isHidden = true
            self.resetTracking()
        }
        alert_controller.addAction(restart_action)
        present(alert_controller, animated: true, completion: nil)
    }
    
    
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
        
    }
}
