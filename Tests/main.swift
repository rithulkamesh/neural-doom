import Foundation
import Metal
import CryptoKit

struct Generator {
    var state: UInt64 = 0x9e3779b97f4a7c15
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
    mutating func span(_ width: UInt64) -> Int32 { Int32(next() % width) }
    mutating func snapshot() -> HMMovementInput {
        var c = [Int32](repeating: 0, count: 24)
        for i in 0...12 { c[i] = span(2) }
        c[13] = span(513) - 256
        c[14] = span(16385) - 8192
        for i in 15...17 { c[i] = span(2) }
        for i in 18...20 { c[i] = span(3) - 1 }
        c[21] = span(16_777_213)
        c[22] = span(4) + 1
        return CircuitRuntime.input(c)
    }
}
func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
func same(_ a: HMMovementOutput, _ b: HMMovementOutput) -> Bool {
    a.forwardmove == b.forwardmove && a.sidemove == b.sidemove && a.angleturn == b.angleturn && a.turnheld == b.turnheld
}
func percentile(_ xs: [UInt64], _ p: Double) -> Double {
    let ordered = xs.sorted()
    return Double(ordered[min(ordered.count-1, Int(Double(ordered.count-1)*p))]) / 1_000_000
}
let graph = CircuitGraph()
if let at = CommandLine.arguments.firstIndex(of: "--app-bundle"), at + 1 < CommandLine.arguments.count {
    let app = URL(fileURLWithPath: CommandLine.arguments[at+1], isDirectory: true)
    guard let bundle = Bundle(url: app),
          let wad = bundle.url(forResource: "freedoom1", withExtension: "wad"),
          let notice = bundle.url(forResource: "FREEDOOM-COPYING", withExtension: "txt"),
          let credits = bundle.url(forResource: "FREEDOOM-CREDITS", withExtension: "txt") else {
        fputs("FAIL: clean app is missing a bundled IWAD or attribution\n", stderr); exit(1)
    }
    require(!wad.path.contains("/Sources/"), "IWAD resolved from source tree")
    require(IWADValidator.error(for: wad) == nil, "bundled IWAD failed readability/header/directory validation")
    let data = try Data(contentsOf: wad)
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    require(digest == "7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d", "bundled IWAD checksum changed")
    let licenseText = try String(contentsOf: notice)
    let creditsText = try String(contentsOf: credits)
    require(licenseText.contains("Redistribution and use"), "Freedoom license missing")
    require(creditsText.contains("Freedoom"), "Freedoom credits missing")
    print("clean app bundle: IWAD resolves outside source tree, header/directory readable, SHA-256 \(digest), license and credits present")
    exit(0)
}
if CommandLine.arguments.contains("--emit-manifest") {
    let path = CommandLine.arguments.last!
    try graph.manifestJSON().write(to: URL(fileURLWithPath: path))
    print("manifest: \(graph.operationCount) operations, \(graph.layerCount) layers")
    exit(0)
}
let committedManifest = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Docs/locomotion-graph.json")
require((try? Data(contentsOf: committedManifest)) == graph.manifestJSON(), "generated graph manifest is stale")
require(graph.operationCount <= 232, "frozen graph exceeds 256-cell Metal scratch bound")
require(graph.liveOperationCount == graph.operationCount, "manifest counts dead builder allocations")
require(MemoryLayout<CircuitOp>.stride == 32, "operation ABI is not 32 bytes")
guard MTLCreateSystemDefaultDevice() != nil else { fputs("FAIL: Apple Silicon Metal device unavailable\n", stderr); exit(1) }
let circuit = CircuitRuntime(deadlineNs: 1_000_000_000)
var generator = Generator()
var cpuMismatch = 0, metalMismatch = 0, extractionMismatch = 0
let total = CommandLine.arguments.contains("--quick") ? 1000 : 100_000
let start = DispatchTime.now().uptimeNanoseconds
for i in 0..<total {
    let input = generator.snapshot()
    var copy = input
    require(HM_InputInDomain(&copy) == 1, "generated input outside domain")
    let reference = HM_TestOriginalMovement(&copy)
    let extraction = HM_ReferenceMovement(&copy)
    if !same(reference, extraction) {
        extractionMismatch += 1
        if extractionMismatch < 4 { print("C extraction mismatch at \(i): \(reference) vs \(extraction)") }
    }
    let (cpu, _) = circuit.cpu(input)
    if !same(reference, cpu) {
        cpuMismatch += 1
        if cpuMismatch < 4 { print("CPU mismatch at \(i): \(reference) vs \(cpu)") }
    }
    guard let (gpu, _) = circuit.metal(input) else { fputs("FAIL: Metal command failed at \(i)\n", stderr); exit(1) }
    if !same(reference, gpu) {
        metalMismatch += 1
        if metalMismatch < 4 { print("Metal mismatch at \(i): \(reference) vs \(gpu)") }
    }
}
require(cpuMismatch == 0 && metalMismatch == 0 && extractionMismatch == 0, "locomotion parity")
let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000

// Domain boundary rejects every invalid category before GPU submission.
var domainChecks = 0
for (at, value) in [(0,2), (13,257), (13,-257), (14,8193), (14,-8193),
                    (18,2), (21,-1), (21,16_777_213), (22,0), (22,5)] {
    var c = [Int32](repeating: 0, count: 24); c[22] = 1; c[at] = Int32(value)
    var input = CircuitRuntime.input(c)
    require(HM_InputInDomain(&input) == 0, "domain accepted cell \(at)=\(value)")
    domainChecks += 1
}

