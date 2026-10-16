import AppKit
import SwiftUI

final class InspectorModel: ObservableObject {
    @Published var trace: CircuitTrace?
    @Published var graph: CircuitGraph?
    @Published var dropped = 0
    @Published var circuitTics = 0
    @Published var domainFallbacks = 0
    @Published var metalFallbacks = 0
    @Published var mismatches = 0
    @Published var fallbackReason = "none"
    @Published var isPaused = false
    weak var engine: EngineCoordinator?
    func publish(trace: CircuitTrace, graph: CircuitGraph, dropped: Int,
                 circuitTics: Int, domainFallbacks: Int, metalFallbacks: Int, mismatches: Int,
                 fallbackReason: String) {
        self.trace = trace; self.graph = graph; self.dropped = dropped
        self.circuitTics = circuitTics; self.domainFallbacks = domainFallbacks
        self.metalFallbacks = metalFallbacks; self.mismatches = mismatches
        self.fallbackReason = fallbackReason
    }
    func refreshCounts(circuitTics: Int, domainFallbacks: Int, metalFallbacks: Int, mismatches: Int,
                       fallbackReason: String) {
        self.circuitTics = circuitTics; self.domainFallbacks = domainFallbacks
        self.metalFallbacks = metalFallbacks; self.mismatches = mismatches
        self.fallbackReason = fallbackReason
    }
    func pause() { isPaused = true; engine?.pause() }
    func resume() { isPaused = false; engine?.resume() }
    func step() { engine?.step() }
}

struct InspectorView: View {
    @ObservedObject var model: InspectorModel
    @State private var selectedOutput = 0
    private let outputs = ["forwardmove", "sidemove", "angleturn", "turnheld"]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CIRCUIT INSPECTOR").font(.system(.headline, design: .monospaced))
            if let trace = model.trace, let graph = model.graph {
                HStack {
                    Text("tic \(trace.tick)")
                    Spacer()
                    Text("\(graph.operationCount) ops · \(graph.layerCount) layers")
                }.font(.system(.caption, design: .monospaced))
                Text(String(format: "Circuit attempt %.3f ms · sampled CPU replay", Double(trace.latencyNs) / 1_000_000))
                    .font(.caption)
                Text("Circuit \(model.circuitTics) · domain fallback \(model.domainFallbacks) · Metal fallback \(model.metalFallbacks) · mismatch \(model.mismatches) · dropped \(model.dropped)")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                Text("Latest fallback: \(model.fallbackReason)").font(.caption)
                HStack {
                    Button("Pause") { model.pause() }.disabled(model.isPaused)
                    Button("Step one tic") { model.step() }.disabled(!model.isPaused)
                    Button("Resume") { model.resume() }.disabled(!model.isPaused)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("LAYERS · heat: log₂ |activation|").font(.system(.caption, design: .monospaced)).bold()
                        ForEach(trace.layers, id: \.id) { layer in
                            HStack(spacing: 5) {
                                Text(String(format: "%02d", layer.id)).frame(width: 24, alignment: .leading)
                                Text("A\(layer.affine) G\(layer.reglu) I\(layer.index)").frame(width: 90, alignment: .leading)
                                HStack(spacing: 1) {
                                    ForEach(0..<8, id: \.self) { bin in
                                        Rectangle().fill(Color.orange.opacity(layer.heat[bin] == 0 ? 0.08 : min(1, Double(layer.heat[bin]) / 5 + 0.2)))
                                            .frame(width: 12, height: 13)
                                    }
                                }
                                Text(String(format: "%d active · G %d/%d · B %d/%d · %.1f µs CPU", layer.nonzero,
                                            layer.gateOpen, layer.reglu, layer.booleanActive, layer.booleanCount,
                                            Double(layer.cpuReplayNs)/1000))
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }.font(.system(size: 10, design: .monospaced))
                        }
                        Divider()
                        Text("REFERENCE C  /  CIRCUIT").font(.system(.caption, design: .monospaced)).bold()
                        comparison("forward", trace.reference.forwardmove, trace.circuit.forwardmove)
                        comparison("side", trace.reference.sidemove, trace.circuit.sidemove)
                        comparison("angle", trace.reference.angleturn, trace.circuit.angleturn)
                        comparison("turnheld", trace.reference.turnheld, trace.circuit.turnheld)
                        Text(trace.changedTurnheld ? "state cell turnheld changed" : "state cell turnheld unchanged").font(.caption)
                        Text("Source FNV64 \(String(trace.sourceHash, radix: 16))").font(.system(size: 10, design: .monospaced))
                        Divider()
                        Picker("Output neighborhood", selection: $selectedOutput) {
                            ForEach(0..<4, id: \.self) { Text(outputs[$0]).tag($0) }
                        }
                        let nodes = model.engine?.circuit.neighborhood(root: selectedOutput, trace: trace) ?? []
                        Text("\(nodes.count) of at most 64 upstream operations · stable IDs").font(.caption)
                        ForEach(nodes, id: \.0.id) { node in
                            Text("#\(node.0.id) L\(node.0.layer) \(node.0.kind) \(node.0.label) = \(Int(node.1))")
                                .font(.system(size: 10, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("Waiting for the first sampled game tic. Move to see circuit activity.")
                HStack {
                    Button("Pause") { model.pause() }
                    Button("Step one tic") { model.step() }.disabled(!model.isPaused)
                    Button("Resume") { model.resume() }
                }
            }
        }.padding(14).frame(minWidth: 530, minHeight: 600)
    }
    private func comparison(_ name: String, _ c: Int32, _ circuit: Int32) -> some View {
        HStack {
            Text(name).frame(width: 90, alignment: .leading)
            Text("\(c)").frame(width: 80, alignment: .trailing)
            Text("→")
            Text("\(circuit)").frame(width: 80, alignment: .trailing)
            Text(c == circuit ? "MATCH" : "MISMATCH").foregroundStyle(c == circuit ? .green : .red)
        }.font(.system(.caption, design: .monospaced))
    }
}

final class InspectorPanel: NSPanel {
    init(model: InspectorModel) {
        super.init(contentRect: NSRect(x: 100, y: 100, width: 580, height: 690),
                   styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        title = "Handwired Doom — Circuit Inspector"
        contentView = NSHostingView(rootView: InspectorView(model: model))
        isReleasedWhenClosed = false
    }
}
