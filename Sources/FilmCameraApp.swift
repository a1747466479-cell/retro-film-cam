import SwiftUI
import AVFoundation
import AVKit
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreHaptics
import Photos
import UniformTypeIdentifiers
import AudioToolbox

// MARK: - 1. 胶卷画幅 (135全画幅 vs 120中画幅) 与胶卷型号模型
enum FilmFormat: String, Codable, CaseIterable, Identifiable {
    case mm135 = "135 全画幅 (3:2 横向齿孔)"
    case medium120 = "120 中画幅 (6x6 哈苏方画幅)"
    var id: String { rawValue }
}

struct FocalLensOption: Identifiable, Equatable {
    let id: String
    let mmLabel: String
    let subLabel: String
    // 对应 iPhone 16 Pro builtInTripleCamera 的硬件/光学变焦倍数 (0.5x 基准为 1.0, 1x 主摄为 2.0, 5x 长焦为 10.0)
    let tripleCameraZoomFactor: CGFloat
    let singleCameraZoomFactor: CGFloat

    static let iPhone16ProLenses: [FocalLensOption] = [
        FocalLensOption(id: "13mm", mmLabel: "13mm", subLabel: "0.5x 超广", tripleCameraZoomFactor: 1.0, singleCameraZoomFactor: 1.0),
        FocalLensOption(id: "24mm", mmLabel: "24mm", subLabel: "1x 主摄", tripleCameraZoomFactor: 2.0, singleCameraZoomFactor: 1.0),
        FocalLensOption(id: "28mm", mmLabel: "28mm", subLabel: "1.2x 街拍", tripleCameraZoomFactor: 2.34, singleCameraZoomFactor: 1.17),
        FocalLensOption(id: "35mm", mmLabel: "35mm", subLabel: "1.5x 人文", tripleCameraZoomFactor: 2.92, singleCameraZoomFactor: 1.46),
        FocalLensOption(id: "50mm", mmLabel: "50mm", subLabel: "2x 标头", tripleCameraZoomFactor: 4.0, singleCameraZoomFactor: 2.0),
        FocalLensOption(id: "120mm", mmLabel: "120mm", subLabel: "5x 长焦", tripleCameraZoomFactor: 10.0, singleCameraZoomFactor: 5.0)
    ]
}

struct FilmStock: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var subtitle: String
    var edgeCode: String
    var iso: Int
    var themeColorHex: String
    var defaultFormat: FilmFormat = .mm135
    var customCubeFileName: String?
    var cubeDimension: Int?

    static let builtInStocks: [FilmStock] = [
        FilmStock(id: "fuji_pro400h", name: "Fuji Pro 400H", subtitle: "传奇人像 · 清透青绿与柔粉肤色", edgeCode: "FUJI PRO 400H", iso: 400, themeColorHex: "#2EC4B6", defaultFormat: .mm135),
        FilmStock(id: "kodak_ektar100", name: "Kodak Ektar 100", subtitle: "风光之王 · 极致细腻高饱和", edgeCode: "KODAK EKTAR 100", iso: 100, themeColorHex: "#E71D36", defaultFormat: .mm135),
        FilmStock(id: "kodak_gold200", name: "Kodak 金 200", subtitle: "复古金黄 · 温暖午后阳光感", edgeCode: "KODAK GOLD 200", iso: 200, themeColorHex: "#FFB703", defaultFormat: .mm135),
        FilmStock(id: "fuji_c200", name: "富士 C200", subtitle: "日系青绿 · 街拍绿植", edgeCode: "HONGSHUXIA C200", iso: 200, themeColorHex: "#1E7A4C", defaultFormat: .mm135),
        FilmStock(id: "kodak_portra400", name: "柯达 Portra 400", subtitle: "暖调人像 · 柔和肤色", edgeCode: "HONGSHUXIA PORTRA", iso: 400, themeColorHex: "#E09F3E", defaultFormat: .mm135),
        FilmStock(id: "cinestill_800t", name: "Cinestill 800T", subtitle: "电影夜景 · 高光红晕", edgeCode: "HONGSHUXIA 800T", iso: 800, themeColorHex: "#C1292E", defaultFormat: .mm135),
        FilmStock(id: "ilford_hp5", name: "伊尔福 HP5", subtitle: "高反差黑白 · 粗颗粒", edgeCode: "HONGSHUXIA HP5", iso: 400, themeColorHex: "#6C757D", defaultFormat: .mm135),
        FilmStock(id: "agfa_100", name: "爱克发 Vista 100", subtitle: "德味浓郁 · 高饱和复古", edgeCode: "HONGSHUXIA AGFA", iso: 100, themeColorHex: "#D9381E", defaultFormat: .mm135),
        FilmStock(id: "hasselblad_120_400h", name: "120 中画幅 · Pro 400H", subtitle: "6x6 哈苏方画幅 · 细腻空气感", edgeCode: "FUJIFILM 120 PRO 400H", iso: 400, themeColorHex: "#0077B6", defaultFormat: .medium120)
    ]
}

struct FilmFrame: Identifiable, Codable {
    var id: UUID = UUID()
    var frameNumber: Int
    var rawFileName: String
    var captureDate: Date
    var focalMM: String = "24mm"
    var format: FilmFormat = .mm135
    var isScanned: Bool = false
    var exposureEV: Double = 0.0
    var warmthWB: Double = 0.0
}

struct FilmRollData: Identifiable, Codable {
    var id: UUID = UUID()
    var stockID: String
    var format: FilmFormat = .mm135
    var capacity: Int
    var frames: [FilmFrame]
    var isDeveloped: Bool = false
    var createdDate: Date = Date()
}

enum ExportBorderStyle: String, CaseIterable, Identifiable {
    case sprocket35mm = "胶片齿孔/边码黑边"
    case clean = "无边框纯享版"
    var id: String { rawValue }
}

enum AppStage: String, Codable {
    case shooting
    case darkroom
    case lightTableScanner
}

// MARK: - 2. 触觉与机械音效引擎
final class HapticManager {
    static let shared = HapticManager()
    private var engine: CHHapticEngine?

    private init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            engine = try CHHapticEngine()
            try engine?.start()
        } catch {
            print("Haptic Engine Error: \(error)")
        }
    }

    func playRatchetTick(intensity: Float = 0.8, sharpness: Float = 0.95) {
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.impactOccurred(intensity: CGFloat(intensity))
        AudioServicesPlaySystemSound(1157)
    }

    func playFilmWoundLock() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        AudioServicesPlaySystemSound(1306)
    }

    func playShutterJammedWarning() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }

    func playShutterClick() {
        let heavy = UIImpactFeedbackGenerator(style: .heavy)
        heavy.impactOccurred()
        AudioServicesPlaySystemSound(1108)
    }

    func playScannerStepperPulse() {
        let soft = UIImpactFeedbackGenerator(style: .light)
        soft.impactOccurred(intensity: 0.45)
    }
}

// MARK: - 3. CoreImage 高清胶卷色彩引擎与横向边框合成器
final class FilmColorEngine {
    static let shared = FilmColorEngine()
    private let context = CIContext(options: [
        .useSoftwareRenderer: false,
        .highQualityDownsample: true,
        .workingColorSpace: CGColorSpace(name: CGColorSpace.displayP3)!
    ])
    private var lutCache: [String: (dimension: Int, data: Data)] = [:]

    /// 将相机拍出的照片裁剪为标准横向 3:2 (135胶卷) 或 1:1 (120中画幅)，彻底解决竖条变形问题
    func cropToFilmAspectRatio(_ image: UIImage, format: FilmFormat) -> UIImage {
        guard let cgImg = image.cgImage else { return image }
        let width = CGFloat(cgImg.width)
        let height = CGFloat(cgImg.height)

        let targetRatio: CGFloat = (format == .medium120) ? 1.0 : (3.0 / 2.0)
        var cropRect: CGRect

        // 如果是竖着拿手机拍的 (height > width)，在 135 模式下从中心裁出横向 3:2 构图（和取景框所见完全一致）
        if format == .medium120 {
            let side = min(width, height)
            cropRect = CGRect(x: (width - side) / 2.0, y: (height - side) / 2.0, width: side, height: side)
        } else {
            if width / height > targetRatio {
                let newWidth = height * targetRatio
                cropRect = CGRect(x: (width - newWidth) / 2.0, y: 0, width: newWidth, height: height)
            } else {
                let newHeight = width / targetRatio
                cropRect = CGRect(x: 0, y: (height - newHeight) / 2.0, width: width, height: newHeight)
            }
        }

        guard let croppedCG = cgImg.cropping(to: cropRect) else { return image }
        return UIImage(cgImage: croppedCG, scale: image.scale, orientation: .up)
    }

    func renderOrangeNegative(from sourceImage: UIImage) -> UIImage {
        guard let cgImg = sourceImage.cgImage else { return sourceImage }
        let ciInput = CIImage(cgImage: cgImg)

        let invert = CIFilter.colorInvert()
        invert.inputImage = ciInput
        guard let inverted = invert.outputImage else { return sourceImage }

        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = inverted
        matrix.rVector = CIVector(x: 0.95, y: 0.10, z: 0.00, w: 0)
        matrix.gVector = CIVector(x: 0.05, y: 0.62, z: 0.05, w: 0)
        matrix.bVector = CIVector(x: 0.00, y: 0.08, z: 0.35, w: 0)
        matrix.biasVector = CIVector(x: 0.14, y: 0.05, z: 0.01, w: 0)

        guard let output = matrix.outputImage,
              let outCG = context.createCGImage(output, from: ciInput.extent) else {
            return sourceImage
        }
        return UIImage(cgImage: outCG, scale: sourceImage.scale, orientation: .up)
    }