let ring = TraceRing(capacity: 128)
let dummy = HMMovementOutput(forwardmove: 0, sidemove: 0, angleturn: 0, turnheld: 0)
for i in 0..<1000 {
    ring.append(CircuitTrace(tick: i, sourceHash: 0, capturedNs: 0, circuit: dummy,
                             reference: dummy, latencyNs: 0, fallback: nil, layers: [],
                             values: [], changedTurnheld: false))
}
require(ring.items.count == 128 && ring.dropped == 872 && ring.items.first?.tick == 872, "ring bounds/drops")

var scheduler = TicScheduler()
let period = scheduler.periodNs
require(scheduler.due(now: 0) == 0, "scheduler initial tick")
require(scheduler.due(now: period * 3) == 3, "three tics in one presented frame")
scheduler.pause(now: period * 3)
require(scheduler.due(now: period * 200) == 0, "paused engine advanced")
require(scheduler.step() == 1 && scheduler.step() == 1, "step did not yield one tic per invocation")
scheduler.resume(now: period * 200)
require(scheduler.due(now: period * 200) == 0, "resume caught up paused wall time")
require(scheduler.due(now: period * 201) == 1, "resume did not yield next tic")
require(scheduler.step() == 0, "step ran when not paused")

// Visualization samples are a replay of the already committed values.
var vizChecks = 0
for _ in 0..<1000 {
    let input = generator.snapshot()
    let (off, offTrace) = circuit.cpu(input, trace: false)
    let (on, onTrace) = circuit.cpu(input, trace: true)
    require(same(off, on) && offTrace.isEmpty && onTrace.count == 24 + graph.operationCount,
            "visualization changed outputs or wrote off-mode trace")
    vizChecks += 1
}
let live = CircuitRuntime(deadlineNs: 1_000_000_000)
for _ in 0..<8 {
    var input = generator.snapshot()
    let reference = HM_TestOriginalMovement(&input)
    require(live.evaluate(input, reference: reference) != nil, "off-mode circuit did not own command")
}
require(live.traces.items.isEmpty, "visualization-off wrote operation trace")
live.visualizationEnabled = true
for _ in 0..<16 {
    var input = generator.snapshot()
    let reference = HM_TestOriginalMovement(&input)
    require(live.evaluate(input, reference: reference) != nil, "on-mode circuit changed result")
}
require(live.traces.items.count == 4, "sample rate is not one trace in four tics")
for trace in live.traces.items {
    require(!trace.mismatch && trace.layers.count == graph.layerCount, "live layer/compare telemetry")
    require(trace.values.count == 24 + graph.operationCount, "live sampled values missing")
    for root in 0..<4 { require(live.neighborhood(root: root, trace: trace).count <= 64, "drill-down exceeded 64 operations") }
}
var invalid = [Int32](repeating: 0, count: 24); invalid[22] = 1; invalid[13] = 257
let rejected = CircuitRuntime.input(invalid)
let previousCircuitTics = live.circuitTics
require(live.evaluate(rejected, reference: dummy) == nil && live.domainFallbacks == 1
        && live.circuitTics == previousCircuitTics, "live domain fallback dispatched circuit")
let failedMetal = CircuitRuntime(device: nil)
var valid = CircuitRuntime.input([Int32](repeating: 0, count: 22) + [1, 0])
let fallbackReference = HM_TestOriginalMovement(&valid)
require(failedMetal.evaluate(valid, reference: fallbackReference) == nil && failedMetal.metalFallbacks == 1,
        "Metal failure did not select reference fallback")
let expiredDeadline = CircuitRuntime(deadlineNs: 0)
require(expiredDeadline.evaluate(valid, reference: fallbackReference) == nil
        && expiredDeadline.metalFallbacks == 1 && expiredDeadline.lastFallback == "metal-timeout",
        "expired Metal deadline did not select reference fallback")
let stalledWorker = CircuitRuntime(deadlineNs: 2_000_000, workerDelayNs: 50_000_000)
require(stalledWorker.evaluate(valid, reference: fallbackReference) == nil
        && stalledWorker.metalFallbacks == 1 && stalledWorker.lastFallback == "metal-timeout"
        && stalledWorker.circuitTics == 0,
        "stalled Metal encoding did not select same-tic reference fallback")
print("parity: \(total) generated snapshots versus original G_BuildTiccmd, C extraction mismatches \(extractionMismatch), CPU mismatches \(cpuMismatch), Metal mismatches \(metalMismatch)")
print("domain: \(domainChecks) rejected invalid snapshots + live domain/Metal fallbacks; ring: 1000 appends, capacity 128, drops \(ring.dropped); pause/step: 7 assertions; visualization: \(vizChecks) invariant checks + 24 live tics / 4 sampled traces")
print(String(format: "batch %.2f s; graph %d ops, %d layers", elapsed, graph.operationCount, graph.layerCount))

// Warm, isolated synchronous submit/wait distribution; in-game pacing is
// reported by the run trace separately, never inferred from this probe.
var ns: [UInt64] = []
let sample = generator.snapshot()
for _ in 0..<100 { _ = circuit.metal(sample) }
for _ in 0..<1000 { if let (_, t) = circuit.metal(sample) { ns.append(t) } }
require(ns.count == 1000, "latency sample count")
print(String(format: "Metal sync latency (1000 warm samples, ms): median %.3f p95 %.3f p99 %.3f", percentile(ns, 0.5), percentile(ns, 0.95), percentile(ns, 0.99)))
