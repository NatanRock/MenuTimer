// Рисует иконку приложения и собирает Resources/AppIcon.icns.
// Запуск: swift tools/make_icon.swift   (из корня проекта)
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func makeIcon(size: CGFloat) -> CGImage? {
    let pixels = Int(size)
    guard let ctx = CGContext(
        data: nil, width: pixels, height: pixels,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // Корпус: скруглённый квадрат с вертикальным градиентом
    let inset = size * 0.055
    let body = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = body.width * 0.225
    let bodyPath = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [
            CGColor(red: 0.27, green: 0.29, blue: 0.33, alpha: 1),
            CGColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1)
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: body.midX, y: body.maxY),
        end: CGPoint(x: body.midX, y: body.minY),
        options: []
    )
    ctx.restoreGState()

    // Блик по верхней кромке
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
    ctx.setLineWidth(size * 0.012)
    ctx.strokePath()
    ctx.restoreGState()

    let center = CGPoint(x: size * 0.5, y: size * 0.455)
    let dial = size * 0.245
    let ring = size * 0.058

    // Коронка секундомера
    let crownWidth = size * 0.13
    let crownHeight = size * 0.075
    let crown = CGRect(
        x: center.x - crownWidth / 2,
        y: center.y + dial + ring * 0.1,
        width: crownWidth,
        height: crownHeight
    )
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.92))
    ctx.addPath(CGPath(
        roundedRect: crown,
        cornerWidth: crownHeight * 0.35,
        cornerHeight: crownHeight * 0.35,
        transform: nil
    ))
    ctx.fillPath()

    // Циферблат: белое кольцо
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.92))
    ctx.setLineWidth(ring)
    ctx.addArc(center: center, radius: dial, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    // Красная дуга — «прошедшая» четверть, от 12 часов по часовой стрелке
    ctx.setStrokeColor(CGColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1))
    ctx.setLineWidth(ring)
    ctx.setLineCap(.round)
    ctx.addArc(center: center, radius: dial, startAngle: .pi / 2, endAngle: 0, clockwise: true)
    ctx.strokePath()
    ctx.setLineCap(.butt)

    // Стрелка вверх и центральная точка
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.92))
    ctx.setLineWidth(size * 0.045)
    ctx.setLineCap(.round)
    ctx.move(to: center)
    ctx.addLine(to: CGPoint(x: center.x, y: center.y + dial * 0.62))
    ctx.strokePath()
    ctx.setLineCap(.butt)

    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.addArc(center: center, radius: size * 0.035, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.fillPath()

    return ctx.makeImage()
}

func write(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("не удалось создать \(url.lastPathComponent)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(String, CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, size) in variants {
    guard let image = makeIcon(size: size) else { fatalError("не отрисовалось \(name)") }
    write(image, to: iconset.appendingPathComponent(name))
}

let icns = root.appendingPathComponent("Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else { fatalError("iconutil завершился с кодом \(task.terminationStatus)") }

print("готово: Resources/AppIcon.icns")