    func renderPositive(from sourceImage: UIImage, stock: FilmStock, ev: Double, warmth: Double) -> UIImage {
        guard let cgImg = sourceImage.cgImage else { return sourceImage }
        var current = CIImage(cgImage: cgImg)
        let extent = current.extent

        if abs(ev) > 0.01 {
            let expFilter = CIFilter.exposureAdjust()
            expFilter.inputImage = current
            expFilter.ev = Float(ev)
            if let out = expFilter.outputImage { current = out }
        }

        if abs(warmth) > 0.01 {
            let tempFilter = CIFilter.temperatureAndTint()
            tempFilter.inputImage = current
            tempFilter.neutral = CIVector(x: 6500, y: 0)
            tempFilter.targetNeutral = CIVector(x: 6500 - CGFloat(warmth * 1800), y: 0)
            if let out = tempFilter.outputImage { current = out }
        }

        if let cubeFile = stock.customCubeFileName,
           let lut = loadCubeData(fileName: cubeFile) {
            let cubeFilter = CIFilter.colorCubeWithColorSpace()
            cubeFilter.inputImage = current
            cubeFilter.cubeDimension = Float(lut.dimension)
            cubeFilter.cubeData = lut.data
            cubeFilter.colorSpace = CGColorSpaceCreateDeviceRGB()
            if let out = cubeFilter.outputImage { current = out }
        } else {
            current = applyBuiltInStockProfile(to: current, stockID: stock.id)
        }

        if stock.id == "cinestill_800t" {
            current = applyHalationEffect(to: current, extent: extent)
        }

        // 保持高清晰度：降低噪点对细节的破坏，同时增加胶片光学微锐化
        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = current
        sharpen.sharpness = 0.35
        if let out = sharpen.outputImage { current = out }

        let grainLevel: CGFloat
        if stock.id == "ilford_hp5" {
            grainLevel = 0.11
        } else if stock.id == "kodak_ektar100" || stock.id == "fuji_pro400h" || stock.id == "hasselblad_120_400h" {
            grainLevel = 0.025 // Ektar 100 与 Pro 400H 极其细腻
        } else {
            grainLevel = 0.045
        }

        current = applyFilmGrainAndVignette(to: current, extent: extent, grainAmount: grainLevel)

        guard let outCG = context.createCGImage(current, from: extent) else { return sourceImage }
        return UIImage(cgImage: outCG, scale: sourceImage.scale, orientation: .up)
    }

    private func applyBuiltInStockProfile(to image: CIImage, stockID: String) -> CIImage {
        var img = image
        switch stockID {
        case "fuji_pro400h", "hasselblad_120_400h":
            // Fuji Pro 400H：清透空气感，高光偏薄荷青，阴影柔润，肤色白皙通透
            let matrix = CIFilter.colorMatrix()
            matrix.inputImage = img
            matrix.rVector = CIVector(x: 0.96, y: 0.02, z: 0.00, w: 0)
            matrix.gVector = CIVector(x: 0.02, y: 1.03, z: 0.04, w: 0)
            matrix.bVector = CIVector(x: 0.00, y: 0.05, z: 1.02, w: 0)
            matrix.biasVector = CIVector(x: 0.01, y: 0.02, z: 0.02, w: 0)
            if let out = matrix.outputImage { img = out }
            let controls = CIFilter.colorControls()
            controls.inputImage = img
            controls.contrast = 0.96
            controls.brightness = 0.02
            controls.saturation = 0.95
            if let out = controls.outputImage { img = out }

        case "kodak_ektar100":
            // Kodak Ektar 100：高反差、极具冲击力的红蓝高饱和风光色彩
            let matrix = CIFilter.colorMatrix()
            matrix.inputImage = img
            matrix.rVector = CIVector(x: 1.14, y: -0.02, z: -0.02, w: 0)
            matrix.gVector = CIVector(x: -0.01, y: 1.04, z: -0.01, w: 0)
            matrix.bVector = CIVector(x: -0.02, y: 0.02, z: 1.10, w: 0)
            matrix.biasVector = CIVector(x: -0.01, y: -0.01, z: -0.01, w: 0)
            if let out = matrix.outputImage { img = out }
            let controls = CIFilter.colorControls()
            controls.inputImage = img
            controls.saturation = 1.28
            controls.contrast = 1.14
            if let out = controls.outputImage { img = out }

        case "kodak_gold200":
            // Kodak Gold 200（金200）：浓郁暖金黄高光、怀旧复古琥珀暗部
            let matrix = CIFilter.colorMatrix()
            matrix.inputImage = img
            matrix.rVector = CIVector(x: 1.10, y: 0.05, z: 0.00, w: 0)
            matrix.gVector = CIVector(x: 0.03, y: 1.01, z: 0.00, w: 0)
            matrix.bVector = CIVector(x: 0.00, y: 0.01, z: 0.84, w: 0)
            matrix.biasVector = CIVector(x: 0.03, y: 0.015, z: -0.02, w: 0)
            if let out = matrix.outputImage { img = out }
            let controls = CIFilter.colorControls()
            controls.inputImage = img
            controls.saturation = 1.12
            controls.contrast = 1.06
            if let out = controls.outputImage { img = out }

        case "fuji_c200":
            let matrix = CIFilter.colorMatrix()
            matrix.inputImage = img
            matrix.rVector = CIVector(x: 0.94, y: 0.02, z: 0.00, w: 0)
            matrix.gVector = CIVector(x: 0.03, y: 1.04, z: 0.03, w: 0)
            matrix.bVector = CIVector(x: 0.00, y: 0.06, z: 0.98, w: 0)
            matrix.biasVector = CIVector(x: -0.01, y: 0.02, z: 0.02, w: 0)
            if let out = matrix.outputImage { img = out }

        case "kodak_portra400":
            let matrix = CIFilter.colorMatrix()
            matrix.inputImage = img
            matrix.rVector = CIVector(x: 1.06, y: 0.04, z: 0.00, w: 0)
            matrix.gVector = CIVector(x: 0.02, y: 0.99, z: 0.00, w: 0)
            matrix.bVector = CIVector(x: 0.00, y: 0.02, z: 0.89, w: 0)
            matrix.biasVector = CIVector(x: 0.02, y: 0.01, z: -0.01, w: 0)
            if let out = matrix.outputImage { img = out }

        case "cinestill_800t":
            let matrix = CIFilter.colorMatrix()
            matrix.inputImage = img
            matrix.rVector = CIVector(x: 0.92, y: 0.00, z: 0.00, w: 0)
            matrix.gVector = CIVector(x: 0.00, y: 1.01, z: 0.05, w: 0)
            matrix.bVector = CIVector(x: 0.00, y: 0.07, z: 1.08, w: 0)
            matrix.biasVector = CIVector(x: -0.02, y: 0.01, z: 0.04, w: 0)
            if let out = matrix.outputImage { img = out }

        case "ilford_hp5":
            let mono = CIFilter.colorMonochrome()
            mono.inputImage = img
            mono.color = CIColor(red: 0.5, green: 0.5, blue: 0.5)
            mono.intensity = 1.0
            if let out = mono.outputImage { img = out }
            let controls = CIFilter.colorControls()
            controls.inputImage = img
            controls.contrast = 1.24
            controls.brightness = 0.01
            if let out = controls.outputImage { img = out }

        case "agfa_100":
            let matrix = CIFilter.colorMatrix()
            matrix.inputImage = img
            matrix.rVector = CIVector(x: 1.12, y: 0.03, z: -0.02, w: 0)
            matrix.gVector = CIVector(x: 0.02, y: 1.03, z: 0.00, w: 0)
            matrix.bVector = CIVector(x: -0.02, y: 0.02, z: 0.92, w: 0)
            matrix.biasVector = CIVector(x: 0.01, y: 0.00, z: -0.02, w: 0)
            if let out = matrix.outputImage { img = out }
            let controls = CIFilter.colorControls()
            controls.inputImage = img
            controls.saturation = 1.22
            controls.contrast = 1.10
            if let out = controls.outputImage { img = out }

        default:
            break
        }
        return img
    }

    private func applyHalationEffect(to image: CIImage, extent: CGRect) -> CIImage {
        let highlightExtract = CIFilter.colorControls()
        highlightExtract.inputImage = image
        highlightExtract.brightness = -0.58
        highlightExtract.contrast = 2.4
        guard let highlights = highlightExtract.outputImage else { return image }

        let redTint = CIFilter.colorMatrix()
        redTint.inputImage = highlights
        redTint.rVector = CIVector(x: 1.3, y: 0.4, z: 0.2, w: 0)
        redTint.gVector = CIVector(x: 0.15, y: 0.1, z: 0.0, w: 0)
        redTint.bVector = CIVector(x: 0.05, y: 0.0, z: 0.0, w: 0)
        guard let tinted = redTint.outputImage else { return image }

        let blur = CIFilter.gaussianBlur()
        blur.inputImage = tinted.clampedToExtent()
        blur.radius = Float(min(extent.width, extent.height) * 0.022)
        guard let blurred = blur.outputImage?.cropped(to: extent) else { return image }

        let screen = CIFilter.screenBlendMode()
        screen.inputImage = blurred
        screen.backgroundImage = image
        return screen.outputImage ?? image
    }

