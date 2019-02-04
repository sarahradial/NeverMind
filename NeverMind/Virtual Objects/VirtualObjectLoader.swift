//
//  VirtualObjectLoader.swift
//  NeverMind
//
//  Created by Sarah Yan on 12/30/18.
//  Copyright © 2019 MIT Media Labs: Fluid Interfaces. All rights reserved.
//

import Foundation
import ARKit

// in the background queue, load multiple virtual objects to display
// the objects quickly once they are needed

class VirtualObjectLoader {
    private(set) var obj_loaded = [VirtualObject]()
    private(set) var is_loading = false
    
    // - MARK: loading object
    func loadVirtualObject(_ object: VirtualObject, loadedHandler: @escaping (VirtualObject) -> Void){
        is_loading = true
        obj_loaded.append(object)
        
        // load the content asynchronously
        DispatchQueue.global(qos: .background).async {
            object.reset()
            object.load()
            
            self.is_loading = false
            loadedHandler(object)
        }
    }
    
    // - MARK: removing objects
    func removeAllVirtualObjects(){
        // reverse the indices
        for index in obj_loaded.indices.reversed(){
            removeVirtualObject(at: index)
        }
    }
    // helper function to remove an object at a given index
    func removeVirtualObject(at index: Int){
        guard obj_loaded.indices.contains(index) else { return } // error checking
        
        obj_loaded[index].removeFromParentNode()
        obj_loaded.remove(at: index)
    }
}
