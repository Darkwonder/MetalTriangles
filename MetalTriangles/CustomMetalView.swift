//
//  CustomMetalView.swift
//  MetalTriangles
//
//  Created by Mladen Mikic on 15/07/2020.
//

import Foundation
import Metal
import Cocoa
import AppKit
import CoreMedia


class CustomMetalView: NSView,
                       // https://developer.apple.com/documentation/quartzcore/calayerdelegate
                       CALayerDelegate {
    
    // https://developer.apple.com/documentation/quartzcore/cametallayer
    private var metalLayer: CAMetalLayer! = nil
    
    // https://developer.apple.com/documentation/metal/mtlcommandqueue
    private var commandQueue: MTLCommandQueue! = nil
    
    // https://developer.apple.com/documentation/metal/mtlrenderpassdescriptor
    private let passDescriptor = MTLRenderPassDescriptor()
    
    private var displayLink: CVDisplayLink! = nil
    
    // https://developer.apple.com/documentation/metal/mtldevice
    private var device: MTLDevice! = nil
    
    private var pipeline: MTLRenderPipelineState! = nil
    
    // https://developer.apple.com/documentation/metal/mtlbuffer
    private var positionBuffer: MTLBuffer! = nil
    
    private var colorBuffer: MTLBuffer! = nil
    
    // https://developer.apple.com/documentation/metal/mtlrenderpasscolorattachmentdescriptor
    private var colorAttachment: MTLRenderPassColorAttachmentDescriptor! = nil
    
    
    // MARK: - Init
    
    override public init(frame:NSRect) {
        super.init(frame:frame)
        self.commonInit()
        print("Function: \(#function), line: \(#line)")
    }
    
    required public init?(coder:NSCoder) {
        super.init(coder:coder)
        self.commonInit()
        print("Function: \(#function), line: \(#line)")
    }
    
    open func commonInit() {
        print("Function: \(#function), line: \(#line)")
        self.wantsLayer = true
        self.layerContentsRedrawPolicy = .duringViewResize
    }
    
    deinit {
        self.stopDisplayLink()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - View methods
    
    // https://developer.apple.com/documentation/appkit/nsview/1483687-makebackinglayer
    override func makeBackingLayer() -> CALayer {
        print("Function: \(#function), line: \(#line)")
        // https://developer.apple.com/documentation/quartzcore/cametallayer
        let layer = CAMetalLayer()
        layer.pixelFormat = .bgra8Unorm
        layer.delegate = self
        
        if let scaleFactor = NSScreen.main?.backingScaleFactor {
            layer.contentsScale = scaleFactor
        }
        
        self.metalLayer = layer

        return layer
    }
    
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        print("Function: \(#function), line: \(#line)")
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.windowDidClose), name: NSWindow.willCloseNotification, object: nil)
        self.startDisplayLink()
    }
    
    override func removeFromSuperview() {
        super.removeFromSuperview()
        print("Function: \(#function), line: \(#line)")
        
        self.stopDisplayLink()
    }
    
    // MARK: - Helpers
    
    @objc func windowDidClose() {
        print("Function: \(#function), line: \(#line)")
        
        self.stopDisplayLink()
    }
    
    func assignDevice(_ device: MTLDevice) {
        print("Function: \(#function), line: \(#line)")
        self.metalLayer.device = device
        self.device = device
        print("\nDevice \(device.name) has been set to: \(self).")
        
        prepareForDrawing()
    }
    
    private func prepareForDrawing() {
        print("Function: \(#function), line: \(#line)")
         
        // Do expensive one time setup code here:
        guard let commandQueue = self.metalLayer.device?.makeCommandQueue() else { return }
        self.commandQueue = commandQueue
        
        self.setupColorAttachment()
        self.buildVertexBuffers()
        self.buildPipeline()
    }
    
    private func buildVertexBuffers() {
        print("Function: \(#function), line: \(#line)")
        
        guard let device: MTLDevice = self.device else { return }
        let positions:[Float] = [
            0.0,  0.5, 0, 1,
            -0.5, -0.5, 0, 1,
            0.5, -0.5, 0, 1
        ]
         
        let colors:[Float] = [
            1, 0, 0, 1,
            0, 1, 0, 1,
            0, 0, 1, 1]
        
        let positionsLength = MemoryLayout.size(ofValue: positions[0]) * positions.count
        let colorsLength = MemoryLayout.size(ofValue: colors[0]) * colors.count
 
        self.positionBuffer = device.makeBuffer(bytes: positions, length: positionsLength, options: .cpuCacheModeWriteCombined)
        self.colorBuffer = device.makeBuffer(bytes: colors, length: colorsLength, options: .cpuCacheModeWriteCombined)
    }
    
    private func buildPipeline() {
        print("Function: \(#function), line: \(#line)")
        
        guard let device: MTLDevice = self.device else { return }
        // https://developer.apple.com/documentation/metal/mtllibrary
        guard let library: MTLLibrary = device.makeDefaultLibrary() else { return }
        
        // https://developer.apple.com/documentation/metal/mtlrenderpipelinedescriptor
        let pipelineDescriptor: MTLRenderPipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        // https://developer.apple.com/documentation/metal/mtlfunction
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "vertex_main")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
        
        do
        {
            self.pipeline = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        }
        catch let error
        {
            print("\n\(self) failed with error \(error.localizedDescription).")
            return
        }
    }
    
    private func setupColorAttachment() {
        print("Function: \(#function), line: \(#line)")
        
        self.colorAttachment = self.passDescriptor.colorAttachments[0]
        self.colorAttachment?.loadAction = .clear
        self.colorAttachment?.storeAction = .store
        self.colorAttachment?.clearColor = MTLClearColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
    }
    
    private func startDisplayLink() {
        print("Function: \(#function), line: \(#line)")
        
        guard self.displayLink == nil else { return }
        // The following code is based on https://stackoverflow.com/questions/25981553/cvdisplaylink-with-swift
        // and https://developer.apple.com/documentation/metal/drawable_objects/creating_a_custom_metal_view
        
        let outputCallback:CVDisplayLinkOutputCallback =
        {
            (displayLink:CVDisplayLink, inNow:UnsafePointer<CVTimeStamp>, inOutputTime:UnsafePointer<CVTimeStamp>, flagsIn:CVOptionFlags, flagsOut:UnsafeMutablePointer<CVOptionFlags>, displayLinkContext:UnsafeMutableRawPointer?) -> CVReturn in

            let view = unsafeBitCast(displayLinkContext, to:CustomMetalView.self)
            
            view.redraw()
        
            
            return kCVReturnSuccess
        }

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        // Create and start a CVDisplayLink
        
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        
        if let displayLink = self.displayLink
        {
            CVDisplayLinkSetOutputCallback(displayLink, outputCallback, context)
            CVDisplayLinkStart(displayLink)
        }

    }
    
    private func stopDisplayLink() {
        print("Function: \(#function), line: \(#line)")
        if let displayLink = self.displayLink
        {
            CVDisplayLinkStop(displayLink)
            self.displayLink = nil
        }
    }
    
    // MARK: - Drawing.
    
    func redraw() {
        print("Function: \(#function), line: \(#line)")
        
        guard let commandQueue = self.commandQueue else { return }
                
        // https://developer.apple.com/documentation/quartzcore/cametaldrawable
        guard let drawable = self.metalLayer.nextDrawable() else { return }
        
        // https://developer.apple.com/documentation/metal/mtltexture
        let texture = drawable.texture
        
        guard let colorAttachment = self.colorAttachment else { return }
        colorAttachment.texture = texture
        
        // https://developer.apple.com/documentation/metal/mtlcommandbuffer
        let commandBuffer = commandQueue.makeCommandBuffer()
        
        // https://developer.apple.com/documentation/metal/mtlrendercommandencoder
        let commandEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: passDescriptor)
        
        // Adding few commands:
        
        commandEncoder?.setRenderPipelineState(self.pipeline)
        commandEncoder?.setVertexBuffer(self.positionBuffer, offset: 0, index: 0)
        commandEncoder?.setVertexBuffer(self.colorBuffer, offset: 0, index: 1)
        commandEncoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3, instanceCount: 1)
        
        // Add several commands from different sources:
        // self.renderPatch.forEach{ $0.renderWith(commandEncoder) }
        
        commandEncoder?.endEncoding()
        
        commandBuffer?.present(drawable)
        commandBuffer?.commit()
    }
}

