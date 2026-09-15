// Рисует иконку Folio 1024×1024: системный скруглённый квадрат, две страницы и цветная панель как в Confluence.
// Использование: swift Scripts/make-icon.swift Assets/AppIcon-1024.png
import AppKit

let outputPath = CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png"
let canvas = 1024
let tileRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let tileRadius: CGFloat = 186

let tealLight = NSColor(srgbRed: 0.22, green: 0.80, blue: 0.72, alpha: 1)
let tealDark = NSColor(srgbRed: 0.03, green: 0.44, blue: 0.54, alpha: 1)
let ink = NSColor(srgbRed: 0.04, green: 0.47, blue: 0.53, alpha: 1)
let titleInk = NSColor(white: 0.27, alpha: 1)
let lineInk = NSColor(white: 0.80, alpha: 1)

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Не удалось создать холст")
}

func withShadow(alpha: CGFloat, blur: CGFloat, offset: NSSize, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(alpha)
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = offset
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

/// Лист со скруглёнными углами и срезанным правым верхним углом под загнутый край.
func pagePath(_ rect: NSRect, radius: CGFloat, fold: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: rect.minX + radius, y: rect.minY))
    path.line(to: NSPoint(x: rect.maxX - radius, y: rect.minY))
    path.appendArc(from: NSPoint(x: rect.maxX, y: rect.minY), to: NSPoint(x: rect.maxX, y: rect.minY + radius), radius: radius)
    if fold > 0 {
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - fold))
        path.line(to: NSPoint(x: rect.maxX - fold, y: rect.maxY))
    } else {
        path.appendArc(from: NSPoint(x: rect.maxX, y: rect.maxY), to: NSPoint(x: rect.maxX - radius, y: rect.maxY), radius: radius)
    }
    path.appendArc(from: NSPoint(x: rect.minX, y: rect.maxY), to: NSPoint(x: rect.minX, y: rect.maxY - radius), radius: radius)
    path.appendArc(from: NSPoint(x: rect.minX, y: rect.minY), to: NSPoint(x: rect.minX + radius, y: rect.minY), radius: radius)
    path.close()
    return path
}

func bar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: height), xRadius: height / 2, yRadius: height / 2).fill()
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high

// Плитка.
let tile = NSBezierPath(roundedRect: tileRect, xRadius: tileRadius, yRadius: tileRadius)
withShadow(alpha: 0.22, blur: 28, offset: NSSize(width: 0, height: -12)) {
    NSColor.white.setFill()
    tile.fill()
}
NSGradient(starting: tealLight, ending: tealDark)?.draw(in: tile, angle: -90)
NSGraphicsContext.saveGraphicsState()
tile.addClip()
NSGradient(starting: NSColor.white.withAlphaComponent(0.26), ending: NSColor.white.withAlphaComponent(0))?
    .draw(in: NSRect(x: tileRect.minX, y: tileRect.midY, width: tileRect.width, height: tileRect.height / 2), angle: -90)
NSGraphicsContext.restoreGraphicsState()

// Задний лист, чуть повёрнут.
let frontRect = NSRect(x: 336, y: 226, width: 420, height: 534)
let backRect = frontRect.offsetBy(dx: -96, dy: 30)
NSGraphicsContext.saveGraphicsState()
let rotation = NSAffineTransform()
rotation.translateX(by: backRect.midX, yBy: backRect.midY)
rotation.rotate(byDegrees: 8)
rotation.translateX(by: -backRect.midX, yBy: -backRect.midY)
rotation.concat()
withShadow(alpha: 0.12, blur: 24, offset: NSSize(width: 0, height: -8)) {
    NSColor.white.withAlphaComponent(0.55).setFill()
    pagePath(backRect, radius: 40, fold: 0).fill()
}
NSGraphicsContext.restoreGraphicsState()

// Передний лист.
let foldSize: CGFloat = 104
let front = pagePath(frontRect, radius: 40, fold: foldSize)
withShadow(alpha: 0.24, blur: 36, offset: NSSize(width: 0, height: -16)) {
    NSColor.white.setFill()
    front.fill()
}
NSGradient(starting: NSColor.white, ending: NSColor(white: 0.94, alpha: 1))?.draw(in: front, angle: -90)

// Загнутый угол.
let fold = NSBezierPath()
fold.move(to: NSPoint(x: frontRect.maxX - foldSize, y: frontRect.maxY))
fold.appendArc(
    from: NSPoint(x: frontRect.maxX - foldSize, y: frontRect.maxY - foldSize),
    to: NSPoint(x: frontRect.maxX, y: frontRect.maxY - foldSize),
    radius: 22
)
fold.line(to: NSPoint(x: frontRect.maxX, y: frontRect.maxY - foldSize))
fold.close()
withShadow(alpha: 0.20, blur: 14, offset: NSSize(width: -4, height: -8)) {
    NSColor(white: 0.90, alpha: 1).setFill()
    fold.fill()
}
NSGradient(starting: NSColor(white: 0.97, alpha: 1), ending: NSColor(white: 0.84, alpha: 1))?.draw(in: fold, angle: -45)

// Заголовок, панель и строки текста.
let left = frontRect.minX + 54
bar(x: left, y: frontRect.maxY - 150, width: 196, height: 36, color: titleInk)

let panel = NSRect(x: frontRect.minX + 44, y: frontRect.maxY - 296, width: 332, height: 108)
tealLight.withAlphaComponent(0.22).setFill()
NSBezierPath(roundedRect: panel, xRadius: 24, yRadius: 24).fill()
ink.setFill()
NSBezierPath(ovalIn: NSRect(x: panel.minX + 24, y: panel.midY - 18, width: 36, height: 36)).fill()
bar(x: panel.minX + 80, y: panel.midY + 6, width: 206, height: 18, color: ink.withAlphaComponent(0.60))
bar(x: panel.minX + 80, y: panel.midY - 24, width: 146, height: 18, color: ink.withAlphaComponent(0.38))

bar(x: left, y: frontRect.maxY - 356, width: 312, height: 24, color: lineInk)
bar(x: left, y: frontRect.maxY - 402, width: 272, height: 24, color: lineInk)
bar(x: left, y: frontRect.maxY - 448, width: 190, height: 24, color: lineInk)

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Не удалось закодировать PNG")
}
try png.write(to: URL(fileURLWithPath: outputPath))
print("иконка: \(outputPath)")
