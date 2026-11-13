// 앱 아이콘 생성 스크립트 — iconset 디렉토리에 PNG 세트를 출력
// 사용법: swift make-icon.swift <output.iconset>
import AppKit

let outDir = CommandLine.arguments[1]

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let size = CGFloat(px)
    let inset = size * 0.05
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.21, yRadius: size * 0.21)

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.11, green: 0.69, blue: 0.84, alpha: 1),   // 청록
        NSColor(calibratedRed: 0.30, green: 0.32, blue: 0.92, alpha: 1),   // 인디고
    ])!
    gradient.draw(in: path, angle: -65)

    let stroke = size * 0.052
    NSColor.white.withAlphaComponent(0.95).setStroke()

    // 집 — 지붕 + 몸체 (생활)
    let house = NSBezierPath()
    house.lineWidth = stroke
    house.lineCapStyle = .round
    house.lineJoinStyle = .round
    house.move(to: NSPoint(x: size * 0.22, y: size * 0.52))
    house.line(to: NSPoint(x: size * 0.50, y: size * 0.75))
    house.line(to: NSPoint(x: size * 0.78, y: size * 0.52))
    house.stroke()

    let body = NSBezierPath()
    body.lineWidth = stroke
    body.lineCapStyle = .round
    body.lineJoinStyle = .round
    body.move(to: NSPoint(x: size * 0.295, y: size * 0.555))
    body.line(to: NSPoint(x: size * 0.295, y: size * 0.25))
    body.line(to: NSPoint(x: size * 0.705, y: size * 0.25))
    body.line(to: NSPoint(x: size * 0.705, y: size * 0.555))
    body.stroke()

    // 상승 차트 라인 — 집 안 (자산)
    let line = NSBezierPath()
    line.lineWidth = stroke
    line.lineCapStyle = .round
    line.lineJoinStyle = .round
    line.move(to: NSPoint(x: size * 0.37, y: size * 0.345))
    line.line(to: NSPoint(x: size * 0.46, y: size * 0.445))
    line.line(to: NSPoint(x: size * 0.54, y: size * 0.385))
    line.line(to: NSPoint(x: size * 0.63, y: size * 0.49))
    line.stroke()

    // 화살표 머리
    let arrow = NSBezierPath()
    arrow.lineWidth = stroke
    arrow.lineCapStyle = .round
    arrow.move(to: NSPoint(x: size * 0.63, y: size * 0.49))
    arrow.line(to: NSPoint(x: size * 0.555, y: size * 0.49))
    arrow.move(to: NSPoint(x: size * 0.63, y: size * 0.49))
    arrow.line(to: NSPoint(x: size * 0.63, y: size * 0.415))
    arrow.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let entries: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for (name, px) in entries {
    try! render(px).write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}
print("아이콘 생성 완료: \(entries.count)개")