    private func applyFilmGrainAndVignette(to image: CIImage, extent: CGRect, grainAmount: CGFloat) -> CIImage {
        var result = image
        if let noise = CIFilter.randomGenerator().outputImage?.cropped(to: extent) {
            let grainMatrix = CIFilter.colorMatrix()
            grainMatrix.inputImage = noise
            grainMatrix.rVector = CIVector(x: grainAmount, y: 0, z: 0, w: 0)
            grainMatrix.gVector = CIVector(x: grainAmount, y: 0, z: 0, w: 0)
            grainMatrix.bVector = CIVector(x: grainAmount, y: 0, z: 0, w: 0)
            grainMatrix.aVector = CIVector(x: 0, y: 0, z: 0, w: grainAmount)
            if let grain = grainMatrix.outputImage {
                let blend = CIFilter.softLightBlendMode()
                blend.inputImage = grain
                blend.backgroundImage = result
                if let blended = blend.outputImage?.cropped(to: extent) {
                    result = blended
                }
            }
        }
        let vignette = CIFilter.vignette()
        vignette.inputImage = result
        vignette.intensity = 0.48
        vignette.radius = 1.75
        return vignette.outputImage ?? result
    }

    func parseAndSaveCubeFile(from url: URL) throws -> (fileName: String, dimension: Int) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let content = try String(contentsOf: url, encoding: .utf8)
        var dimension = 32
        var floatValues: [Float] = []

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("TITLE") || line.hasPrefix("DOMAIN_") { continue }
            if line.hasPrefix("LUT_3D_SIZE") {
                let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 2, let dim = Int(parts[1]) { dimension = dim }
                continue
            }
            let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if parts.count >= 3, let r = Float(parts[0]), let g = Float(parts[1]), let b = Float(parts[2]) {
                floatValues.append(r); floatValues.append(g); floatValues.append(b); floatValues.append(1.0)
            }
        }

        let expectedCount = dimension * dimension * dimension * 4
        guard floatValues.count == expectedCount else {
            throw NSError(domain: "CubeParser", code: -1, userInfo: [NSLocalizedDescriptionKey: "LUT 尺寸不匹配或非标准 3D .cube 格式"])
        }

        let data = Data(bytes: floatValues, count: floatValues.count * MemoryLayout<Float>.size)
        let savedName = "lut_\(UUID().uuidString).bin"
        let destURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(savedName)
        try data.write(to: destURL)
        lutCache[savedName] = (dimension, data)
        return (savedName, dimension)
    }

    private func loadCubeData(fileName: String) -> (dimension: Int, data: Data)? {
        if let cached = lutCache[fileName] { return cached }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let floatCount = data.count / MemoryLayout<Float>.size
        let cubeRoot = Int(round(pow(Double(floatCount / 4), 1.0 / 3.0)))
        let result = (dimension: cubeRoot, data: data)
        lutCache[fileName] = result
        return result
    }

    /// 导出合成器：135画幅严格按照图五生成【横向 3:2 + 上下各 8 个圆角矩形齿孔 + 金色喷码】；120画幅生成【6x6 哈苏无齿孔宽黑边】
    func composeFinalExportImage(
        positiveImage: UIImage,
        stock: FilmStock,
        frame: FilmFrame,
        borderStyle: ExportBorderStyle,
        includeDateStamp: Bool
    ) -> UIImage {
        let croppedPhoto = cropToFilmAspectRatio(positiveImage, format: frame.format)
        let baseSize = croppedPhoto.size
        let hasBorder = (borderStyle == .sprocket35mm)

        let topBottomBarHeight: CGFloat
        let sideWidth: CGFloat
        if !hasBorder {
            topBottomBarHeight = 0
            sideWidth = 0
        } else if frame.format == .medium120 {
            topBottomBarHeight = baseSize.height * 0.12
            sideWidth = baseSize.width * 0.08
        } else {
            topBottomBarHeight = baseSize.height * 0.19
            sideWidth = baseSize.width * 0.035
        }

        let canvasSize = CGSize(width: baseSize.width + sideWidth * 2, height: baseSize.height + topBottomBarHeight * 2)
        let formatRenderer = UIGraphicsImageRendererFormat()
        formatRenderer.scale = 1.0 // 保持物理像素 1:1 无损输出
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: formatRenderer)

        return renderer.image { ctx in
            let cgCtx = ctx.cgContext

            if hasBorder {
                UIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1.0).setFill()
                cgCtx.fill(CGRect(origin: .zero, size: canvasSize))

                let fontSize = max(16, topBottomBarHeight * 0.20)
                let goldAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .heavy),
                    .foregroundColor: UIColor(red: 0.90, green: 0.66, blue: 0.20, alpha: 0.92)
                ]

                if frame.format == .mm135 {
                    // 严格复刻参考图五：上下各 8 颗标准 35mm 圆角白齿孔，齿孔上方与下方居中印金色帧号 (如 30)
                    let holeCount = 8
                    let holeWidth = canvasSize.width * 0.058
                    let holeHeight = topBottomBarHeight * 0.44
                    let usableWidth = canvasSize.width - sideWidth * 2
                    let spacing = (usableWidth - CGFloat(holeCount) * holeWidth) / CGFloat(holeCount - 1)

                    UIColor(red: 0.96, green: 0.96, blue: 0.94, alpha: 1.0).setFill()
                    for i in 0..<holeCount {
                        let x = sideWidth + CGFloat(i) * (holeWidth + spacing)
                        let topHoleRect = CGRect(x: x, y: topBottomBarHeight * 0.38, width: holeWidth, height: holeHeight)
                        let bottomHoleRect = CGRect(x: x, y: canvasSize.height - topBottomBarHeight + topBottomBarHeight * 0.18, width: holeWidth, height: holeHeight)
                        UIBezierPath(roundedRect: topHoleRect, cornerRadius: holeWidth * 0.22).fill()
                        UIBezierPath(roundedRect: bottomHoleRect, cornerRadius: holeWidth * 0.22).fill()
                    }

                    // 顶部左：胶卷边缘喷码；顶部中：金色帧数；顶部右：▶ 帧数A
                    let edgeStr = "\(stock.edgeCode)  \(frame.focalMM)" as NSString
                    edgeStr.draw(at: CGPoint(x: sideWidth, y: topBottomBarHeight * 0.08), withAttributes: goldAttrs)

                    let centerNumStr = String(format: "%02d", frame.frameNumber) as NSString
                    centerNumStr.draw(at: CGPoint(x: canvasSize.width * 0.48, y: topBottomBarHeight * 0.08), withAttributes: goldAttrs)

                    let rightTopStr = String(format: "▶ %02dA", frame.frameNumber) as NSString
                    rightTopStr.draw(at: CGPoint(x: canvasSize.width - sideWidth - fontSize * 4.5, y: topBottomBarHeight * 0.08), withAttributes: goldAttrs)

                    // 底部中：金色帧数；底部右：ISO 编码
                    centerNumStr.draw(at: CGPoint(x: canvasSize.width * 0.48, y: canvasSize.height - topBottomBarHeight * 0.30), withAttributes: goldAttrs)
                    let isoStr = "\(stock.iso)" as NSString
                    isoStr.draw(at: CGPoint(x: canvasSize.width - sideWidth - fontSize * 2.5, y: canvasSize.height - topBottomBarHeight * 0.30), withAttributes: goldAttrs)
                } else {
                    // 120 中画幅边框：无齿孔，上下印有 120 专属胶卷喷码与 6x6 画幅标记
                    let topText = "\(stock.edgeCode)  ·  120 MEDIUM FORMAT 6x6" as NSString
                    topText.draw(at: CGPoint(x: sideWidth, y: topBottomBarHeight * 0.32), withAttributes: goldAttrs)

                    let bottomText = String(format: "▶ %02d   [ 6x6 cm · %@ ]   ISO %d", frame.frameNumber, frame.focalMM, stock.iso) as NSString
                    bottomText.draw(at: CGPoint(x: sideWidth, y: canvasSize.height - topBottomBarHeight * 0.62), withAttributes: goldAttrs)
                }
            }

            let photoRect = CGRect(x: sideWidth, y: topBottomBarHeight, width: baseSize.width, height: baseSize.height)
            croppedPhoto.draw(in: photoRect)

            if includeDateStamp {
                let formatter = DateFormatter()
                formatter.dateFormat = "''yy MM dd"
                let dateStr = formatter.string(from: frame.captureDate) as NSString
                let stampFontSize = max(22, baseSize.width * 0.038)

                let shadow = NSShadow()
                shadow.shadowColor = UIColor(red: 1.0, green: 0.22, blue: 0.0, alpha: 0.95)
                shadow.shadowBlurRadius = stampFontSize * 0.45
                shadow.shadowOffset = .zero

                let stampAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedDigitSystemFont(ofSize: stampFontSize, weight: .heavy),
                    .foregroundColor: UIColor(red: 1.0, green: 0.56, blue: 0.12, alpha: 0.92),
                    .shadow: shadow
                ]
                let textSize = dateStr.size(withAttributes: stampAttrs)
                let stampPoint = CGPoint(
                    x: photoRect.maxX - textSize.width - baseSize.width * 0.045,
                    y: photoRect.maxY - textSize.height - baseSize.height * 0.045
                )
                dateStr.draw(at: stampPoint, withAttributes: stampAttrs)
            }
        }
    }
}

// MARK: - 4. ViewModel (集成 iPhone 16 Pro 三摄焦段切换 + 最高画质输出)
final class FilmCameraViewModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureSessionControlsDelegate {
    @Published var stage: AppStage = .shooting
    @Published var allStocks: [FilmStock] = FilmStock.builtInStocks
    @Published var currentStock: FilmStock = FilmStock.builtInStocks[0]
    @Published var currentFormat: FilmFormat = .mm135
    @Published var maxFramesPerRoll: Int = 12

    // iPhone 16 Pro 镜头焦段控制
    @Published var selectedLens: FocalLensOption = FocalLensOption.iPhone16ProLenses[1] // 默认 24mm 1x 主摄
    private var isUsingTripleCamera: Bool = false

