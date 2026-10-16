import AppKit
import MetalKit

final class GameView: MTKView, MTKViewDelegate {
    weak var engine: EngineCoordinator?
    private var pipeline: MTLRenderPipelineState?
    private var texture: MTLTexture?
    private let frameLock = NSLock()
    private var pixels = [UInt8](repeating: 0, count: 640 * 400 * 4)
    private var hasFrame = false
    private var buttons = 0

    init(device: MTLDevice) {
        super.init(frame: .zero, device: device)
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        isPaused = false
        enableSetNeedsDisplay = false
        preferredFramesPerSecond = 60
        delegate = self
        clearColor = MTLClearColorMake(0.02, 0.02, 0.03, 1)
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 640, height: 400, mipmapped: false)
        desc.usage = [.shaderRead]
        texture = device.makeTexture(descriptor: desc)
        let sourceURL = Bundle.main.url(forResource: "Present", withExtension: "msl")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Present.msl")
        if let source = try? String(contentsOf: sourceURL, encoding: .utf8),
           let library = try? device.makeLibrary(source: source, options: nil),
           let vertex = library.makeFunction(name: "gameVertex"),
           let fragment = library.makeFunction(name: "gameFragment") {
            let state = MTLRenderPipelineDescriptor()
            state.vertexFunction = vertex
            state.fragmentFunction = fragment
            state.colorAttachments[0].pixelFormat = colorPixelFormat
            pipeline = try? device.makeRenderPipelineState(descriptor: state)
        }
    }
    required init(coder: NSCoder) { fatalError("Use init(device:)") }
    override var acceptsFirstResponder: Bool { true }

    func receiveFrame(_ pointer: UnsafePointer<UInt32>) {
        frameLock.lock()
        let byteCount = pixels.count
        pixels.withUnsafeMutableBytes { dest in
            dest.copyMemory(from: UnsafeRawBufferPointer(start: pointer, count: byteCount))
        }
        hasFrame = true
        frameLock.unlock()
    }

    func draw(in view: MTKView) {
        guard let drawable = currentDrawable, let pass = currentRenderPassDescriptor,
              let queue = engine?.presentationQueue, let command = queue.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: pass),
              let pipeline, let texture else { return }
        frameLock.lock()
        if hasFrame {
            pixels.withUnsafeBytes { bytes in
                texture.replace(region: MTLRegionMake2D(0, 0, 640, 400), mipmapLevel: 0,
                                withBytes: bytes.baseAddress!, bytesPerRow: 640 * 4)
            }
        }
        frameLock.unlock()
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        // A 16:10 letterbox keeps Doom's 8:5 framebuffer undistorted.
        let drawableAspect = Double(drawable.texture.width) / Double(drawable.texture.height)
        let gameAspect = 640.0 / 400.0
        if drawableAspect > gameAspect {
            let w = Double(drawable.texture.height) * gameAspect
            encoder.setViewport(MTLViewport(originX: (Double(drawable.texture.width)-w)/2,
                                            originY: 0, width: w,
                                            height: Double(drawable.texture.height), znear: 0, zfar: 1))
        } else {
            let h = Double(drawable.texture.width) / gameAspect
            encoder.setViewport(MTLViewport(originX: 0, originY: (Double(drawable.texture.height)-h)/2,
                                            width: Double(drawable.texture.width), height: h, znear: 0, zfar: 1))
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
        command.present(drawable)
        command.commit()
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    override func keyDown(with event: NSEvent) {
        if event.isARepeat { return }
        if event.modifierFlags.contains(.command) { super.keyDown(with: event); return }
        if let key = doomKey(event) { engine?.enqueueKey(pressed: true, key: key) }
    }
    override func keyUp(with event: NSEvent) { if let key = doomKey(event) { engine?.enqueueKey(pressed: false, key: key) } }
    override func flagsChanged(with event: NSEvent) {
        let pair: (UInt16, NSEvent.ModifierFlags, UInt8)?
        switch event.keyCode {
        case 56, 60: pair = (event.keyCode, .shift, 0xb6)
        case 59, 62: pair = (event.keyCode, .control, 0xa3)
        case 58, 61: pair = (event.keyCode, .option, 0xb8)
        default: pair = nil
        }
        if let (_, flag, key) = pair { engine?.enqueueKey(pressed: event.modifierFlags.contains(flag), key: key) }
    }
    private func doomKey(_ event: NSEvent) -> UInt8? {
        switch event.keyCode {
        case 123: return 0xac // left
        case 124: return 0xae // right
        case 125: return 0xaf // down
        case 126: return 0xad // up
        case 36, 76: return 13
        case 53: return 27
        case 49: return 0xa2 // use
        case 48: return 9
        case 51: return 127
        default:
            guard let c = event.charactersIgnoringModifiers?.lowercased().utf8.first else { return nil }
            return c
        }
    }
    override func mouseDown(with event: NSEvent) { buttons |= 1; engine?.enqueueMouse(buttons: buttons, dx: 0, dy: 0) }
    override func mouseUp(with event: NSEvent) { buttons &= ~1; engine?.enqueueMouse(buttons: buttons, dx: 0, dy: 0) }
    override func rightMouseDown(with event: NSEvent) { buttons |= 2; engine?.enqueueMouse(buttons: buttons, dx: 0, dy: 0) }
    override func rightMouseUp(with event: NSEvent) { buttons &= ~2; engine?.enqueueMouse(buttons: buttons, dx: 0, dy: 0) }
    override func mouseMoved(with event: NSEvent) { engine?.enqueueMouse(buttons: buttons, dx: Int(event.deltaX), dy: -Int(event.deltaY)) }
    override func mouseDragged(with event: NSEvent) { mouseMoved(with: event) }
    override func rightMouseDragged(with event: NSEvent) { mouseMoved(with: event) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
}
