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
    case mm135 = "135 全画幅 (3:2)"
    case medium120 = "120 中画幅 (6x6)"
    var id: String { rawValue }
}

struct FocalLensOption: Identifiable, Equatable {
    let id: String
    let mmLabel: String
    let subLabel: String
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
    var customCubeFileName: String?
    var cubeDimension: Int?

    static let builtInStocks: [FilmStock] = [
        FilmStock(id: "fuji_pro400h", name: "Fuji Pro 400H", subtitle: "传奇人像 · 清透青绿与柔粉肤色", edgeCode: "FUJI PRO 400H", iso: 400, themeColorHex: "#2EC4B6"),
        FilmStock(id: "kodak_ektar100", name: "Kodak Ektar 100", subtitle: "风光之王 · 极致细腻高饱和", edgeCode: "KODAK EKTAR 100", iso: 100, themeColorHex: "#E71D36"),
        FilmStock(id: "kodak_gold200", name: "Kodak 金 200", subtitle: "复古金黄 · 温暖午后阳光感", edgeCode: "KODAK GOLD 200", iso: 200, themeColorHex: "#FFB703"),
        FilmStock(id: "fuji_c200", name: "富士 C200", subtitle: "日系青绿 · 街拍绿植", edgeCode: "HONGSHUXIA C200", iso: 200, themeColorHex: "#1E7A4C"),
        FilmStock(id: "kodak_portra400", name: "柯达 Portra 400", subtitle: "暖调人像 · 柔和肤色", edgeCode: "HONGSHUXIA PORTRA", iso: 400, themeColorHex: "#E09F3E"),
        FilmStock(id: "cinestill_800t", name: "Cinestill 800T", subtitle: "电影夜景 · 高光红晕", edgeCode: "HONGSHUXIA 800T", iso: 800, themeColorHex: "#C1292E"),
        FilmStock(id: "ilford_hp5", name: "伊尔福 HP5", subtitle: "高反差黑白 · 粗颗粒", edgeCode: "HONGSHUXIA HP5", iso: 400, themeColorHex: "#6C757D"),
        FilmStock(id: "agfa_100", name: "爱克发 Vista 100", subtitle: "德味浓郁 · 高饱和复古", edgeCode: "HONGSHUXIA AGFA", iso: 100, themeColorHex: "#D9381E"),
        FilmStock(id: "hasselblad_120_400h", name: "哈苏 120 · Pro 400H", subtitle: "中画幅色彩 · 细腻空气感", edgeCode: "FUJIFILM 120 PRO 400H", iso: 400, themeColorHex: "#0077B6")
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

// 严格对应“一卷胶卷 = 一个暗盒”的数据结构
struct FilmRollData: Identifiable, Codable {
    var id: UUID = UUID()
    var rollNumber: Int
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

    /// 确保任何输入图像均旋转为横向正立，并裁切为 3:2 (135) 或 1:1 (120)
    func cropToLandscapeFilmAspectRatio(_ image: UIImage, format: FilmFormat) -> UIImage {
        let uprightImage = ensureLandscapeOrientation(image)
        guard let cgImg = uprightImage.cgImage else { return uprightImage }
        let width = CGFloat(cgImg.width)
        let height = CGFloat(cgImg.height)

        let targetRatio: CGFloat = (format == .medium120) ? 1.0 : (3.0 / 2.0)
        let cropRect: CGRect

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

        guard let croppedCG = cgImg.cropping(to: cropRect) else { return uprightImage }
        return UIImage(cgImage: croppedCG, scale: 1.0, orientation: .up)
    }

    /// 如果底层传感器输出了竖向图 (height > width)，将其逆时针旋转 90 度还原为横屏右手握持的正立画面
    private func ensureLandscapeOrientation(_ image: UIImage) -> UIImage {
        let size = image.size
        if size.width >= size.height {
            return image
        }
        let landscapeSize = CGSize(width: size.height, height: size.width)
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: landscapeSize, format: rendererFormat)
        return renderer.image { ctx in
            let cgCtx = ctx.cgContext
            cgCtx.translateBy(x: landscapeSize.width / 2.0, y: landscapeSize.height / 2.0)
            cgCtx.rotate(by: -.pi / 2.0)
            image.draw(in: CGRect(x: -size.width / 2.0, y: -size.height / 2.0, width: size.width, height: size.height))
        }
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
        return UIImage(cgImage: outCG, scale: 1.0, orientation: .up)
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

        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = current
        sharpen.sharpness = 0.35
        if let out = sharpen.outputImage { current = out }

        let grainLevel: CGFloat
        if stock.id == "ilford_hp5" {
            grainLevel = 0.10
        } else if stock.id == "kodak_ektar100" || stock.id == "fuji_pro400h" || stock.id == "hasselblad_120_400h" {
            grainLevel = 0.022
        } else {
            grainLevel = 0.04
        }

        current = applyFilmGrainAndVignette(to: current, extent: extent, grainAmount: grainLevel)

        guard let outCG = context.createCGImage(current, from: extent) else { return sourceImage }
        return UIImage(cgImage: outCG, scale: 1.0, orientation: .up)
    }

    private func applyBuiltInStockProfile(to image: CIImage, stockID: String) -> CIImage {
        var img = image
        switch stockID {
        case "fuji_pro400h", "hasselblad_120_400h":
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
        vignette.intensity = 0.45
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

    func composeFinalExportImage(
        positiveImage: UIImage,
        stock: FilmStock,
        frame: FilmFrame,
        borderStyle: ExportBorderStyle,
        includeDateStamp: Bool
    ) -> UIImage {
        let croppedPhoto = cropToLandscapeFilmAspectRatio(positiveImage, format: frame.format)
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
        formatRenderer.scale = 1.0
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

                    let edgeStr = "\(stock.edgeCode)  \(frame.focalMM)" as NSString
                    edgeStr.draw(at: CGPoint(x: sideWidth, y: topBottomBarHeight * 0.08), withAttributes: goldAttrs)

                    let centerNumStr = String(format: "%02d", frame.frameNumber) as NSString
                    centerNumStr.draw(at: CGPoint(x: canvasSize.width * 0.48, y: topBottomBarHeight * 0.08), withAttributes: goldAttrs)

                    let rightTopStr = String(format: "▶ %02dA", frame.frameNumber) as NSString
                    rightTopStr.draw(at: CGPoint(x: canvasSize.width - sideWidth - fontSize * 4.5, y: topBottomBarHeight * 0.08), withAttributes: goldAttrs)

                    centerNumStr.draw(at: CGPoint(x: canvasSize.width * 0.48, y: canvasSize.height - topBottomBarHeight * 0.30), withAttributes: goldAttrs)
                    let isoStr = "\(stock.iso)" as NSString
                    isoStr.draw(at: CGPoint(x: canvasSize.width - sideWidth - fontSize * 2.5, y: canvasSize.height - topBottomBarHeight * 0.30), withAttributes: goldAttrs)
                } else {
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

// MARK: - 4. ViewModel (严格保证“一卷胶卷一个暗盒” + 修复 120/135 切换)
final class FilmCameraViewModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureSessionControlsDelegate {
    @Published var stage: AppStage = .shooting
    @Published var allStocks: [FilmStock] = FilmStock.builtInStocks
    @Published var currentStock: FilmStock = FilmStock.builtInStocks[0]
    @Published var currentFormat: FilmFormat = .mm135
    @Published var maxFramesPerRoll: Int = 12

    @Published var selectedLens: FocalLensOption = FocalLensOption.iPhone16ProLenses[1]
    private var isUsingTripleCamera: Bool = false

    // 胶卷仓库：每个元素代表整整一卷胶卷，绝不再是单张
    @Published var savedRolls: [FilmRollData] = []
    @Published var viewingRollID: UUID?

    // 当前相机里正在拍的这卷胶卷的唯一 ID 与帧数组
    @Published var activeRollID: UUID = UUID()
    @Published var frames: [FilmFrame] = []
    @Published var isShutterLocked: Bool = false
    @Published var advanceProgress: Double = 0.0
    @Published var isHardwareControlActive: Bool = false
    private var isAdvancingLock: Bool = false // 防止手势重复触发过片

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
                self.photoOutput.isHighResolutionCaptureEnabled = true
                self.photoOutput.maxPhotoQualityPrioritization = .quality
                if let maxDim = self.videoDevice?.activeFormat.supportedMaxPhotoDimensions.last {
                    self.photoOutput.maxPhotoDimensions = maxDim
                }
                // 锁定照片输出方向为横屏右手握持方向 (0度正立横屏)
                if let conn = self.photoOutput.connection(with: .video), conn.isVideoRotationAngleSupported(0) {
                    conn.videoRotationAngle = 0
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
            self.applyZoomFactor(for: self.selectedLens, animated: false)
        }
    }

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

    /// 装填全新一卷胶卷（如果上一卷已经拍了照片，会自动保留在仓库那唯一的一盒里，开启新的 activeRollID）
    func loadNewRoll(stock: FilmStock, format: FilmFormat, capacity: Int) {
        currentStock = stock
        currentFormat = format
        maxFramesPerRoll = capacity
        activeRollID = UUID()
        viewingRollID = activeRollID
        frames.removeAll()
        isShutterLocked = false
        isAdvancingLock = false
        advanceProgress = 0.0
        hardwareAdvanceSlider?.value = 0.0
        stage = .shooting
        HapticManager.shared.playFilmWoundLock()
    }

    /// 仅切换当前卷的 135 / 120 画幅或张数（不清空已拍照片，随时自由切换 135 与 120）
    func updateFormatOrCapacity(format: FilmFormat, capacity: Int) {
        currentFormat = format
        maxFramesPerRoll = capacity
        if let idx = savedRolls.firstIndex(where: { $0.id == activeRollID }) {
            savedRolls[idx].format = format
            savedRolls[idx].capacity = capacity
            saveSavedRolls()
        }
        HapticManager.shared.playRatchetTick()
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
        isAdvancingLock = false
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
            if let conn = self.photoOutput.connection(with: .video), conn.isVideoRotationAngleSupported(0) {
                conn.videoRotationAngle = 0
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
        let cropped = FilmColorEngine.shared.cropToLandscapeFilmAspectRatio(normalized, format: currentFormat)
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
        try? image.jpegData(compressionQuality: 1.0)?.write(to: url)

        DispatchQueue.main.async {
            let newFrame = FilmFrame(
                frameNumber: self.frames.count + 1,
                rawFileName: fileName,
                captureDate: Date(),
                focalMM: self.selectedLens.mmLabel,
                format: self.currentFormat
            )
            self.frames.append(newFrame)
            // 关键：将这张照片追加更新到当前这一卷的同一个暗盒中，绝不新建多余暗盒！
            self.upsertActiveRollInWarehouse(isDeveloped: false)
        }
    }

    /// 核心修复：保证当前这卷胶卷在仓库里永远只占 1 个金属暗盒
    private func upsertActiveRollInWarehouse(isDeveloped: Bool) {
        if let existingIdx = savedRolls.firstIndex(where: { $0.id == activeRollID }) {
            savedRolls[existingIdx].frames = frames
            savedRolls[existingIdx].stockID = currentStock.id
            savedRolls[existingIdx].format = currentFormat
            savedRolls[existingIdx].capacity = maxFramesPerRoll
            if isDeveloped {
                savedRolls[existingIdx].isDeveloped = true
            }
        } else {
            let nextNumber = (savedRolls.map { $0.rollNumber }.max() ?? 0) + 1
            let newRoll = FilmRollData(
                id: activeRollID,
                rollNumber: nextNumber,
                stockID: currentStock.id,
                format: currentFormat,
                capacity: maxFramesPerRoll,
                frames: frames,
                isDeveloped: isDeveloped,
                createdDate: Date()
            )
            savedRolls.insert(newRoll, at: 0)
        }
        viewingRollID = activeRollID
        saveSavedRolls()
    }

    func updateFilmAdvance(progress: Double) {
        guard isShutterLocked, !isAdvancingLock else { return }
        let clamped = min(max(progress, 0.0), 1.0)
        advanceProgress = clamped
        hardwareAdvanceSlider?.value = Float(clamped)

        let currentStep = Int(clamped * 12)
        if currentStep > lastHapticStep {
            lastHapticStep = currentStep
            HapticManager.shared.playRatchetTick()
        }

        if clamped >= 0.96 {
            isAdvancingLock = true
            completeFilmAdvance()
        }
    }

    private func completeFilmAdvance() {
        HapticManager.shared.playFilmWoundLock()
        advanceProgress = 1.0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.advanceProgress = 0.0
            self.hardwareAdvanceSlider?.value = 0.0
            if self.frames.count >= self.maxFramesPerRoll {
                self.upsertActiveRollInWarehouse(isDeveloped: false)
                self.viewingRollID = self.activeRollID
                self.stage = .darkroom
                self.darkroomRemainingSeconds = self.darkroomTotalSeconds
                self.isDeveloping = false
            } else {
                self.isShutterLocked = false
                self.isAdvancingLock = false
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
        let targetID = viewingRollID ?? activeRollID
        if let idx = savedRolls.firstIndex(where: { $0.id == targetID }) {
            savedRolls[idx].isDeveloped = true
            frames = savedRolls[idx].frames
            saveSavedRolls()
        }
        HapticManager.shared.playFilmWoundLock()
        stage = .lightTableScanner
    }

    /// 从胶卷仓库点击某一盒胶卷进入看片台
    func openRollFromWarehouse(_ roll: FilmRollData) {
        viewingRollID = roll.id
        frames = roll.frames
        if let stock = allStocks.first(where: { $0.id == roll.stockID }) {
            currentStock = stock
        }
        currentFormat = roll.format
        stage = .lightTableScanner
    }

    /// 从看片台返回拍摄界面：如果刚才那卷已经拍满了，自动装入一卷新胶卷准备拍摄
    func returnToCameraFromScanner() {
        if let currentRoll = savedRolls.first(where: { $0.id == activeRollID }),
           currentRoll.frames.count >= currentRoll.capacity {
            loadNewRoll(stock: currentStock, format: currentFormat, capacity: maxFramesPerRoll)
        } else {
            if let activeRoll = savedRolls.first(where: { $0.id == activeRollID }) {
                frames = activeRoll.frames
            }
            viewingRollID = activeRollID
            stage = .shooting
        }
    }

    func syncCurrentFramesToWarehouse() {
        let targetID = viewingRollID ?? activeRollID
        if let idx = savedRolls.firstIndex(where: { $0.id == targetID }) {
            savedRolls[idx].frames = frames
            saveSavedRolls()
        }
    }

    /// 一键清除旧版残留的错误单张碎片暗盒
    func clearAllWarehouseRolls() {
        savedRolls.removeAll()
        saveSavedRolls()
        loadNewRoll(stock: currentStock, format: currentFormat, capacity: maxFramesPerRoll)
    }

    func deleteRoll(_ roll: FilmRollData) {
        savedRolls.removeAll { $0.id == roll.id }
        saveSavedRolls()
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
        if let data = try? JSONEncoder().encode(savedRolls) { UserDefaults.standard.set(data, forKey: "SavedFilmRollsWarehouse_v2") }
    }

    private func loadSavedRolls() {
        if let data = UserDefaults.standard.data(forKey: "SavedFilmRollsWarehouse_v2"),
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

// MARK: - 5. 横屏相机实时取景器 (自动锁定摄像头画面为横向正立，拒绝歪斜 90 度)
struct LandscapeCameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var onPhysicalPress: () -> Void

    class VideoPreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var pressHandler: (() -> Void)?

        override func layoutSubviews() {
            super.layoutSubviews()
            // 关键：当把手机逆时针横过来握持（灵动岛在左侧，快门在右侧）时，设置预览旋转角为 0 度，画面完全正立！
            if let connection = videoPreviewLayer.connection {
                if connection.isVideoRotationAngleSupported(0) {
                    connection.videoRotationAngle = 0
                }
            }
        }

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
    func updateUIView(_ uiView: VideoPreviewView, context: Context) {
        uiView.pressHandler = onPhysicalPress
    }
}

@main
struct RetroFilmCamApp: App {
    @StateObject private var vm = FilmCameraViewModel()
    var body: some Scene {
        WindowGroup {
            ZStack {
                Color.black.ignoresSafeArea()
                switch vm.stage {
                case .shooting:
                    VintageCameraShootingView(vm: vm)
                case .darkroom:
                    DarkroomDevelopingView(vm: vm)
                case .lightTableScanner:
                    LightTableScannerView(vm: vm)
                }
            }
            .preferredColorScheme(.dark)
            .statusBarHidden(true)
        }
    }
}

// MARK: - 舞台一：100% 还原你图一设计的【横屏握持旁轴相机布局】
struct VintageCameraShootingView: View {
    @ObservedObject var vm: FilmCameraViewModel
    @State private var showWarehouseSheet = false
    @State private var showRollSheet = false
    @State private var showCubeImporter = false
    @State private var importAlertMessage: String?

    var body: some View {
        GeometryReader { fullGeo in
            let isPortraitContainer = fullGeo.size.height > fullGeo.size.width
            let landW = max(fullGeo.size.width, fullGeo.size.height)
            let landH = min(fullGeo.size.width, fullGeo.size.height)

            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.05).ignoresSafeArea()

                // 横向四栏式徕卡旁轴相机主布局（完全对齐你的图一）
                HStack(spacing: 12) {
                    // 【左一栏】：竖向钛金属相机顶盖（下侧胶卷小窗、中间帧数圆窗、上方机械过片拨杆）
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.38, green: 0.38, blue: 0.36),
                                        Color(red: 0.18, green: 0.18, blue: 0.17),
                                        Color(red: 0.28, green: 0.27, blue: 0.25),
                                        Color(red: 0.12, green: 0.12, blue: 0.11)
                                    ],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(
                                        LinearGradient(colors: [.white.opacity(0.45), .clear, .white.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                        lineWidth: 1.2
                                    )
                            )
                            .shadow(color: .black.opacity(0.85), radius: 8, x: 0, y: 4)

                        HStack(spacing: 6) {
                            // 左侧：镌刻铭文 + 沉头螺丝 + 测距小窗
                            VStack {
                                CameraScrewIcon()
                                RoundedRectangle(cornerRadius: 2.5)
                                    .fill(LinearGradient(colors: [.white.opacity(0.8), .gray.opacity(0.35), .white.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                                    .frame(width: 10, height: 26)
                                    .overlay(RoundedRectangle(cornerRadius: 2.5).stroke(Color.black, lineWidth: 1))
                                    .padding(.top, 4)

                                Spacer()

                                Text("HONGSHUXIA OPTIK · \(vm.selectedLens.mmLabel)")
                                    .font(.system(size: 8, weight: .bold, design: .serif))
                                    .tracking(1.6)
                                    .foregroundColor(Color(red: 0.92, green: 0.88, blue: 0.80).opacity(0.85))
                                    .fixedSize()
                                    .rotationEffect(.degrees(-90))
                                    .frame(width: 14, height: 155)

                                Spacer()
                                CameraScrewIcon()
                            }
                            .padding(.vertical, 12)

                            // 右侧：过片扳手(上) + 计数器圆窗(中) + 胶卷型号窗(下)
                            VStack(spacing: 12) {
                                VerticalMechanicalLever(
                                    isLocked: vm.isShutterLocked,
                                    progress: vm.advanceProgress
                                ) { newProgress in
                                    vm.updateFilmAdvance(progress: newProgress)
                                }

                                Spacer()

                                // 圆形帧数计数器
                                ZStack {
                                    Circle()
                                        .fill(Color.black)
                                        .frame(width: 42, height: 42)
                                        .overlay(Circle().stroke(LinearGradient(colors: [.gray, .black, .white.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2))
                                    VStack(spacing: 0) {
                                        Text("FRAME").font(.system(size: 5.5, weight: .bold, design: .monospaced)).foregroundColor(.gray)
                                        Text(String(format: "%02d", vm.frames.count))
                                            .font(.system(size: 15, weight: .black, design: .monospaced))
                                            .foregroundColor(vm.isShutterLocked ? .orange : Color(red: 0.95, green: 0.92, blue: 0.82))
                                    }
                                }

                                Spacer()

                                // 底部胶卷型号暗盒小窗
                                Button { showRollSheet = true } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        RoundedRectangle(cornerRadius: 1.5)
                                            .fill(Color(hex: vm.currentStock.themeColorHex))
                                            .frame(width: 34, height: 4)
                                        Text(vm.currentStock.name)
                                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                            .foregroundColor(Color(red: 1.0, green: 0.86, blue: 0.38))
                                            .lineLimit(1)
                                        Text("\(vm.currentFormat == .medium120 ? "120" : "135") · \(vm.maxFramesPerRoll)EXP")
                                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.75))
                                    }
                                    .padding(7)
                                    .frame(width: 56)
                                    .background(Color.black.opacity(0.85))
                                    .cornerRadius(6)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.2), lineWidth: 1))
                                }
                            }
                            .padding(.vertical, 10)
                        }
                        .padding(.horizontal, 8)
                    }
                    .frame(width: 84, height: landH - 24)

                    // 【中间核心栏】：荔枝纹蒙皮机身 + 顶部红标/胶卷仓库 + 横向正立大取景窗 + 底部焦段按钮排
                    ZStack {
                        RoundedRectangle(cornerRadius: 22)
                            .fill(Color(red: 0.08, green: 0.08, blue: 0.09))
                            .overlay(LeatheretteGrainCanvas().clipShape(RoundedRectangle(cornerRadius: 22)).opacity(0.35))
                            .overlay(
                                RoundedRectangle(cornerRadius: 22)
                                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.25), .black.opacity(0.95), .white.opacity(0.12)], startPoint: .top, endPoint: .bottom), lineWidth: 2)
                            )
                            .shadow(color: .black.opacity(0.9), radius: 12, x: 0, y: 8)

                        VStack(spacing: 10) {
                            // 机身顶部：左侧“红树下”红标 + 右侧“胶卷仓库”入口
                            HStack {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(
                                            RadialGradient(colors: [Color(red: 0.92, green: 0.16, blue: 0.13), Color(red: 0.60, green: 0.06, blue: 0.05)], center: .topLeading, startRadius: 2, endRadius: 26)
                                        )
                                        .frame(width: 66, height: 24)
                                    Text("红树下")
                                        .font(.system(size: 11.5, weight: .bold, design: .serif))
                                        .foregroundColor(.white)
                                }
                                .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 2)

                                Spacer()

                                // 一卷一盒的胶卷仓库入口
                                Button {
                                    showWarehouseSheet = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "cylinder.split.1x2.fill")
                                            .foregroundColor(.yellow)
                                        Text("胶卷仓库 (\(vm.savedRolls.count)卷)")
                                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                            .foregroundColor(.yellow)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.black.opacity(0.8))
                                    .cornerRadius(14)
                                    .overlay(Capsule().stroke(Color.yellow.opacity(0.55), lineWidth: 1))
                                }
                            }
                            .padding(.horizontal, 24)

                            // 中央横向正立大取景框（135 为 3:2 宽屏，120 为 1:1 哈苏方画幅）
                            let vfHeight: CGFloat = min(landH - 122, 224)
                            let vfWidth: CGFloat = (vm.currentFormat == .medium120) ? vfHeight : (vfHeight * 1.5)

                            ZStack {
                                LandscapeCameraPreviewView(session: vm.session) {
                                    vm.handlePhysicalCameraButtonPress()
                                }
                                .frame(width: vfWidth, height: vfHeight)
                                .clipShape(RoundedRectangle(cornerRadius: 10))

                                // 徕卡旁轴明亮框线与中心黄斑对焦区
                                ZStack {
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.white.opacity(0.78), style: StrokeStyle(lineWidth: 1.1, dash: [8, 4]))
                                        .padding(12)

                                    Rectangle()
                                        .fill(Color.yellow.opacity(0.16))
                                        .frame(width: 46, height: 30)
                                        .overlay(Rectangle().stroke(Color.yellow.opacity(0.65), lineWidth: 0.8))

                                    VStack {
                                        Spacer()
                                        HStack {
                                            Spacer()
                                            Text("\(vm.selectedLens.mmLabel) · \(vm.currentFormat == .medium120 ? "120 6x6" : "3:2")")
                                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                                .foregroundColor(.yellow)
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 2.5)
                                                .background(Color.black.opacity(0.65))
                                                .cornerRadius(4)
                                                .padding(16)
                                        }
                                    }
                                }
                                .frame(width: vfWidth, height: vfHeight)
                                .allowsHitTesting(false)

                                if vm.isShutterLocked {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.black.opacity(0.75))
                                        .frame(width: vfWidth, height: vfHeight)
                                        .overlay(
                                            VStack(spacing: 8) {
                                                Image(systemName: "hand.draw.fill").font(.system(size: 26)).foregroundColor(.orange)
                                                Text(vm.frames.count >= vm.maxFramesPerRoll ? "整卷已拍满！请拨动右侧滑轨送入暗房" : "快门已锁死 · 请滑动右侧过片条或实体按键过片")
                                                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                                    .foregroundColor(.white)
                                                    .multilineTextAlignment(.center)
                                                    .padding(.horizontal, 18)
                                            }
                                        )
                                }
                            }
                            .padding(5)
                            .background(RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [Color(white: 0.28), Color(white: 0.08), Color(white: 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                            .shadow(color: .black.opacity(0.9), radius: 8, x: 0, y: 5)
                            .animation(.spring(response: 0.32), value: vm.currentFormat)

                            // 底部 iPhone 16 Pro 六颗经典焦段按钮排 (13mm ~ 120mm)
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
                                                .font(.system(size: 7.5, weight: .semibold))
                                                .foregroundColor(isSelected ? .black.opacity(0.78) : .gray)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(isSelected ? Color.yellow : Color.black.opacity(0.75))
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(isSelected ? Color.orange : Color.white.opacity(0.15), lineWidth: 1)
                                        )
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 10)
                    }
                    .frame(maxWidth: .infinity, maxHeight: landH - 24)

                    // 【右二栏】：竖向过片滑轨条（右手大拇指上下滑动即可过片）
                    VerticalSlideAdvanceBar(
                        isLocked: vm.isShutterLocked,
                        progress: vm.advanceProgress
                    ) { newProgress in
                        vm.updateFilmAdvance(progress: newProgress)
                    }
                    .frame(width: 52, height: landH - 24)

                    // 【最右侧栏】：右手握持三联转盘（上：装卷/120，中：红色机械快门，下：LUT工坊）
                    VStack(spacing: 22) {
                        Button { showRollSheet = true } label: {
                            KnurledMetalDialButton(
                                icon: "film.stack.fill",
                                title: "装卷/120",
                                accentColor: Color(red: 0.98, green: 0.82, blue: 0.32)
                            )
                        }

                        Button { vm.capturePhoto() } label: {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [Color(white: 0.72), Color(white: 0.25), Color(white: 0.52)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 78, height: 78)
                                    .shadow(color: .black.opacity(0.85), radius: 6, x: 0, y: 4)
                                Circle()
                                    .stroke(Color.black.opacity(0.6), style: StrokeStyle(lineWidth: 3, dash: [2, 2]))
                                    .frame(width: 72, height: 72)
                                Circle()
                                    .fill(
                                        RadialGradient(
                                            colors: vm.isShutterLocked ? [Color(white: 0.3), Color(white: 0.15)] : [Color(red: 0.92, green: 0.18, blue: 0.14), Color(red: 0.55, green: 0.06, blue: 0.05)],
                                            center: .topLeading, startRadius: 4, endRadius: 40
                                        )
                                    )
                                    .frame(width: 58, height: 58)
                                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                                Circle()
                                    .fill(Color(white: 0.1))
                                    .frame(width: 15, height: 15)
                                    .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.2))
                            }
                        }
                        .disabled(vm.isShutterLocked)

                        Button { showCubeImporter = true } label: {
                            KnurledMetalDialButton(
                                icon: "cube.transparent.fill",
                                title: "LUT工坊",
                                accentColor: Color(red: 0.85, green: 0.82, blue: 0.75)
                            )
                        }
                    }
                    .frame(width: 84, height: landH - 24)
                }
                .padding(.horizontal, 14)
                .frame(width: landW, height: landH)
                // 当工程处于竖屏容器时，自动顺时针旋转 90 度铺满全屏，横握手机时所有 UI 与摄像头画面完全正立！
                .rotationEffect(isPortraitContainer ? .degrees(90) : .degrees(0))
                .frame(width: fullGeo.size.width, height: fullGeo.size.height)
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showWarehouseSheet) {
            FilmWarehouseView(vm: vm)
        }
        .sheet(isPresented: $showRollSheet) {
            FilmRollSelectorSheet(vm: vm)
        }
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