    @Published var savedRolls: [FilmRollData] = []
    @Published var currentActiveRollIndex: Int = 0

    @Published var frames: [FilmFrame] = []
    @Published var isShutterLocked: Bool = false
    @Published var advanceProgress: Double = 0.0
    @Published var isHardwareControlActive: Bool = false

    @Published var darkroomTotalSeconds: Int = 60
    @Published var darkroomRemainingSeconds: Int = 60
    @Published var isDeveloping: Bool = false
    private var darkroomTimer: Timer?

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.personal.hongshuxiafilm.sessionQueue")
    private let photoOutput = AVCapturePhotoOutput()
    private var videoDevice: AVCaptureDevice?
    private var hardwareAdvanceSlider: AVCaptureSlider?
    private var lastHapticStep: Int = 0

    override init() {
        super.init()
        loadCustomStocks()
        loadSavedRolls()
        setupCameraWithHardwareControl()
    }

    func setupCameraWithHardwareControl() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            // 优先启用 iPhone 16 Pro 的三摄融合镜头 (0.5x 超广 + 1x 主摄 + 5x 长焦无缝切换)
            let device: AVCaptureDevice?
            if let triple = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) {
                device = triple
                self.isUsingTripleCamera = true
            } else if let dualWide = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
                device = dualWide
                self.isUsingTripleCamera = true
            } else {
                device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                self.isUsingTripleCamera = false
            }

            if let camDevice = device,
               let input = try? AVCaptureDeviceInput(device: camDevice),
               self.session.canAddInput(input) {
                self.session.addInput(input)
                self.videoDevice = camDevice
            }

            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
                // 开启最高物理分辨率与最高清晰度输出
                self.photoOutput.isHighResolutionCaptureEnabled = true
                self.photoOutput.maxPhotoQualityPrioritization = .quality
                if let maxDim = self.videoDevice?.activeFormat.supportedMaxPhotoDimensions.last {
                    self.photoOutput.maxPhotoDimensions = maxDim
                }
            }

            if self.session.supportsControls {
                for control in self.session.controls { self.session.removeControl(control) }
                let windSlider = AVCaptureSlider("红树下 M 机械过片", symbolName: "film", in: 0.0...1.0, step: 0.02)
                windSlider.value = 0.0
                windSlider.setActionQueue(.main) { [weak self] newValue in
                    guard let self = self else { return }
                    if self.isShutterLocked { self.updateFilmAdvance(progress: Double(newValue)) }
                    else { windSlider.value = 0.0 }
                }
                if self.session.canAddControl(windSlider) {
                    self.session.addControl(windSlider)
                    self.hardwareAdvanceSlider = windSlider
                }
                self.session.setControlsDelegate(self, queue: self.sessionQueue)
            }

            self.session.commitConfiguration()
            self.session.startRunning()

            // 默认切换到 24mm 1x 主摄焦段
            self.applyZoomFactor(for: self.selectedLens, animated: false)
        }
    }

    /// 切换 iPhone 16 Pro 光学镜头与经典人文焦段
    func selectLens(_ lens: FocalLensOption) {
        selectedLens = lens
        HapticManager.shared.playRatchetTick(intensity: 0.85, sharpness: 0.9)
        sessionQueue.async { [weak self] in
            self?.applyZoomFactor(for: lens, animated: true)
        }
    }

    private func applyZoomFactor(for lens: FocalLensOption, animated: Bool) {
        guard let device = videoDevice else { return }
        let targetFactor = isUsingTripleCamera ? lens.tripleCameraZoomFactor : lens.singleCameraZoomFactor
        let clampedFactor = min(max(targetFactor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
        do {
            try device.lockForConfiguration()
            if animated {
                device.ramp(toVideoZoomFactor: clampedFactor, withRate: 18.0)
            } else {
                device.videoZoomFactor = clampedFactor
            }
            device.unlockForConfiguration()
        } catch {
            print("Zoom error: \(error)")
        }
    }

    func sessionControlsDidBecomeActive(_ session: AVCaptureSession) {
        DispatchQueue.main.async { self.isHardwareControlActive = true }
    }
    func sessionControlsWillEnterFullscreenAppearance(_ session: AVCaptureSession) {}
    func sessionControlsWillExitFullscreenAppearance(_ session: AVCaptureSession) {}
    func sessionControlsDidBecomeInactive(_ session: AVCaptureSession) {
        DispatchQueue.main.async {
            self.isHardwareControlActive = false
            if self.isShutterLocked && self.advanceProgress < 0.96 {
                withAnimation(.spring()) { self.advanceProgress = 0.0 }
                self.hardwareAdvanceSlider?.value = 0.0
            }
        }
    }

    func loadNewRoll(stock: FilmStock, format: FilmFormat, capacity: Int) {
        currentStock = stock
        currentFormat = format
        maxFramesPerRoll = capacity
        frames.removeAll()
        isShutterLocked = false
        advanceProgress = 0.0
        hardwareAdvanceSlider?.value = 0.0
        stage = .shooting
        HapticManager.shared.playFilmWoundLock()
    }

    func handlePhysicalCameraButtonPress() {
        guard stage == .shooting else { return }
        if isShutterLocked { HapticManager.shared.playShutterJammedWarning() }
        else { capturePhoto() }
    }

    func capturePhoto() {
        guard !isShutterLocked, frames.count < maxFramesPerRoll else { return }
        HapticManager.shared.playShutterClick()
        isShutterLocked = true
        advanceProgress = 0.0
        lastHapticStep = 0
        hardwareAdvanceSlider?.value = 0.0

        if session.isRunning {
            let settings = AVCapturePhotoSettings()
            settings.isHighResolutionPhotoEnabled = true
            settings.photoQualityPrioritization = self.photoOutput.maxPhotoQualityPrioritization
            if let maxDim = self.videoDevice?.activeFormat.supportedMaxPhotoDimensions.last {
                settings.maxPhotoDimensions = maxDim
            }
            photoOutput.capturePhoto(with: settings, delegate: self)
        } else {
            saveSimulatedLatentFrame()
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(), let rawImg = UIImage(data: data) else {
            saveSimulatedLatentFrame()
            return
        }
        let normalized = normalizeOrientation(rawImg)
        let cropped = FilmColorEngine.shared.cropToFilmAspectRatio(normalized, format: currentFormat)
        saveLatentImageToDisk(cropped)
    }

    private func saveSimulatedLatentFrame() {
        let size = (currentFormat == .medium120) ? CGSize(width: 1600, height: 1600) : CGSize(width: 1800, height: 1200)
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { ctx in
            UIColor(red: 0.16, green: 0.26, blue: 0.34, alpha: 1.0).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.95, green: 0.72, blue: 0.32, alpha: 1.0).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: size.width * 0.35, y: size.height * 0.25, width: 360, height: 360))
        }
        saveLatentImageToDisk(img)
    }

    private func saveLatentImageToDisk(_ image: UIImage) {
        let fileName = "latent_\(UUID().uuidString).jpg"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
        // 1.0 无损最高画质保存
        try? image.jpegData(compressionQuality: 1.0)?.write(to: url)
        DispatchQueue.main.async {
            self.frames.append(
                FilmFrame(
                    frameNumber: self.frames.count + 1,
                    rawFileName: fileName,
                    captureDate: Date(),
                    focalMM: self.selectedLens.mmLabel,
                    format: self.currentFormat
                )
            )
        }
    }

    func updateFilmAdvance(progress: Double) {
        guard isShutterLocked else { return }
        let clamped = min(max(progress, 0.0), 1.0)
        advanceProgress = clamped
        hardwareAdvanceSlider?.value = Float(clamped)

        let currentStep = Int(clamped * 12)
        if currentStep > lastHapticStep {
            lastHapticStep = currentStep
            HapticManager.shared.playRatchetTick()
        }

        if clamped >= 0.96 { completeFilmAdvance() }
    }

    private func completeFilmAdvance() {
        HapticManager.shared.playFilmWoundLock()
        advanceProgress = 1.0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.advanceProgress = 0.0
            self.hardwareAdvanceSlider?.value = 0.0
            if self.frames.count >= self.maxFramesPerRoll {
                let newRoll = FilmRollData(
                    stockID: self.currentStock.id,
                    format: self.currentFormat,
                    capacity: self.maxFramesPerRoll,
                    frames: self.frames,
                    isDeveloped: false
                )
                self.savedRolls.insert(newRoll, at: 0)
                self.currentActiveRollIndex = 0
                self.saveSavedRolls()

                self.stage = .darkroom
                self.darkroomRemainingSeconds = self.darkroomTotalSeconds
                self.isDeveloping = false
            } else {
                self.isShutterLocked = false
            }
        }
    }

    func startDarkroomDeveloping(durationSeconds: Int) {
        darkroomTotalSeconds = durationSeconds
        darkroomRemainingSeconds = durationSeconds
        isDeveloping = true
        HapticManager.shared.playShutterClick()

        darkroomTimer?.invalidate()
        darkroomTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            if self.darkroomRemainingSeconds > 1 {
                self.darkroomRemainingSeconds -= 1
                HapticManager.shared.playScannerStepperPulse()
            } else {
                timer.invalidate()
                self.finishDevelopingAndGoToScanner()
            }
        }
    }

    func finishDevelopingAndGoToScanner() {
        darkroomTimer?.invalidate()
        isDeveloping = false
        if savedRolls.indices.contains(currentActiveRollIndex) {
            savedRolls[currentActiveRollIndex].isDeveloped = true
            saveSavedRolls()
        }
        HapticManager.shared.playFilmWoundLock()
        stage = .lightTableScanner
    }

    func syncCurrentFramesToWarehouse() {
        if savedRolls.indices.contains(currentActiveRollIndex) {
            savedRolls[currentActiveRollIndex].frames = frames
            saveSavedRolls()
        }
    }

    func loadRawImage(for frame: FilmFrame) -> UIImage {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(frame.rawFileName)
        return (try? Data(contentsOf: url)).flatMap { UIImage(data: $0) } ?? UIImage()
    }

    func importCubeLUT(from url: URL) throws {
        let parsed = try FilmColorEngine.shared.parseAndSaveCubeFile(from: url)
        let cleanTitle = url.deletingPathExtension().lastPathComponent.uppercased()
        let customStock = FilmStock(
            id: "custom_\(UUID().uuidString.prefix(6))",
            name: cleanTitle,
            subtitle: "自定义 3D LUT 胶卷",
            edgeCode: "\(cleanTitle) LUT",
            iso: 400,
            themeColorHex: "#8E44AD",
            defaultFormat: .mm135,
            customCubeFileName: parsed.fileName,
            cubeDimension: parsed.dimension
        )
        allStocks.append(customStock)
        currentStock = customStock
        saveCustomStocks()
    }

    private func saveCustomStocks() {
        let customs = allStocks.filter { $0.customCubeFileName != nil }
        if let data = try? JSONEncoder().encode(customs) { UserDefaults.standard.set(data, forKey: "SavedCustomFilmStocks") }
    }

    private func loadCustomStocks() {
        if let data = UserDefaults.standard.data(forKey: "SavedCustomFilmStocks"),
           let customs = try? JSONDecoder().decode([FilmStock].self, from: data) {
            allStocks = FilmStock.builtInStocks + customs
        }
    }

    private func saveSavedRolls() {
        if let data = try? JSONEncoder().encode(savedRolls) { UserDefaults.standard.set(data, forKey: "SavedFilmRollsWarehouse") }
    }

    private func loadSavedRolls() {
        if let data = UserDefaults.standard.data(forKey: "SavedFilmRollsWarehouse"),
           let rolls = try? JSONDecoder().decode([FilmRollData].self, from: data) {
            savedRolls = rolls
        }
    }

    private func normalizeOrientation(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}

