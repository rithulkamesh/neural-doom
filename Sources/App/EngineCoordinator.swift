import AppKit
import Metal

private struct KeyEvent { let pressed: Int32; let key: UInt8 }
private struct MouseState { var buttons = 0; var dx = 0; var dy = 0 }

final class EngineCoordinator {
    static var active: EngineCoordinator?
    let queue = DispatchQueue(label: "handwired.doom.engine", qos: .userInteractive)
    let circuit: CircuitRuntime
    let presentationQueue: MTLCommandQueue
    weak var gameView: GameView?
    weak var inspector: InspectorModel?
    private let inputLock = NSLock()
    private var keys: [KeyEvent] = []
    private var mouse = MouseState()
    private var timer: DispatchSourceTimer?
    private var started = false
    private var scheduler = TicScheduler()
    private var evidenceFile: FileHandle?
    private var scriptedTics = 0
    private let autoplay = ProcessInfo.processInfo.environment["HANDWIRED_DOOM_AUTOPLAY"] == "1"
    private(set) var lateTics = 0
    private(set) var catchUpTics = 0
    private var lastProducedFrameNs: UInt64?

    init(device: MTLDevice) {
        circuit = CircuitRuntime(device: device)
        circuit.visualizationEnabled = ProcessInfo.processInfo.environment["HANDWIRED_DOOM_VISUALIZE"] == "1"
        presentationQueue = device.makeCommandQueue()!
        Self.active = self
        circuit.traceHandler = { [weak self] trace, dropped in
            guard let self else { return }
            let graph = self.circuit.graph
            let circuitTics = self.circuit.circuitTics
            let domainFallbacks = self.circuit.domainFallbacks
            let metalFallbacks = self.circuit.metalFallbacks
            let mismatches = self.circuit.mismatches
            let fallbackReason = self.circuit.lastFallback
            DispatchQueue.main.async {
                self.inspector?.publish(trace: trace, graph: graph,
                                        dropped: dropped, circuitTics: circuitTics,
                                        domainFallbacks: domainFallbacks,
                                        metalFallbacks: metalFallbacks,
                                        mismatches: mismatches,
                                        fallbackReason: fallbackReason)
            }
        }
        circuit.countersHandler = { [weak self] in
            guard let self else { return }
            let circuitTics = self.circuit.circuitTics
            let domainFallbacks = self.circuit.domainFallbacks
            let metalFallbacks = self.circuit.metalFallbacks
            let mismatches = self.circuit.mismatches
            let fallbackReason = self.circuit.lastFallback
            DispatchQueue.main.async {
                self.inspector?.refreshCounts(circuitTics: circuitTics,
                                              domainFallbacks: domainFallbacks,
                                              metalFallbacks: metalFallbacks,
                                              mismatches: mismatches,
                                              fallbackReason: fallbackReason)
            }
        }
    }
    func start(iwad: URL, completion: @escaping (String?) -> Void) {
        queue.async {
            guard !self.started else { DispatchQueue.main.async { completion("Restart the app to choose another IWAD.") }; return }
            self.started = true
            if let path = ProcessInfo.processInfo.environment["HANDWIRED_DOOM_TRACE_PATH"] {
                FileManager.default.createFile(atPath: path, contents: nil)
                self.evidenceFile = FileHandle(forWritingAtPath: path)
                self.writeEvidence("host_tick,gametic,in_level,x,y,angle,forward,side,turn,turnheld,ref_forward,ref_side,ref_turn,ref_held,fallback,latency_ns,engine_tic_ns,late_tics,catch_up_tics,frame_interval_ns,trace_count,trace_drops\n")
            }
            iwad.path.withCString { HM_EngineStart($0) }
            self.scheduler.resume(now: DispatchTime.now().uptimeNanoseconds)
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(5), leeway: .milliseconds(1))
            timer.setEventHandler { [weak self] in self?.pump() }
            self.timer = timer
            timer.resume()
            DispatchQueue.main.async { completion(nil) }
        }
    }
    private func pump() {
        guard started else { return }
        let due = scheduler.due(now: DispatchTime.now().uptimeNanoseconds)
        if due > 1 { catchUpTics += due - 1 }
        for _ in 0..<due {
            runOneTic()
        }
        lateTics = max(lateTics, scheduler.lateTics)
    }
    private func runOneTic() {
        if autoplay {
            if scriptedTics == 0 { enqueueKey(pressed: true, key: 0xad) }
            if scriptedTics == 140 { enqueueKey(pressed: false, key: 0xad); enqueueKey(pressed: true, key: 0xae) }
            if scriptedTics == 210 { enqueueKey(pressed: false, key: 0xae) }
            scriptedTics += 1
        }
        let before = DispatchTime.now().uptimeNanoseconds
        injectMouse()
        HM_EngineFrame()
        let elapsed = DispatchTime.now().uptimeNanoseconds - before
        let producedAt = DispatchTime.now().uptimeNanoseconds
        let frameInterval = lastProducedFrameNs.map { producedAt - $0 } ?? 0
        lastProducedFrameNs = producedAt
        if elapsed > scheduler.periodNs { lateTics += 1 }
        if evidenceFile != nil {
            let s = HM_EnginePlayerState()
            let r = circuit.lastResult
            let c = circuit.lastReference
            writeEvidence("\(scriptedTics),\(s.gametic),\(s.in_level),\(s.x),\(s.y),\(s.angle),\(r?.forwardmove ?? 0),\(r?.sidemove ?? 0),\(r?.angleturn ?? 0),\(r?.turnheld ?? 0),\(c?.forwardmove ?? 0),\(c?.sidemove ?? 0),\(c?.angleturn ?? 0),\(c?.turnheld ?? 0),\(circuit.lastFallback),\(circuit.lastLatencyNs),\(elapsed),\(lateTics),\(catchUpTics),\(frameInterval),\(circuit.traces.items.count),\(circuit.traces.dropped)\n")
        }
    }
    private func writeEvidence(_ line: String) { evidenceFile?.write(line.data(using: .utf8)!) }
    func pause() { queue.async { self.scheduler.pause(now: DispatchTime.now().uptimeNanoseconds) } }
    func resume() { queue.async { self.scheduler.resume(now: DispatchTime.now().uptimeNanoseconds) } }
    func step() { queue.async { if self.started && self.scheduler.step() == 1 { self.runOneTic() } } }
    func setVisualization(_ enabled: Bool) { queue.async { self.circuit.visualizationEnabled = enabled } }

    func enqueueKey(pressed: Bool, key: UInt8) {
        inputLock.lock(); defer { inputLock.unlock() }
        if keys.count < 512 { keys.append(KeyEvent(pressed: pressed ? 1 : 0, key: key)) }
    }
    func takeKey(pressed: UnsafeMutablePointer<Int32>, key: UnsafeMutablePointer<UInt8>) -> Int32 {
        inputLock.lock(); defer { inputLock.unlock() }
        guard !keys.isEmpty else { return 0 }
        let event = keys.removeFirst()
        pressed.pointee = event.pressed; key.pointee = event.key
        return 1
    }
    func enqueueMouse(buttons: Int, dx: Int, dy: Int) {
        inputLock.lock(); defer { inputLock.unlock() }
        mouse.buttons = buttons
        mouse.dx = max(-8192, min(8192, mouse.dx + dx))
        mouse.dy = max(-8192, min(8192, mouse.dy + dy))
    }
    private func injectMouse() {
        inputLock.lock()
        let state = mouse
        mouse.dx = 0; mouse.dy = 0
        inputLock.unlock()
        HM_EnginePostMouse(Int32(state.buttons), Int32(state.dx), Int32(state.dy))
    }
}

