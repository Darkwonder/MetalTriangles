//
//  ViewController.swift
//  MetalTriangles
//
//  Created by Mladen Mikic on 15/07/2020.
//

import Cocoa
import Metal

class ViewController: NSViewController {

    private var selectedDevice: MTLDevice?
    private var metalView: CustomMetalView? {
        return self.view as? CustomMetalView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupMetalDevice()
        
        guard let device = self.selectedDevice else { return }
        self.metalView?.assignDevice(device)
    }

    private func setupMetalDevice() {
        self.selectedDevice = MTLCopyAllDevices().first
    }


}