// MARK: - 5. 相机实时取景器
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var onPhysicalPress: () -> Void

    class VideoPreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var pressHandler: (() -> Void)?

        func setupHardwareEventInteraction() {
            let interaction = AVCaptureEventInteraction { [weak self] event in
                if event.phase == .ended { DispatchQueue.main.async { self?.pressHandler?() } }
            }
            self.addInteraction(interaction)
        }
    }

    func makeUIView(context: Context) -> VideoPreviewView {
        let view = VideoPreviewView()
        view.backgroundColor = .black
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.pressHandler = onPhysicalPress
        view.setupHardwareEventInteraction()
        return view
    }
    func updateUIView(_ uiView: VideoPreviewView, context: Context) { uiView.pressHandler = onPhysicalPress }
}

@main
struct RetroFilmCamApp: App {
    @StateObject private var vm = FilmCameraViewModel()
    var body: some Scene {
        WindowGroup {
            ZStack {
                Color.black.ignoresSafeArea()
                switch vm.stage {
                case .shooting: VintageCameraShootingView(vm: vm)
                case .darkroom: DarkroomDevelopingView(vm: vm)
                case .lightTableScanner: LightTableScannerView(vm: vm)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - 舞台一：红树下 M 系列机械机身 + iPhone 16 Pro 经典焦段切换环
struct VintageCameraShootingView: View {
    @ObservedObject var vm: FilmCameraViewModel
    @State private var showWarehouseSheet = false
    @State private var showRollSheet = false
    @State private var showCubeImporter = false
    @State private var importAlertMessage: String?

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.05).ignoresSafeArea()

            VStack(spacing: 10) {
                // 1. 钛金属拉丝顶盖
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.40, green: 0.40, blue: 0.38), Color(red: 0.20, green: 0.20, blue: 0.19), Color(red: 0.30, green: 0.29, blue: 0.27), Color(red: 0.12, green: 0.12, blue: 0.11)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .clear, .white.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2))
                        .shadow(color: .black.opacity(0.85), radius: 10, x: 0, y: 6)

                    VStack(spacing: 8) {
                        HStack {
                            CameraScrewIcon()
                            Text("HONGSHUXIA OPTIK · \(vm.selectedLens.mmLabel)  \(vm.currentFormat == .medium120 ? "120 6x6" : "135 35mm")")
                                .font(.system(size: 8.5, weight: .bold, design: .serif))
                                .tracking(1.8)
                                .foregroundColor(Color(red: 0.92, green: 0.88, blue: 0.80).opacity(0.85))
                            Spacer()
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(LinearGradient(colors: [.white.opacity(0.75), .gray.opacity(0.35), .white.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 28, height: 10)
                                .overlay(RoundedRectangle(cornerRadius: 2.5).stroke(Color.black, lineWidth: 1.2))
                            CameraScrewIcon()
                        }
                        .padding(.horizontal, 14)

                        HStack(spacing: 10) {
                            Button { showRollSheet = true } label: {
                                HStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: 2).fill(Color(hex: vm.currentStock.themeColorHex)).frame(width: 5, height: 26)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(vm.currentStock.name).font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(Color(red: 1.0, green: 0.86, blue: 0.38))
                                        Text("\(vm.currentFormat == .medium120 ? "120 6x6" : "135") · ISO \(vm.currentStock.iso) / \(vm.maxFramesPerRoll)EXP")
                                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced)).foregroundColor(.white.opacity(0.7))
                                    }
                                }
                                .padding(.horizontal, 8).padding(.vertical, 5).background(Color.black.opacity(0.85)).cornerRadius(5).overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.2), lineWidth: 1))
                            }

                            Spacer()

                            ZStack {
                                Circle().fill(Color.black).frame(width: 42, height: 42).overlay(Circle().stroke(LinearGradient(colors: [.gray, .black, .white.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2))
                                VStack(spacing: 0) {
                                    Text("FRAME").font(.system(size: 5.5, weight: .bold, design: .monospaced)).foregroundColor(.gray)
                                    Text(String(format: "%02d", vm.frames.count)).font(.system(size: 15, weight: .black, design: .monospaced)).foregroundColor(vm.isShutterLocked ? .orange : Color(red: 0.95, green: 0.92, blue: 0.82))
                                }
                            }

                            MechanicalAdvanceLever(isLocked: vm.isShutterLocked, progress: vm.advanceProgress) { newProgress in
                                vm.updateFilmAdvance(progress: newProgress)
                            }
                        }
                        .padding(.horizontal, 14)
                    }
                    .padding(.vertical, 10)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)

                // 2. 荔枝纹蒙皮机身 + 宽屏 3:2 / 120 6x6 取景框 + iPhone 16 Pro 经典焦段切换环
                ZStack {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color(red: 0.08, green: 0.08, blue: 0.09))
                        .overlay(LeatheretteGrainCanvas().clipShape(RoundedRectangle(cornerRadius: 22)).opacity(0.35))
                        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(LinearGradient(colors: [.white.opacity(0.25), .black.opacity(0.95), .white.opacity(0.12)], startPoint: .top, endPoint: .bottom), lineWidth: 2))
                        .shadow(color: .black.opacity(0.9), radius: 12, x: 0, y: 8)

                    VStack(spacing: 10) {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 4).fill(RadialGradient(colors: [Color(red: 0.92, green: 0.16, blue: 0.13), Color(red: 0.60, green: 0.06, blue: 0.05)], center: .topLeading, startRadius: 2, endRadius: 22)).frame(width: 62, height: 20)
                                Text("红树下").font(.system(size: 11, weight: .bold, design: .serif)).foregroundColor(.white)
                            }
                            .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 2)

                            Spacer()

                            // 胶卷仓库入口
                            Button {
                                showWarehouseSheet = true
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "cylinder.split.1x2.fill").foregroundColor(.yellow)
                                    Text("胶卷仓库 (\(vm.savedRolls.count))")
                                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                        .foregroundColor(.yellow)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.black.opacity(0.8))
                                .cornerRadius(10)
                                .overlay(Capsule().stroke(Color.yellow.opacity(0.5), lineWidth: 1))
                            }
                        }
                        .padding(.horizontal, 18)

                        // 关键取景窗：135 胶卷为宽幅 3:2 横构图 (312 x 208)，120 胶卷为 1:1 哈苏方画幅 (220 x 220)
                        let vfWidth: CGFloat = (vm.currentFormat == .medium120) ? 216 : 312
                        let vfHeight: CGFloat = (vm.currentFormat == .medium120) ? 216 : 208

                        ZStack {
                            CameraPreviewView(session: vm.session) { vm.handlePhysicalCameraButtonPress() }
                                .frame(width: vfWidth, height: vfHeight)
                                .clipShape(RoundedRectangle(cornerRadius: 10))

                            // 徕卡明亮框线与黄斑对焦区
                            ZStack {
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 1, dash: [8, 4]))
                                    .padding(12)
                                Rectangle()
                                    .fill(Color.yellow.opacity(0.15))
                                    .frame(width: 42, height: 28)
                                    .overlay(Rectangle().stroke(Color.yellow.opacity(0.65), lineWidth: 0.8))

                                // 取景框右下角焦段与画幅浮标
                                VStack {
                                    Spacer()
                                    HStack {
                                        Spacer()
                                        Text("\(vm.selectedLens.mmLabel) · \(vm.currentFormat == .medium120 ? "6x6" : "3:2")")
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundColor(.yellow.opacity(0.9))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.black.opacity(0.6))
                                            .cornerRadius(4)
                                            .padding(16)
                                    }
                                }
                            }
                            .frame(width: vfWidth, height: vfHeight)
                            .allowsHitTesting(false)

                            if vm.isShutterLocked {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.black.opacity(0.76))
                                    .frame(width: vfWidth, height: vfHeight)
                                    .overlay(
                                        VStack(spacing: 8) {
                                            Image(systemName: "hand.tap.fill").font(.system(size: 26)).foregroundColor(.orange)
                                            Text(vm.frames.count >= vm.maxFramesPerRoll ? "整卷已拍满！过片即刻送进暗房" : "快门机械锁死 · 请滑动【相机控制键】或拨杆过片")
                                                .font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.white).multilineTextAlignment(.center).padding(.horizontal, 16)
                                        }
                                    )
                            }
                        }
                        .padding(5)
                        .background(RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [Color(white: 0.28), Color(white: 0.08), Color(white: 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                        .shadow(color: .black.opacity(0.9), radius: 8, x: 0, y: 5)
                        .animation(.spring(response: 0.35), value: vm.currentFormat)

                        // iPhone 16 Pro 三摄 + 经典定焦快速切换环 (13mm / 24mm / 28mm / 35mm / 50mm / 120mm)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(FocalLensOption.iPhone16ProLenses) { lens in
                                    let isSelected = (vm.selectedLens == lens)
                                    Button {
                                        vm.selectLens(lens)
                                    } label: {
                                        VStack(spacing: 1) {
                                            Text(lens.mmLabel)
                                                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                                .foregroundColor(isSelected ? .black : .white)
                                            Text(lens.subLabel)
                                                .font(.system(size: 8, weight: .semibold))
                                                .foregroundColor(isSelected ? .black.opacity(0.75) : .gray)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(isSelected ? Color.yellow : Color.black.opacity(0.7))
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(isSelected ? Color.orange : Color.white.opacity(0.15), lineWidth: 1)
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 14)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .padding(.horizontal, 12)

                // 3. 过片触控条
                AppleCameraSlideAdvanceBar(isLocked: vm.isShutterLocked, progress: vm.advanceProgress) { newProgress in
                    vm.updateFilmAdvance(progress: newProgress)
                }
                .padding(.horizontal, 14)

                // 4. 底部操作台
                HStack(spacing: 36) {
                    Button { showCubeImporter = true } label: {
                        KnurledMetalDialButton(icon: "cube.transparent.fill", title: "LUT工坊", accentColor: Color(red: 0.85, green: 0.82, blue: 0.75))
                    }

                    Button { vm.capturePhoto() } label: {
                        ZStack {
                            Circle().fill(LinearGradient(colors: [Color(white: 0.7), Color(white: 0.25), Color(white: 0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 74, height: 74).shadow(color: .black.opacity(0.8), radius: 6, x: 0, y: 4)
                            Circle().stroke(Color.black.opacity(0.6), style: StrokeStyle(lineWidth: 3, dash: [2, 2])).frame(width: 68, height: 68)
                            Circle().fill(RadialGradient(colors: vm.isShutterLocked ? [Color(white: 0.3), Color(white: 0.15)] : [Color(red: 0.9, green: 0.18, blue: 0.14), Color(red: 0.55, green: 0.06, blue: 0.05)], center: .topLeading, startRadius: 4, endRadius: 38)).frame(width: 54, height: 54).overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                            Circle().fill(Color(white: 0.1)).frame(width: 14, height: 14).overlay(Circle().stroke(Color(white: 0.5), lineWidth: 1.2))
                        }
                    }
                    .disabled(vm.isShutterLocked)

                    Button { showRollSheet = true } label: {
                        KnurledMetalDialButton(icon: "film.stack.fill", title: "装卷/120", accentColor: Color(red: 0.98, green: 0.82, blue: 0.32))
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .sheet(isPresented: $showWarehouseSheet) {
            FilmWarehouseView(vm: vm)
        }
        .sheet(isPresented: $showRollSheet) { FilmRollSelectorSheet(vm: vm) }
        .fileImporter(isPresented: $showCubeImporter, allowedContentTypes: [UTType(filenameExtension: "cube") ?? .data], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let first = urls.first {
                do {
                    try vm.importCubeLUT(from: first)
                    importAlertMessage = "成功载入 \(first.lastPathComponent) 专属胶卷！"
                } catch {
                    importAlertMessage = "导入失败：\(error.localizedDescription)"
                }
            }
        }
        .alert("工坊提示", isPresented: Binding(get: { importAlertMessage != nil }, set: { if !$0 { importAlertMessage = nil } })) {
            Button("确定", role: .cancel) {}
        } message: { Text(importAlertMessage ?? "") }
    }
}

// MARK: - 拟物化“胶卷仓库”界面（金属暗盒整齐陈列，点击进入看片台扫描）
struct FilmWarehouseView: View {
    @ObservedObject var vm: FilmCameraViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.06).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("已拍满存档的胶卷金属暗盒（点击进入扫描看片台）")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                            .padding(.horizontal, 16)
                            .padding(.top, 10)

                        if vm.savedRolls.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "cylinder.split.1x2")
                                    .font(.system(size: 42))
                                    .foregroundColor(.gray)
                                Text("胶卷仓库暂无存档\n拍满一卷后暗盒会自动排列在此处")
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 16)], spacing: 16) {
                                ForEach(Array(vm.savedRolls.enumerated()), id: \.element.id) { idx, roll in
                                    let stock = vm.allStocks.first(where: { $0.id == roll.stockID }) ?? vm.allStocks[0]
                                    Button {
                                        vm.currentActiveRollIndex = idx
                                        vm.frames = roll.frames
                                        vm.currentStock = stock
                                        vm.currentFormat = roll.format
                                        vm.stage = .lightTableScanner
                                        dismiss()
                                    } label: {
                                        VStack(spacing: 8) {
                                            ZStack {
                                                // 金属胶卷轴心
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(Color(white: 0.28))
                                                    .frame(width: 34, height: 86)
                                                // 胶卷金属罐体
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(
                                                        LinearGradient(
                                                            colors: [Color(hex: stock.themeColorHex), Color.black.opacity(0.9)],
                                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                                        )
                                                    )
                                                    .frame(height: 74)
                                                    .overlay(
                                                        VStack(spacing: 3) {
                                                            Text(roll.format == .medium120 ? "120 MEDIUM" : "135 FILM")
                                                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                                                .foregroundColor(.white.opacity(0.8))
                                                            Text(stock.name)
                                                                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                                                                .foregroundColor(.white)
                                                                .lineLimit(1)
                                                            Text("\(roll.frames.count) EXP")
                                                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                                .foregroundColor(.yellow)
                                                        }
                                                        .padding(.horizontal, 6)
                                                    )
                                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.25), lineWidth: 1.2))
                                            }
                                            Text(roll.isDeveloped ? "● 已显影 · 点击看片扫描" : "● 待显影 · 点击冲洗")
                                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                                .foregroundColor(roll.isDeveloped ? .green : .orange)
                                        }
                                        .padding(10)
                                        .background(Color(white: 0.11))
                                        .cornerRadius(12)
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1))
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("红树下 · 胶卷仓库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }.foregroundColor(.orange)
                }
            }
        }
    }
}

