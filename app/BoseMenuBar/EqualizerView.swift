import SwiftUI
import BoseKit

/// Ventana del ecualizador: curva arrastrable + campos numéricos.
///
/// Los valores mostrados son siempre los confirmados por los auriculares
/// (`controller.equalizer`), salvo durante un arrastre, en el que se ve una
/// vista previa local. El comando se envía al soltar, no en cada movimiento.
struct EqualizerView: View {
    @ObservedObject var controller: HeadphonesController

    /// `@State` es estado local de la vista (lo conserva SwiftUI entre redibujados).
    @State private var dragging: (band: UInt8, value: Int)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !controller.isConnected {
                placeholder("Sin conexión con los auriculares.")
            } else if controller.equalizer.isEmpty {
                placeholder("Leyendo el ecualizador…")
            } else {
                EQCurveView(
                    bands: controller.equalizer.map { band in
                        (band, dragging?.band == band.index ? dragging!.value : band.value)
                    },
                    onDrag: { band, value in dragging = (band, value) },
                    onDragEnd: { band, value in
                        dragging = nil
                        controller.setEqualizer(band: band, value: value)
                    }
                )
                .frame(height: 220)

                HStack(alignment: .top, spacing: 24) {
                    ForEach(controller.equalizer, id: \.index) { band in
                        BandField(name: Self.name(of: band.index), band: band,
                                  shownValue: dragging?.band == band.index ? dragging!.value : band.value) {
                            controller.setEqualizer(band: band.index, value: $0)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    static func name(of index: UInt8) -> String {
        HeadphonesController.eqBandNames[index] ?? "Banda \(index)"
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 220)
    }
}

/// Campo numérico + botones −/+ de una banda.
private struct BandField: View {
    let name: String
    let band: EQBand
    let shownValue: Int
    let onCommit: (Int) -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text(name).font(.headline)
            HStack(spacing: 4) {
                // El TextField con `format:` solo escribe en el binding al pulsar
                // Intro o al salir del campo, así que no se envía nada a medio teclear.
                TextField("", value: Binding(get: { shownValue }, set: { onCommit(clamp($0)) }),
                          format: .number)
                    .multilineTextAlignment(.center)
                    .frame(width: 48)
                Stepper("", value: Binding(get: { shownValue }, set: { onCommit(clamp($0)) }),
                        in: band.min...band.max)
                    .labelsHidden()
            }
            Text("\(band.min)…\(band.max)").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func clamp(_ v: Int) -> Int { Swift.min(Swift.max(v, band.min), band.max) }
}

/// Gráfica de la curva. Cada banda es un punto que se arrastra en vertical.
private struct EQCurveView: View {
    /// Pares (banda, valor a mostrar).
    let bands: [(EQBand, Int)]
    let onDrag: (UInt8, Int) -> Void
    let onDragEnd: (UInt8, Int) -> Void

    @State private var activeBand: UInt8?

    private var range: ClosedRange<Int> {
        let lo = bands.map { $0.0.min }.min() ?? -10
        let hi = bands.map { $0.0.max }.max() ?? 10
        return lo...hi
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let points = bands.enumerated().map { i, b in point(index: i, value: b.1, in: size) }

            ZStack {
                grid(in: size)

                // Curva suave: curvas de Bézier con tangentes horizontales en cada
                // punto, prolongada en horizontal hasta los bordes.
                Path { p in
                    guard let first = points.first, let last = points.last else { return }
                    p.move(to: CGPoint(x: 0, y: first.y))
                    p.addLine(to: first)
                    for (a, b) in zip(points, points.dropFirst()) {
                        let midX = (a.x + b.x) / 2
                        p.addCurve(to: b, control1: CGPoint(x: midX, y: a.y), control2: CGPoint(x: midX, y: b.y))
                    }
                    p.addLine(to: CGPoint(x: size.width, y: last.y))
                }
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

                ForEach(Array(bands.enumerated()), id: \.element.0.index) { i, b in
                    let pt = points[i]
                    Circle()
                        .fill(activeBand == b.0.index ? Color.accentColor : Color(nsColor: .windowBackgroundColor))
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: 2.5))
                        .frame(width: 16, height: 16)
                        .position(pt)
                    Text(signed(b.1))
                        .font(.caption.monospacedDigit())
                        .position(x: pt.x, y: pt.y - 18)
                    Text(EqualizerView.name(of: b.0.index))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .position(x: pt.x, y: size.height - 8)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        // Al empezar, se elige la banda más cercana en horizontal.
                        if activeBand == nil {
                            activeBand = nearestBand(toX: g.startLocation.x, width: size.width)
                        }
                        if let band = activeBand { onDrag(band, value(atY: g.location.y, height: size.height)) }
                    }
                    .onEnded { g in
                        if let band = activeBand { onDragEnd(band, value(atY: g.location.y, height: size.height)) }
                        activeBand = nil
                    }
            )
        }
    }

    // MARK: - Geometría

    private let verticalPadding: CGFloat = 26

    private func point(index i: Int, value: Int, in size: CGSize) -> CGPoint {
        CGPoint(x: (CGFloat(i) + 0.5) / CGFloat(bands.count) * size.width, y: y(for: value, height: size.height))
    }

    private func y(for value: Int, height: CGFloat) -> CGFloat {
        let span = CGFloat(range.upperBound - range.lowerBound)
        let t = CGFloat(value - range.lowerBound) / span            // 0 abajo, 1 arriba
        return verticalPadding + (1 - t) * (height - 2 * verticalPadding)
    }

    private func value(atY y: CGFloat, height: CGFloat) -> Int {
        let t = 1 - (y - verticalPadding) / (height - 2 * verticalPadding)
        let raw = CGFloat(range.lowerBound) + t * CGFloat(range.upperBound - range.lowerBound)
        return min(max(Int(raw.rounded()), range.lowerBound), range.upperBound)
    }

    private func nearestBand(toX x: CGFloat, width: CGFloat) -> UInt8? {
        let i = min(max(Int(x / width * CGFloat(bands.count)), 0), bands.count - 1)
        return bands.isEmpty ? nil : bands[i].0.index
    }

    private func grid(in size: CGSize) -> some View {
        let marks = stride(from: range.lowerBound, through: range.upperBound, by: 5).map { $0 }
        return ZStack {
            ForEach(marks, id: \.self) { v in
                let y = y(for: v, height: size.height)
                Path { p in
                    p.move(to: CGPoint(x: 28, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                }
                .stroke(Color.secondary.opacity(v == 0 ? 0.6 : 0.25),
                        style: StrokeStyle(lineWidth: 1, dash: v == 0 ? [] : [3, 3]))
                Text(signed(v))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .position(x: 12, y: y)
            }
        }
    }

    private func signed(_ v: Int) -> String { v > 0 ? "+\(v)" : "\(v)" }
}