// 顶盖竖向过片扳手
struct VerticalMechanicalLever: View {
    let isLocked: Bool
    let progress: Double
    let onDragProgress: (Double) -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Capsule()
                .fill(Color(red: 0.05, green: 0.05, blue: 0.05))
                .frame(width: 36, height: 96)
                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                .overlay(
                    Text(isLocked ? "WIND" : "READY")
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundColor(isLocked ? .orange : Color(red: 0.35, green: 0.85, blue: 0.5))
                        .rotationEffect(.degrees(-90))
                )

            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.92), Color(white: 0.42)], startPoint: .leading, endPoint: .trailing))
                .frame(width: 30, height: 30)
                .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1.5))
                .offset(y: -CGFloat(progress) * 60 - 3)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            guard isLocked else { return }
                            onDragProgress(Double(-value.translation.height / 60.0))
                        }
                        .onEnded { _ in
                            if progress < 0.96 { withAnimation(.spring()) { onDragProgress(0.0) } }
                        }
                )
        }
    }
}

// 右侧竖向拇指滑动过片条（完美贴合图一右侧滑轨）
struct VerticalSlideAdvanceBar: View {
    let isLocked: Bool
    let progress: Double
    let onSlideProgress: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(white: 0.1))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))

                // 刻度线
                VStack(spacing: 8) {
                    ForEach(0..<18, id: \.self) { idx in
                        Rectangle()
                            .fill(idx % 4 == 0 ? Color.orange.opacity(0.75) : Color.white.opacity(0.2))
                            .frame(width: idx % 4 == 0 ? 14 : 7, height: 1.5)
                    }
                }

                // 顶部百分比提示
                VStack {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundColor(.orange)
                        .padding(.top, 10)
                    Spacer()
                }

                // 拇指滑块
                Capsule()
                    .fill(isLocked ? Color.orange : Color.gray.opacity(0.35))
                    .frame(width: 34, height: 48)
                    .overlay(
                        Image(systemName: "chevron.up.2")
                            .font(.system(size: 11, weight: .black))
                            .foregroundColor(.black)
                    )
                    .offset(y: -(geo.size.height - 60) * CGFloat(progress) - 6)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isLocked else { return }
                        let invertedY = geo.size.height - value.location.y
                        onSlideProgress(Double(invertedY / geo.size.height))
                    }
                    .onEnded { _ in
                        if progress < 0.96 { withAnimation(.spring()) { onSlideProgress(0.0) } }
                    }
            )
        }
    }
}