// 辅助组件
struct CameraScrewIcon: View {
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(white: 0.5), Color(white: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 8, height: 8)
            Rectangle().fill(Color.black.opacity(0.8)).frame(width: 5, height: 1).rotationEffect(.degrees(30))
        }
    }
}

struct LeatheretteGrainCanvas: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 4.0
            var row = 0
            for y in stride(from: 0, to: size.height, by: step) {
                row += 1
                let xOffset: CGFloat = (row % 2 == 0) ? (step * 0.5) : 0
                for x in stride(from: 0, to: size.width, by: step) {
                    context.fill(Path(ellipseIn: CGRect(x: x + xOffset, y: y, width: 1.6, height: 1.6)), with: .color(.white.opacity(0.15)))
                    context.fill(Path(ellipseIn: CGRect(x: x + xOffset + 0.7, y: y + 0.7, width: 1.6, height: 1.6)), with: .color(.black.opacity(0.6)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct KnurledMetalDialButton: View {
    let icon: String
    let title: String
    let accentColor: Color
    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.26), Color(white: 0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 56, height: 56)
                .overlay(Circle().stroke(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 2, dash: [3, 2])))
                .shadow(color: .black.opacity(0.7), radius: 4, x: 0, y: 3)
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                Text(title).font(.system(size: 8.5, weight: .bold, design: .monospaced))
            }
            .foregroundColor(accentColor)
        }
    }
}

struct MechanicalAdvanceLever: View {
    let isLocked: Bool
    let progress: Double
    let onDragProgress: (Double) -> Void
    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color(red: 0.05, green: 0.05, blue: 0.05))
                .frame(width: 106, height: 36)
                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                .overlay(
                    Text(isLocked ? "WIND ➔" : "READY")
                        .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                        .foregroundColor(isLocked ? .orange : Color(red: 0.35, green: 0.85, blue: 0.5))
                        .padding(.leading, 12)
                )
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.9), Color(white: 0.4)], startPoint: .top, endPoint: .bottom))
                .frame(width: 32, height: 32)
                .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 2)
                .offset(x: CGFloat(progress) * 70 + 2)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            guard isLocked else { return }
                            onDragProgress(Double(value.translation.width / 70.0))
                        }
                        .onEnded { _ in
                            if progress < 0.96 { withAnimation(.spring()) { onDragProgress(0.0) } }
                        }
                )
        }
    }
}