@_cdecl("HM_EvaluateMovement")
func HM_EvaluateMovementNative(_ input: UnsafePointer<HMMovementInput>?,
                               _ reference: UnsafePointer<HMMovementOutput>?,
                               _ output: UnsafeMutablePointer<HMMovementOutput>?) -> Int32 {
    guard let input, let reference, let output, let circuit = EngineCoordinator.active?.circuit,
          let result = circuit.evaluate(input.pointee, reference: reference.pointee) else { return 0 }
    output.pointee = result
    return 1
}
@_cdecl("HM_HostGetKey")
func HM_HostGetKey(_ pressed: UnsafeMutablePointer<Int32>?, _ key: UnsafeMutablePointer<UInt8>?) -> Int32 {
    guard let pressed, let key else { return 0 }
    return EngineCoordinator.active?.takeKey(pressed: pressed, key: key) ?? 0
}
@_cdecl("HM_HostFrameReady")
func HM_HostFrameReady() {
    guard let pointer = HM_EnginePixels() else { return }
    EngineCoordinator.active?.gameView?.receiveFrame(pointer)
}
@_cdecl("HM_HostSetTitle")
func HM_HostSetTitle(_ title: UnsafePointer<CChar>?) {
    guard let title else { return }
    let name = String(cString: title)
    DispatchQueue.main.async { NSApp.mainWindow?.title = "Handwired Doom — \(name)" }
}