// MARK: - 拟物化“胶卷仓库”界面（修复后：严格一卷胶卷一个金属暗盒，绝不按单张拆分）
struct FilmWarehouseView: View {
    @ObservedObject var vm: FilmCameraViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.06).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("一卷一盒 · 点击任意金属暗盒进入看片台扫描整卷")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            Spacer()
                            if !vm.savedRolls.isEmpty {
                                Button(role: .destructive) {
                                    vm.clearAllWarehouseRolls()
                                } label: {
                                    Text("清空仓库")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                        if vm.savedRolls.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "cylinder.split.1x2")
                                    .font(.system(size: 42))
                                    .foregroundColor(.gray)
                                Text("胶卷仓库暂无存档\n每拍一卷胶卷，会在这里生成一个金属暗盒（内含整卷底片）")
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                                ForEach(vm.savedRolls) { roll in
                                    let stock = vm.allStocks.first(where: { $0.id == roll.stockID }) ?? vm.allStocks[0]
                                    Button {
                                        vm.openRollFromWarehouse(roll)
                                        dismiss()
                                    } label: {
                                        VStack(spacing: 8) {
                                            ZStack {
                                                // 金属胶卷轴心
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(Color(white: 0.28))
                                                    .frame(width: 34, height: 92)
                                                // 胶卷金属罐体
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(
                                                        LinearGradient(
                                                            colors: [Color(hex: stock.themeColorHex), Color.black.opacity(0.9)],
                                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                                        )
                                                    )
                                                    .frame(height: 78)
                                                    .overlay(
                                                        VStack(spacing: 3) {
                                                            Text("第 \(String(format: "%02d", roll.rollNumber)) 卷 · \(roll.format == .medium120 ? "120 6x6" : "135")")
                                                                .font(.system(size: 8.5, weight: .black, design: .monospaced))
                                                                .foregroundColor(.white.opacity(0.85))
                                                            Text(stock.name)
                                                                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                                                                .foregroundColor(.white)
                                                                .lineLimit(1)
                                                            Text("内含 \(roll.frames.count) / \(roll.capacity) 张底片")
                                                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                                .foregroundColor(.yellow)
                                                        }
                                                        .padding(.horizontal, 6)
                                                    )
                                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.25), lineWidth: 1.2))
                                            }
                                            Text(roll.frames.count >= roll.capacity ? "● 已拍满整卷 · 点击扫描" : "● 拍摄中 (\(roll.frames.count)/\(roll.capacity)) · 点击查看")
                                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                                .foregroundColor(roll.frames.count >= roll.capacity ? .green : .orange)
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
            .navigationTitle("红树下 · 胶卷暗盒仓库")
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
                .frame(width: 58, height: 58)
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

// MARK: - 胶卷与 135/120 画幅装填仓（已修复：切换 135 或 120 立即 100% 生效，绝不卡死在 120）
struct FilmRollSelectorSheet: View {
    @ObservedObject var vm: FilmCameraViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. 选择胶卷画幅规格 (点击立即切换 135 / 120)").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.gray)
                        Picker(
                            "胶卷画幅",
                            selection: Binding(
                                get: { vm.currentFormat },
                                set: { newFormat in
                                    vm.updateFormatOrCapacity(format: newFormat, capacity: vm.maxFramesPerRoll)
                                }
                            )
                        ) {
                            ForEach(FilmFormat.allCases) { fmt in
                                Text(fmt.rawValue).tag(fmt)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("2. 选择每卷张数").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.gray).padding(.top, 4)
                        Picker(
                            "每卷张数",
                            selection: Binding(
                                get: { vm.maxFramesPerRoll },
                                set: { newCap in
                                    vm.updateFormatOrCapacity(format: vm.currentFormat, capacity: newCap)
                                }
                            )
                        ) {
                            Text("6 EXP · 爽快半卷").tag(6)
                            Text("12 EXP · 标准整卷").tag(12)
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                    Text("3. 点击下方任意胶卷开启新的一卷（任意胶卷均支持 135 与 120）").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.gray).padding(.horizontal, 16)

                    ForEach(vm.allStocks) { stock in
                        Button {
                            // 严格尊重你顶部选中的 135 或 120 画幅，不再强制锁定
                            vm.loadNewRoll(stock: stock, format: vm.currentFormat, capacity: vm.maxFramesPerRoll)
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.22)).frame(width: 22, height: 60)
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(LinearGradient(colors: [Color(hex: stock.themeColorHex), Color.black.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: 44, height: 50)
                                        .overlay(VStack(spacing: 1) {
                                            Text(vm.currentFormat == .medium120 ? "120" : "135").font(.system(size: 7.5, weight: .black, design: .monospaced)).foregroundColor(.white.opacity(0.85))
                                            Text("\(stock.iso)").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(.white)
                                        })
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(stock.name).font(.system(size: 16, weight: .heavy, design: .monospaced)).foregroundColor(.white)
                                        if vm.currentStock.id == stock.id {
                                            Text("当前装填").font(.system(size: 8.5, weight: .black, design: .monospaced)).padding(.horizontal, 5).padding(.vertical, 2).background(Color.orange).foregroundColor(.black).cornerRadius(3)
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
                ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() }.foregroundColor(.orange) }
            }
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
                Text("当前卷：\(vm.currentStock.name)（整卷共 \(vm.frames.count) 张潜影）").font(.system(size: 12)).foregroundColor(.red.opacity(0.85))

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
            VStack(spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("HONGSHUXIA LIGHT TABLE 5500K").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                        Text("本卷共 \(vm.frames.count) 张 · 点击任意底片自动放大居中审片").font(.system(size: 9.5)).foregroundColor(.black.opacity(0.65))
                    }
                    Spacer()
                    Button { vm.returnToCameraFromScanner() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "camera.fill")
                            Text("返回拍摄")
                        }
                        .font(.system(size: 11, weight: .bold)).foregroundColor(.white).padding(.horizontal, 10).padding(.vertical, 6).background(Color.black).cornerRadius(6)
                    }
                }

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

            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    let cardWidth: CGFloat = 152 * zoomScale
                    let columns = [GridItem(.adaptive(minimum: max(110, cardWidth)), spacing: 12)]

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(Array(vm.frames.enumerated()), id: \.element.id) { idx, frame in
                            let rawImg = vm.loadRawImage(for: frame)
                            let croppedRaw = FilmColorEngine.shared.cropToLandscapeFilmAspectRatio(rawImg, format: frame.format)
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
                                        zoomScale = 1.0
                                    } else {
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
                    Button {
                        for i in 0..<vm.frames.count {
                            vm.frames[i].isScanned = true
                        }
                        vm.syncCurrentFramesToWarehouse()
                        HapticManager.shared.playFilmWoundLock()
                        showToast("已一键扫描本卷全部 \(vm.frames.count) 张底片！")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "wand.and.stars")
                            Text("一键全扫")
                        }
                        .font(.system(size: 11.5, weight: .bold)).foregroundColor(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(Color.cyan).cornerRadius(8)
                    }

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
        let croppedRaw = FilmColorEngine.shared.cropToLandscapeFilmAspectRatio(rawImg, format: frame.format)
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
            let croppedRaw = FilmColorEngine.shared.cropToLandscapeFilmAspectRatio(rawImg, format: frame.format)
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

// MARK: - 看片台上的单张横向齿孔底片组件
struct LightTableContactCell: View {
    let image: UIImage
    let stock: FilmStock
    let frame: FilmFrame
    let cellWidth: CGFloat
    let isSelected: Bool

    var body: some View {
        let photoHeight = (frame.format == .medium120) ? cellWidth : (cellWidth * 0.66)

        VStack(spacing: 4) {
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