struct AppleCameraSlideAdvanceBar: View {
    let isLocked: Bool
    let progress: Double
    let onSlideProgress: (Double) -> Void
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "dial.medium.fill").font(.system(size: 10)).foregroundColor(isLocked ? .orange : .gray)
                Text(isLocked ? "滑动机身【相机控制键】或下方滑轨机械过片" : "快门已上弦 · 按实体按键或红钮拍摄")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(isLocked ? Color(red: 0.98, green: 0.82, blue: 0.32) : .gray)
                Spacer()
                Text("\(Int(progress * 100))%").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.orange)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.7))
                        .overlay(
                            HStack(spacing: 6) {
                                ForEach(0..<24, id: \.self) { idx in
                                    Rectangle()
                                        .fill(idx % 5 == 0 ? Color.orange.opacity(0.75) : Color.white.opacity(0.2))
                                        .frame(width: 1.5, height: idx % 5 == 0 ? 12 : 6)
                                }
                            }
                        )
                    RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.3)).frame(width: max(40, geo.size.width * CGFloat(progress)))
                    Capsule()
                        .fill(isLocked ? Color.orange : Color.gray.opacity(0.4))
                        .frame(width: 48, height: 24)
                        .overlay(Image(systemName: "chevron.right.2").font(.system(size: 10, weight: .black)).foregroundColor(.black))
                        .offset(x: (geo.size.width - 52) * CGFloat(progress) + 2)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard isLocked else { return }
                            onSlideProgress(Double(value.location.x / geo.size.width))
                        }
                        .onEnded { _ in
                            if progress < 0.96 { withAnimation(.spring()) { onSlideProgress(0.0) } }
                        }
                )
            }
            .frame(height: 26)
        }
        .padding(8)
        .background(Color(white: 0.1))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
}

// MARK: - 胶卷与 135/120 画幅装填仓
struct FilmRollSelectorSheet: View {
    @ObservedObject var vm: FilmCameraViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCapacity: Int = 12
    @State private var selectedFormat: FilmFormat = .mm135

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. 选择胶卷画幅规格 (135 全画幅 / 120 哈苏方画幅)").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.gray)
                        Picker("胶卷画幅", selection: $selectedFormat) {
                            ForEach(FilmFormat.allCases) { fmt in
                                Text(fmt.rawValue).tag(fmt)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("2. 选择每卷张数").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.gray).padding(.top, 4)
                        Picker("每卷张数", selection: $selectedCapacity) {
                            Text("6 EXP · 爽快半卷").tag(6)
                            Text("12 EXP · 标准整卷").tag(12)
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                    Text("3. 点击装填胶卷型号（已加入 Fuji Pro 400H / Ektar 100 / 金200 / 120）").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.gray).padding(.horizontal, 16)

                    ForEach(vm.allStocks) { stock in
                        Button {
                            let finalFormat = (stock.defaultFormat == .medium120) ? .medium120 : selectedFormat
                            vm.loadNewRoll(stock: stock, format: finalFormat, capacity: selectedCapacity)
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.22)).frame(width: 22, height: 60)
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(LinearGradient(colors: [Color(hex: stock.themeColorHex), Color.black.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: 44, height: 50)
                                        .overlay(VStack(spacing: 1) {
                                            Text(stock.defaultFormat == .medium120 ? "120" : "135").font(.system(size: 7.5, weight: .black, design: .monospaced)).foregroundColor(.white.opacity(0.85))
                                            Text("\(stock.iso)").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(.white)
                                        })
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(stock.name).font(.system(size: 16, weight: .heavy, design: .monospaced)).foregroundColor(.white)
                                        if vm.currentStock.id == stock.id {
                                            Text("已装填").font(.system(size: 8.5, weight: .black, design: .monospaced)).padding(.horizontal, 5).padding(.vertical, 2).background(Color.orange).foregroundColor(.black).cornerRadius(3)
                                        }
                                    }
                                    Text(stock.subtitle).font(.system(size: 11.5, weight: .medium)).foregroundColor(.white.opacity(0.75))
                                    Text("齿孔喷码：\(stock.edgeCode)").font(.system(size: 9.5, weight: .bold, design: .monospaced)).foregroundColor(Color(red: 0.88, green: 0.64, blue: 0.22))
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundColor(.gray)
                            }
                            .padding(12)
                            .background(Color(white: 0.1))
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(vm.currentStock.id == stock.id ? Color.orange : Color.white.opacity(0.08), lineWidth: 1.2))
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 20)
            }
            .background(Color(red: 0.05, green: 0.05, blue: 0.06).ignoresSafeArea())
            .navigationTitle("装填 135 / 120 胶卷")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("关闭") { dismiss() }.foregroundColor(.orange) }
            }
        }
        .onAppear {
            selectedCapacity = vm.maxFramesPerRoll
            selectedFormat = vm.currentFormat
        }
    }
}

// MARK: - 阶段二：红光暗房显影
struct DarkroomDevelopingView: View {
    @ObservedObject var vm: FilmCameraViewModel
    @State private var selectedWaitSeconds: Int = 60
    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(red: 0.42, green: 0.03, blue: 0.03), Color.black], center: .center, startRadius: 30, endRadius: 420).ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "light.beacon.max.fill").font(.system(size: 50)).foregroundColor(.red).shadow(color: .red, radius: 15)
                Text("暗房显影定影中").font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundColor(.white)
                Text("当前卷：\(vm.currentStock.name)（\(vm.frames.count) 张潜影）").font(.system(size: 12)).foregroundColor(.red.opacity(0.85))

                if !vm.isDeveloping {
                    VStack(spacing: 12) {
                        Picker("显影时长", selection: $selectedWaitSeconds) {
                            Text("30 秒").tag(30)
                            Text("1 分钟").tag(60)
                            Text("3 分钟").tag(180)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 32)

                        Button { vm.startDarkroomDeveloping(durationSeconds: selectedWaitSeconds) } label: {
                            Text("浸入显影液 · 开始计时").font(.system(size: 15, weight: .bold)).foregroundColor(.black).padding(.horizontal, 28).padding(.vertical, 12).background(Color.red).cornerRadius(10)
                        }
                    }
                } else {
                    VStack(spacing: 14) {
                        Text(String(format: "%02d:%02d", vm.darkroomRemainingSeconds / 60, vm.darkroomRemainingSeconds % 60))
                            .font(.system(size: 50, weight: .heavy, design: .monospaced))
                            .foregroundColor(.red)
                        ProgressView(value: Double(vm.darkroomTotalSeconds - vm.darkroomRemainingSeconds), total: Double(max(1, vm.darkroomTotalSeconds))).tint(.red).padding(.horizontal, 45)
                    }
                }

                Button { vm.finishDevelopingAndGoToScanner() } label: {
                    HStack { Image(systemName: "forward.end.fill"); Text("跳过等待 · 移步看片台扫描") }
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(.white).padding(.horizontal, 20).padding(.vertical, 10).background(Color.white.opacity(0.12)).cornerRadius(8)
                }
            }
            .padding()
        }
    }
}

// MARK: - 阶段三：发光看片台（无级缩放 + 点击单张自动放大居中 + 独立/批量导出）
struct LightTableScannerView: View {
    @ObservedObject var vm: FilmCameraViewModel
    @State private var selectedIndex: Int? = 0
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastPinchScale: CGFloat = 1.0
    @State private var borderStyle: ExportBorderStyle = .sprocket35mm
    @State private var includeDateStamp: Bool = true
    @State private var saveToastMessage: String?

