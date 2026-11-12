// Рисует иконку Notch Panel (1024×1024) и собирает AppIcon.icns.
// Запуск: swift Icon/make-icon.swift  (из папки проекта)
import AppKit

let size: CGFloat = 1024
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Icon/icon_1024.png")

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

// Координаты как на экране: y вниз.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

// 1. Основа — «сквиркл» macOS (824×824 в поле 1024) с тенью.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 36, color: color(0x000000, 0.45))
ctx.addPath(bodyPath); ctx.setFillColor(color(0x1b1b20)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(bodyPath); ctx.clip()
// Фон: графитовый градиент сверху вниз.
let bg = CGGradient(colorsSpace: nil, colors: [color(0x34343c), color(0x121216)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
// Мягкое свечение под островком.
let glow = CGGradient(colorsSpace: nil, colors: [color(0x5ac8fa, 0.22), color(0x5ac8fa, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 430), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 430), endRadius: 420, options: [])

// 2. Островок, «вытекающий» из верхнего края (как раскрытая шторка под чёлкой).
let island = CGRect(x: 232, y: 100, width: 560, height: 470)
let r: CGFloat = 120
let p = CGMutablePath()
p.move(to: CGPoint(x: island.minX - 40, y: island.minY))
// маленькие внешние скругления у верхнего края, как у настоящей чёлки
p.addQuadCurve(to: CGPoint(x: island.minX, y: island.minY + 40), control: CGPoint(x: island.minX, y: island.minY))
p.addLine(to: CGPoint(x: island.minX, y: island.maxY - r))
p.addArc(tangent1End: CGPoint(x: island.minX, y: island.maxY), tangent2End: CGPoint(x: island.minX + r, y: island.maxY), radius: r)
p.addLine(to: CGPoint(x: island.maxX - r, y: island.maxY))
p.addArc(tangent1End: CGPoint(x: island.maxX, y: island.maxY), tangent2End: CGPoint(x: island.maxX, y: island.maxY - r), radius: r)
p.addLine(to: CGPoint(x: island.maxX, y: island.minY + 40))
p.addQuadCurve(to: CGPoint(x: island.maxX + 40, y: island.minY), control: CGPoint(x: island.maxX, y: island.minY))
p.closeSubpath()

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 40, color: color(0x000000, 0.6))
ctx.addPath(p); ctx.setFillColor(color(0x000000)); ctx.fillPath()
ctx.restoreGState()
// Тонкий блик по краю островка.
ctx.addPath(p); ctx.setStrokeColor(color(0xffffff, 0.08)); ctx.setLineWidth(3); ctx.strokePath()

// 3. Три полоски-показателя внутри островка.
let bars: [(UInt32, CGFloat)] = [(0x34c759, 0.78), (0xffd60a, 0.55), (0xff9f0a, 0.36)]
let barX: CGFloat = 300, barW: CGFloat = 330, barH: CGFloat = 40
for (i, (hex, frac)) in bars.enumerated() {
    let y = 250 + CGFloat(i) * 82
    let track = CGPath(roundedRect: CGRect(x: barX, y: y, width: barW, height: barH),
                       cornerWidth: barH / 2, cornerHeight: barH / 2, transform: nil)
    ctx.addPath(track); ctx.setFillColor(color(0xffffff, 0.09)); ctx.fillPath()
    let fill = CGPath(roundedRect: CGRect(x: barX, y: y, width: barW * frac, height: barH),
                      cornerWidth: barH / 2, cornerHeight: barH / 2, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 22, color: color(hex, 0.85))
    ctx.addPath(fill); ctx.setFillColor(color(hex)); ctx.fillPath()
    ctx.restoreGState()
}

// 4. Искра Claude справа от полосок.
func sparkle(center c: CGPoint, radius R: CGFloat) -> CGPath {
    let s = CGMutablePath()
    let inner = R * 0.22
    for k in 0..<8 {
        let a = CGFloat(k) * .pi / 4 - .pi / 2
        let rr = k % 2 == 0 ? R : inner * 1.6
        let pt = CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr)
        if k == 0 { s.move(to: pt) } else {
            let mid = CGFloat(k) * .pi / 4 - .pi / 2 - .pi / 8
            s.addQuadCurve(to: pt, control: CGPoint(x: c.x + cos(mid) * inner, y: c.y + sin(mid) * inner))
        }
    }
    let mid = -CGFloat.pi / 2 - CGFloat.pi / 8
    s.addQuadCurve(to: CGPoint(x: c.x, y: c.y - R), control: CGPoint(x: c.x + cos(mid) * inner, y: c.y + sin(mid) * inner))
    s.closeSubpath()
    return s
}
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 26, color: color(0xd97757, 0.9))
ctx.addPath(sparkle(center: CGPoint(x: 700, y: 332), radius: 62))
ctx.setFillColor(color(0xd97757)); ctx.fillPath()
ctx.restoreGState()

// 5. Лёгкий стеклянный блик сверху всей иконки.
let sheen = CGGradient(colorsSpace: nil, colors: [color(0xffffff, 0.10), color(0xffffff, 0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 420), options: [])
ctx.restoreGState()

// Обводка сквиркла.
ctx.addPath(bodyPath); ctx.setStrokeColor(color(0xffffff, 0.10)); ctx.setLineWidth(2); ctx.strokePath()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("PNG:", out.path)