    var body: some View {
        VStack(spacing: 8) {
            // 1. 顶部看片台背光控制栏 + 放大镜缩放滑杆
            VStack(spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("HONGSHUXIA LIGHT TABLE 5500K").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                        Text("双指捏合缩放 · 点击任意底片自动放大至最佳审片尺寸").font(.system(size: 9.5)).foregroundColor(.black.opacity(0.65))
                    }
                    Spacer()
                    Button { vm.stage = .shooting } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "camera.fill")
                            Text("返回拍摄")
                        }
                        .font(.system(size: 11, weight: .bold)).foregroundColor(.white).padding(.horizontal, 10).padding(.vertical, 6).background(Color.black).cornerRadius(6)
                    }
                }

                // 看片台缩放控制条
                HStack(spacing: 8) {
                    Image(systemName: "minus.magnifyingglass").foregroundColor(.black.opacity(0.7)).font(.system(size: 12))
                    Slider(value: $zoomScale, in: 0.75...2.4)
                        .tint(.black)
                    Image(systemName: "plus.magnifyingglass").foregroundColor(.black.opacity(0.7)).font(.system(size: 12))
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            zoomScale = (zoomScale > 1.3) ? 1.0 : 1.85
                        }
                    } label: {
                        Text(String(format: "%.1fx", zoomScale))
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.black)
                            .cornerRadius(4)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(white: 0.95))

            // 2. 发光灯箱平铺看片台（支持自由缩放 + 点击单张自动放大居中审片）
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    let cardWidth: CGFloat = 152 * zoomScale
                    let columns = [GridItem(.adaptive(minimum: max(110, cardWidth)), spacing: 12)]

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(Array(vm.frames.enumerated()), id: \.element.id) { idx, frame in
                            let rawImg = vm.loadRawImage(for: frame)
                            let croppedRaw = FilmColorEngine.shared.cropToFilmAspectRatio(rawImg, format: frame.format)
                            let displayImg = frame.isScanned
                                ? FilmColorEngine.shared.renderPositive(from: croppedRaw, stock: vm.currentStock, ev: frame.exposureEV, warmth: frame.warmthWB)
                                : FilmColorEngine.shared.renderOrangeNegative(from: croppedRaw)

                            LightTableContactCell(
                                image: displayImg,
                                stock: vm.currentStock,
                                frame: frame,
                                cellWidth: cardWidth,
                                isSelected: selectedIndex == idx
                            )
                            .id(frame.id)
                            .onTapGesture {
                                HapticManager.shared.playRatchetTick()
                                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                                    if selectedIndex == idx && zoomScale > 1.5 {
                                        // 再次点击已放大的底片，自动缩回全景平铺
                                        zoomScale = 1.0
                                    } else {
                                        // 点击底片，自动放大到 1.85x 审片尺寸并平滑滚动至视野中央
                                        selectedIndex = idx
                                        zoomScale = 1.85
                                    }
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        proxy.scrollTo(frame.id, anchor: .center)
                                    }
                                }
                            }
                        }
                    }
                    .padding(14)
                }
                .background(Color(red: 0.95, green: 0.95, blue: 0.93))
                .cornerRadius(12)
                .padding(.horizontal, 10)
                .gesture(
                    MagnificationGesture()
                        .onChanged { val in
                            let delta = val / lastPinchScale
                            lastPinchScale = val
                            zoomScale = min(max(zoomScale * delta, 0.75), 2.5)
                        }
                        .onEnded { _ in
                            lastPinchScale = 1.0
                        }
                )
            }

            // 3. 单张精修控制台（参考图三半圆盘刻度感：选中单张时可调 EV / WB 并支持单张独立导出）
            if let sel = selectedIndex, vm.frames.indices.contains(sel) {
                let currentFrame = vm.frames[sel]
                VStack(spacing: 8) {
                    HStack {
                        Text("正在精修第 \(String(format: "%02dA", currentFrame.frameNumber)) 张 (\(currentFrame.focalMM))")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundColor(.yellow)
                        Spacer()
                        Button {
                            vm.frames[sel].isScanned.toggle()
                            vm.syncCurrentFramesToWarehouse()
                            HapticManager.shared.playRatchetTick()
                        } label: {
                            Text(currentFrame.isScanned ? "● 已扫正片 (点击切回负片)" : "○ 橙色负片 (点击反转正片)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(currentFrame.isScanned ? .green : .orange)
                        }
                    }

                    HStack(spacing: 14) {
                        HStack {
                            Text(String(format: "EV %+.1f", currentFrame.exposureEV))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.orange)
                                .frame(width: 52, alignment: .leading)
                            Slider(
                                value: Binding(
                                    get: { vm.frames[sel].exposureEV },
                                    set: {
                                        vm.frames[sel].exposureEV = $0
                                        vm.syncCurrentFramesToWarehouse()
                                    }
                                ),
                                in: -1.5...1.5
                            )
                            .tint(.orange)
                        }

                        HStack {
                            Text(String(format: "WB %+.1f", currentFrame.warmthWB))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.yellow)
                                .frame(width: 52, alignment: .leading)
                            Slider(
                                value: Binding(
                                    get: { vm.frames[sel].warmthWB },
                                    set: {
                                        vm.frames[sel].warmthWB = $0
                                        vm.syncCurrentFramesToWarehouse()
                                    }
                                ),
                                in: -1.0...1.0
                            )
                            .tint(.yellow)
                        }
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.08))
                .cornerRadius(10)
                .padding(.horizontal, 10)
            }

            // 4. 底部边框选择 + 一键全卷扫描 + 单张导出/一键导出整卷
            VStack(spacing: 8) {
                HStack {
                    Picker("边框", selection: $borderStyle) {
                        ForEach(ExportBorderStyle.allCases) { style in Text(style.rawValue).tag(style) }
                    }
                    .pickerStyle(.segmented)

                    Toggle("荧光日期", isOn: $includeDateStamp)
                        .font(.system(size: 11, weight: .semibold))
                        .toggleStyle(.button)
                        .tint(.orange)
                }

                HStack(spacing: 8) {
                    // 一键全卷扫描
                    Button {
                        for i in 0..<vm.frames.count {
                            vm.frames[i].isScanned = true
                        }
                        vm.syncCurrentFramesToWarehouse()
                        HapticManager.shared.playFilmWoundLock()
                        showToast("已一键扫描整卷 \(vm.frames.count) 张底片！")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "wand.and.stars")
                            Text("一键全扫")
                        }
                        .font(.system(size: 11.5, weight: .bold)).foregroundColor(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(Color.cyan).cornerRadius(8)
                    }

                    // 导出当前选中单张
                    if let sel = selectedIndex, vm.frames.indices.contains(sel) {
                        Button {
                            exportSinglePhoto(at: sel)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "photo.badge.arrow.down")
                                Text("导出本张")
                            }
                            .font(.system(size: 11.5, weight: .bold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(Color.orange).cornerRadius(8)
                        }
                    }

                    // 一键批量导出整卷
                    Button {
                        batchExportAllPhotos()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down.on.square.fill")
                            Text("一键导出整卷")
                        }
                        .font(.system(size: 11.5, weight: .bold)).foregroundColor(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(Color.yellow).cornerRadius(8)
                    }
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.08))
            .cornerRadius(10)
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
        .overlay(alignment: .top) {
            if let msg = saveToastMessage {
                Text(msg)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color.green)
                    .cornerRadius(16)
                    .padding(.top, 50)
            }
        }
    }

    private func exportSinglePhoto(at index: Int) {
        vm.frames[index].isScanned = true
        let frame = vm.frames[index]
        let rawImg = vm.loadRawImage(for: frame)
        let croppedRaw = FilmColorEngine.shared.cropToFilmAspectRatio(rawImg, format: frame.format)
        let posImg = FilmColorEngine.shared.renderPositive(from: croppedRaw, stock: vm.currentStock, ev: frame.exposureEV, warmth: frame.warmthWB)
        let finalImg = FilmColorEngine.shared.composeFinalExportImage(
            positiveImage: posImg,
            stock: vm.currentStock,
            frame: frame,
            borderStyle: borderStyle,
            includeDateStamp: includeDateStamp
        )
        UIImageWriteToSavedPhotosAlbum(finalImg, nil, nil, nil)
        HapticManager.shared.playFilmWoundLock()
        showToast("已导出第 \(frame.frameNumber) 张高清胶片至相册！")
    }

    private func batchExportAllPhotos() {
        for i in 0..<vm.frames.count {
            vm.frames[i].isScanned = true
            let frame = vm.frames[i]
            let rawImg = vm.loadRawImage(for: frame)
            let croppedRaw = FilmColorEngine.shared.cropToFilmAspectRatio(rawImg, format: frame.format)
            let posImg = FilmColorEngine.shared.renderPositive(from: croppedRaw, stock: vm.currentStock, ev: frame.exposureEV, warmth: frame.warmthWB)
            let finalImg = FilmColorEngine.shared.composeFinalExportImage(
                positiveImage: posImg,
                stock: vm.currentStock,
                frame: frame,
                borderStyle: borderStyle,
                includeDateStamp: includeDateStamp
            )
            UIImageWriteToSavedPhotosAlbum(finalImg, nil, nil, nil)
        }
        vm.syncCurrentFramesToWarehouse()
        HapticManager.shared.playFilmWoundLock()
        showToast("成功将整卷 \(vm.frames.count) 张高清胶片全部导出至系统相册！")
    }

    private func showToast(_ text: String) {
        withAnimation { saveToastMessage = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation { saveToastMessage = nil }
        }
    }
}

// MARK: - 看片台上的单张横向齿孔底片组件（完全对齐图三与图五横向齿孔）
struct LightTableContactCell: View {
    let image: UIImage
    let stock: FilmStock
    let frame: FilmFrame
    let cellWidth: CGFloat
    let isSelected: Bool

    var body: some View {
        let photoHeight = (frame.format == .medium120) ? cellWidth : (cellWidth * 0.66)

        VStack(spacing: 4) {
            // 顶部边缘喷码与上排横向齿孔
            HStack {
                Text(stock.edgeCode)
                    .font(.system(size: max(6, cellWidth * 0.042), weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.90, green: 0.66, blue: 0.20))
                Spacer()
                Text(String(format: "%02d", frame.frameNumber))
                    .font(.system(size: max(7, cellWidth * 0.048), weight: .heavy, design: .monospaced))
                    .foregroundColor(Color(red: 0.90, green: 0.66, blue: 0.20))
            }
            .padding(.horizontal, 4)

            if frame.format == .mm135 {
                HStack(spacing: cellWidth * 0.045) {
                    ForEach(0..<8, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color(red: 0.95, green: 0.95, blue: 0.93))
                            .frame(width: cellWidth * 0.065, height: cellWidth * 0.045)
                    }
                }
            }

            // 底片画面（3:2 横向或 1:1 哈苏方画幅）
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: cellWidth, height: photoHeight)
                .clipped()

            if frame.format == .mm135 {
                HStack(spacing: cellWidth * 0.045) {
                    ForEach(0..<8, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color(red: 0.95, green: 0.95, blue: 0.93))
                            .frame(width: cellWidth * 0.065, height: cellWidth * 0.045)
                    }
                }
            }

            // 底部帧号与焦段标记
            HStack {
                Text(frame.focalMM)
                    .font(.system(size: max(6, cellWidth * 0.04), weight: .semibold, design: .monospaced))
                    .foregroundColor(.gray)
                Spacer()
                Text(String(format: "▶ %02dA", frame.frameNumber))
                    .font(.system(size: max(6.5, cellWidth * 0.045), weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.90, green: 0.66, blue: 0.20))
            }
            .padding(.horizontal, 4)
        }
        .padding(6)
        .background(Color(red: 0.06, green: 0.06, blue: 0.06))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.orange : Color.black, lineWidth: isSelected ? 2.5 : 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        self.init(red: Double((int >> 16) & 0xFF) / 255.0, green: Double((int >> 8) & 0xFF) / 255.0, blue: Double(int & 0xFF) / 255.0)
    }
}