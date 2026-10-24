import SwiftUI
import AVFoundation
import AVKit
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreHaptics
import Photos
import UniformTypeIdentifiers
import AudioToolbox

// MARK: - 1. 胶卷画幅、焦段、闪光灯与数据模型
enum FilmFormat: String, Codable, CaseIterable, Identifiable {
    case mm135 = "135 全画幅 (3:2)"
    case medium120 = "120 中画幅 (6x6)"
    var id: String { rawValue }
}

enum CameraFlashOption: String, Codable, CaseIterable {
    case off = "OFF"
    case auto = "AUTO"
    case on = "ON"

    var iconName: String {
        switch self {
        case .off: return "bolt.slash.fill"
        case .auto: return "bolt.badge.automatic.fill"
        case .on: return "bolt.fill"
        }
    }

    var avFlashMode: AVCaptureDevice.FlashMode {
        switch self {
        case .off: return .off
        case .auto: return .auto
        case .on: return .on
        }
    }

    func next() -> CameraFlashOption {
        switch self {
        case .off: return .auto
        case .auto: return .on
        case .on: return .off
        }
    }
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
    var cubeFileName: String
    var cubeDimension: Int = 32

    static let builtInStocks: [FilmStock] = [
        FilmStock(id: "fuji_pro400h", name: "Fuji Pro 400H", subtitle: "传奇人像 · 清透青绿与柔粉肤色", edgeCode: "FUJI PRO 400H", iso: 400, themeColorHex: "#2EC4B6", cubeFileName: "fuji_pro400h.cube"),
        FilmStock(id: "kodak_ektar100", name: "Kodak Ektar 100", subtitle: "风光之王 · 极致细腻高饱和", edgeCode: "KODAK EKTAR 100", iso: 100, themeColorHex: "#E71D36", cubeFileName: "kodak_ektar100.cube"),
        FilmStock(id: "kodak_gold200", name: "Kodak 金 200", subtitle: "复古金黄 · 温暖午后阳光感", edgeCode: "KODAK GOLD 200", iso: 200, themeColorHex: "#FFB703", cubeFileName: "kodak_gold200.cube"),
        FilmStock(id: "fuji_c200", name: "富士 C200", subtitle: "日系青绿 · 街拍绿植", edgeCode: "HONGSHUXIA C200", iso: 200, themeColorHex: "#1E7A4C", cubeFileName: "fuji_c200.cube"),
        FilmStock(id: "kodak_portra400", name: "柯达 Portra 400", subtitle: "暖调人像 · 柔和肤色", edgeCode: "HONGSHUXIA PORTRA", iso: 400, themeColorHex: "#E09F3E", cubeFileName: "kodak_portra400.cube"),
        FilmStock(id: "cinestill_800t", name: "Cinestill 800T", subtitle: "电影夜景 · 高光红晕", edgeCode: "HONGSHUXIA 800T", iso: 800, themeColorHex: "#C1292E", cubeFileName: "cinestill_800t.cube"),
        FilmStock(id: "ilford_hp5", name: "伊尔福 HP5", subtitle: "高反差黑白 · 经典银盐", edgeCode: "HONGSHUXIA HP5", iso: 400, themeColorHex: "#6C757D", cubeFileName: "ilford_hp5.cube"),
        FilmStock(id: "agfa_100", name: "爱克发 Vista 100", subtitle: "德味浓郁 · 高饱和复古", edgeCode: "HONGSHUXIA AGFA", iso: 100, themeColorHex: "#D9381E", cubeFileName: "agfa_100.cube"),
        FilmStock(id: "hasselblad_120_400h", name: "哈苏 120 · Pro 400H", subtitle: "中画幅色彩 · 细腻空气感", edgeCode: "FUJIFILM 120 PRO 400H", iso: 400, themeColorHex: "#0077B6", cubeFileName: "hasselblad_120_400h.cube")
    ]
}

struct FilmFrame: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var frameNumber: Int
    var fallbackJPGName: String
    var captureDate: Date
    var focalMM: String = "24mm"
    var format: FilmFormat = .mm135
    var isScanned: Bool = false

    // 四项核心调整参数
    var warmthWB: Double = 0.0    // 色温 (-1.0 ~ 1.0)
    var exposureEV: Double = 0.0  // 曝光 (-1.5 ~ 1.5)
    var highlights: Double = 0.0  // 高光 (-1.0 ~ 1.0)
    var shadows: Double = 0.0     // 阴影 (-1.0 ~ 1.0)
}

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
    case sprocket35mm = "齿孔黑边"
    case clean = "无边框"
    var id: String { rawValue }
}

enum AppStage: String, Codable {
    case shooting
    case darkroom
    case lightTableScanner
}

// 看片台两个大类按钮 + 四个子参数
enum DialGroup: Int {
    case exposureAndTemp = 0 // 按钮1：曝光与色温
    case toneRecovery = 1    // 按钮2：高光与阴影
}

enum DialParam: String, CaseIterable {
    case exposure = "曝光 EV"
    case warmth = "色温 WB"
    case highlights = "高光 HL"
    case shadows = "阴影 SH"
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
        } catch {}
    }

    func playRatchetTick(intensity: Float = 0.75, sharpness: Float = 0.9) {
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.impactOccurred(intensity: CGFloat(intensity))
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
        soft.impactOccurred(intensity: 0.4)
    }
}

// MARK: - 3. 标准 .cube 3D LUT 生成器 + 16-Bit 浮点色彩与高速缩略图缓存引擎
final class FilmColorEngine {
    static let shared = FilmColorEngine()

    private let context: CIContext = {
        let p3Space = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        return CIContext(options: [
            .workingColorSpace: p3Space,
            .outputColorSpace: p3Space,
            .workingFormat: CIFormat.RGBAh,
            .highQualityDownsample: true,
            .useSoftwareRenderer: false
        ])
    }()

    private var lutMemoryCache: [String: (dimension: Int, data: Data)] = [:]
    // 看片台高速缓存：避免双指缩放时重复计算 CoreImage 导致卡顿
    private let previewCache = NSCache<NSString, UIImage>()
    private let baseThumbnailCache = NSCache<NSString, UIImage>()

    private let lutDirectoryURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("FilmLUTs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {
        previewCache.countLimit = 120
        baseThumbnailCache.countLimit = 120
        generateBuiltInCubeFilesIfNeeded()
    }

    func clearPreviewCache(for frameID: UUID) {
        // 当用户滑动四分之一圆转盘修改参数时，自动通过新 key 渲染
    }

    func generateBuiltInCubeFilesIfNeeded() {
        DispatchQueue.global(qos: .userInitiated).async {
            for stock in FilmStock.builtInStocks {
                let binURL = self.lutDirectoryURL.appendingPathComponent("\(stock.id).lutbin")
                let cubeURL = self.lutDirectoryURL.appendingPathComponent(stock.cubeFileName)
                if FileManager.default.fileExists(atPath: binURL.path),
                   let data = try? Data(contentsOf: binURL) {
                    self.lutMemoryCache[stock.cubeFileName] = (32, data)
                    continue
                }
                let (floatData, cubeText) = self.synthesize3DLUT(for: stock.id, dimension: 32)
                try? floatData.write(to: binURL)
                try? cubeText.write(to: cubeURL, atomically: true, encoding: .utf8)
                self.lutMemoryCache[stock.cubeFileName] = (32, floatData)
            }
        }
    }

    private func filmicCurve(_ x: Float, contrast: Float, toeLift: Float, shoulderRoll: Float) -> Float {
        let clamped = min(max(x, 0.0), 1.0)
        let smooth = clamped * clamped * (3.0 - 2.0 * clamped)
        let mixed = clamped + (smooth - clamped) * contrast
        let rolled = mixed / (1.0 + shoulderRoll * max(0.0, mixed - 0.65))
        let lifted = toeLift + (1.0 - toeLift) * rolled
        return min(max(lifted, 0.0), 1.0)
    }

    private func synthesize3DLUT(for stockID: String, dimension: Int) -> (Data, String) {
        var floats: [Float] = []
        floats.reserveCapacity(dimension * dimension * dimension * 4)

        var lines: [String] = [
            "TITLE \"\(stockID.uppercased())_HONGSHUXIA_FILM\"",
            "LUT_3D_SIZE \(dimension)",
            "DOMAIN_MIN 0.0 0.0 0.0",
            "DOMAIN_MAX 1.0 1.0 1.0"
        ]

        let denom = Float(dimension - 1)
        for bIndex in 0..<dimension {
            for gIndex in 0..<dimension {
                for rIndex in 0..<dimension {
                    let rIn = Float(rIndex) / denom
                    let gIn = Float(gIndex) / denom
                    let bIn = Float(bIndex) / denom

                    let (rOut, gOut, bOut) = evaluateFilmScience(r: rIn, g: gIn, b: bIn, stockID: stockID)
                    floats.append(rOut)
                    floats.append(gOut)
                    floats.append(bOut)
                    floats.append(1.0)

                    lines.append(String(format: "%.5f %.5f %.5f", rOut, gOut, bOut))
                }
            }
        }

        let data = Data(bytes: floats, count: floats.count * MemoryLayout<Float>.size)
        return (data, lines.joined(separator: "\n"))
    }

    private func evaluateFilmScience(r: Float, g: Float, b: Float, stockID: String) -> (Float, Float, Float) {
        let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let shadowWeight = pow(1.0 - luma, 2.2)
        let highlightWeight = pow(luma, 1.8)

        var nr = r, ng = g, nb = b

        switch stockID {
        case "fuji_pro400h", "hasselblad_120_400h":
            nr = filmicCurve(r * 0.97 + g * 0.03, contrast: 0.20, toeLift: 0.028, shoulderRoll: 0.07)
            ng = filmicCurve(g * 1.01 + b * 0.02, contrast: 0.22, toeLift: 0.034, shoulderRoll: 0.06)
            nb = filmicCurve(b * 1.02 + g * 0.03, contrast: 0.18, toeLift: 0.036, shoulderRoll: 0.05)
            let newLuma = 0.2126 * nr + 0.7152 * ng + 0.0722 * nb
            nr = newLuma + (nr - newLuma) * 0.94 + highlightWeight * 0.01
            ng = newLuma + (ng - newLuma) * 0.97 + highlightWeight * 0.022
            nb = newLuma + (nb - newLuma) * 0.95 + shadowWeight * 0.018

        case "kodak_ektar100":
            nr = filmicCurve(r * 1.05 - g * 0.02, contrast: 0.40, toeLift: 0.012, shoulderRoll: 0.06)
            ng = filmicCurve(g * 1.01 - b * 0.01, contrast: 0.38, toeLift: 0.012, shoulderRoll: 0.06)
            nb = filmicCurve(b * 1.04 - r * 0.02, contrast: 0.40, toeLift: 0.015, shoulderRoll: 0.05)
            let newLuma = 0.2126 * nr + 0.7152 * ng + 0.0722 * nb
            nr = newLuma + (nr - newLuma) * 1.16
            ng = newLuma + (ng - newLuma) * 1.12
            nb = newLuma + (nb - newLuma) * 1.14

        case "kodak_gold200":
            nr = filmicCurve(r * 1.04 + g * 0.03, contrast: 0.30, toeLift: 0.024, shoulderRoll: 0.05)
            ng = filmicCurve(g * 1.00 + r * 0.02, contrast: 0.28, toeLift: 0.018, shoulderRoll: 0.06)
            nb = filmicCurve(b * 0.91 + g * 0.02, contrast: 0.25, toeLift: 0.012, shoulderRoll: 0.08)
            nr += highlightWeight * 0.032 + shadowWeight * 0.015
            ng += highlightWeight * 0.018
            nb -= highlightWeight * 0.022

        case "fuji_c200":
            nr = filmicCurve(r * 0.96 + g * 0.02, contrast: 0.28, toeLift: 0.024, shoulderRoll: 0.07)
            ng = filmicCurve(g * 1.02 + b * 0.02, contrast: 0.30, toeLift: 0.030, shoulderRoll: 0.05)
            nb = filmicCurve(b * 0.99 + g * 0.03, contrast: 0.26, toeLift: 0.028, shoulderRoll: 0.06)

        case "kodak_portra400":
            nr = filmicCurve(r * 1.03 + g * 0.03, contrast: 0.24, toeLift: 0.030, shoulderRoll: 0.07)
            ng = filmicCurve(g * 1.00 + r * 0.01, contrast: 0.22, toeLift: 0.025, shoulderRoll: 0.07)
            nb = filmicCurve(b * 0.94 + g * 0.02, contrast: 0.22, toeLift: 0.020, shoulderRoll: 0.08)

        case "cinestill_800t":
            nr = filmicCurve(r * 0.96, contrast: 0.34, toeLift: 0.022, shoulderRoll: 0.05) + highlightWeight * 0.03
            ng = filmicCurve(g * 1.01, contrast: 0.32, toeLift: 0.028, shoulderRoll: 0.06) + shadowWeight * 0.018
            nb = filmicCurve(b * 1.05, contrast: 0.34, toeLift: 0.038, shoulderRoll: 0.04) + shadowWeight * 0.032

        case "ilford_hp5":
            let silverLuma = 0.28 * r + 0.62 * g + 0.10 * b
            let mono = filmicCurve(silverLuma, contrast: 0.44, toeLift: 0.022, shoulderRoll: 0.06)
            nr = mono; ng = mono; nb = mono

        case "agfa_100":
            nr = filmicCurve(r * 1.06 + g * 0.02, contrast: 0.36, toeLift: 0.020, shoulderRoll: 0.05)
            ng = filmicCurve(g * 1.01, contrast: 0.34, toeLift: 0.018, shoulderRoll: 0.06)
            nb = filmicCurve(b * 0.95, contrast: 0.32, toeLift: 0.015, shoulderRoll: 0.07)

        default:
            break
        }

        return (min(max(nr, 0.0), 1.0), min(max(ng, 0.0), 1.0), min(max(nb, 0.0), 1.0))
    }

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

    private func ensureLandscapeOrientation(_ image: UIImage) -> UIImage {
        let size = image.size
        if size.width >= size.height { return image }
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

    /// 获取看片台轻量级缩略图（带内存缓存，彻底消除双指缩放和滚动卡顿）
    func cachedLightTablePreview(for frame: FilmFrame, stock: FilmStock, loadOriginal: () -> UIImage) -> UIImage {
        let cacheKey = String(
            format: "%@_%@_%d_%.2f_%.2f_%.2f_%.2f",
            frame.id.uuidString,
            stock.id,
            frame.isScanned ? 1 : 0,
            frame.exposureEV,
            frame.warmthWB,
            frame.highlights,
            frame.shadows
        ) as NSString

        if let hit = previewCache.object(forKey: cacheKey) {
            return hit
        }

        let baseKey = frame.id.uuidString as NSString
        let baseThumb: UIImage
        if let cachedThumb = baseThumbnailCache.object(forKey: baseKey) {
            baseThumb = cachedThumb
        } else {
            let fullImg = cropToLandscapeFilmAspectRatio(loadOriginal(), format: frame.format)
            let maxSide: CGFloat = 720
            let ratio = min(1.0, maxSide / max(fullImg.size.width, fullImg.size.height))
            let thumbSize = CGSize(width: fullImg.size.width * ratio, height: fullImg.size.height * ratio)
            let fmt = UIGraphicsImageRendererFormat()
            fmt.scale = 1.0
            baseThumb = UIGraphicsImageRenderer(size: thumbSize, format: fmt).image { _ in
                fullImg.draw(in: CGRect(origin: .zero, size: thumbSize))
            }
            baseThumbnailCache.setObject(baseThumb, forKey: baseKey)
        }

        let rendered = frame.isScanned
            ? renderPositive(for: frame, sourceImage: baseThumb, stock: stock)
            : renderOrangeNegative(from: baseThumb)
        previewCache.setObject(rendered, forKey: cacheKey)
        return rendered
    }

    func renderOrangeNegative(from sourceImage: UIImage) -> UIImage {
        guard let cgImg = sourceImage.cgImage else { return sourceImage }
        let ciInput = CIImage(cgImage: cgImg)

        let invert = CIFilter.colorInvert()
        invert.inputImage = ciInput
        guard let inverted = invert.outputImage else { return sourceImage }

        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = inverted
        matrix.rVector = CIVector(x: 0.92, y: 0.08, z: 0.00, w: 0)
        matrix.gVector = CIVector(x: 0.05, y: 0.60, z: 0.05, w: 0)
        matrix.bVector = CIVector(x: 0.00, y: 0.06, z: 0.36, w: 0)
        matrix.biasVector = CIVector(x: 0.14, y: 0.05, z: 0.01, w: 0)

        guard let output = matrix.outputImage,
              let outCG = context.createCGImage(output, from: ciInput.extent) else {
            return sourceImage
        }
        return UIImage(cgImage: outCG, scale: 1.0, orientation: .up)
    }

    /// 16-Bit 浮点正片渲染：曝光/色温/高光/阴影 + .cube 3D LUT
    func renderPositive(for frame: FilmFrame, sourceImage: UIImage, stock: FilmStock) -> UIImage {
        let croppedUI = cropToLandscapeFilmAspectRatio(sourceImage, format: frame.format)
        guard let cgImg = croppedUI.cgImage else { return sourceImage }
        var workingCI = CIImage(cgImage: cgImg)
        let extent = workingCI.extent

        // 1. 曝光调整 (EV)
        if abs(frame.exposureEV) > 0.005 {
            let expFilter = CIFilter.exposureAdjust()
            expFilter.inputImage = workingCI
            expFilter.ev = Float(frame.exposureEV)
            if let out = expFilter.outputImage { workingCI = out }
        }

        // 2. 色温调整 (WB)
        if abs(frame.warmthWB) > 0.005 {
            let tempFilter = CIFilter.temperatureAndTint()
            tempFilter.inputImage = workingCI
            tempFilter.neutral = CIVector(x: 6500, y: 0)
            tempFilter.targetNeutral = CIVector(x: 6500 - CGFloat(frame.warmthWB * 1800), y: 0)
            if let out = tempFilter.outputImage { workingCI = out }
        }

        // 3. 高光与阴影调整
        if abs(frame.highlights) > 0.005 || abs(frame.shadows) > 0.005 {
            let hsFilter = CIFilter.highlightShadowAdjust()
            hsFilter.inputImage = workingCI
            hsFilter.highlightAmount = Float(min(max(1.0 + frame.highlights * 0.45, 0.25), 1.45))
            hsFilter.shadowAmount = Float(min(max(frame.shadows * 0.75, -0.75), 0.85))
            if let out = hsFilter.outputImage { workingCI = out }
        }

        // 4. 标准 .cube 3D LUT 映射
        if let lut = loadLUTData(for: stock) {
            let cubeFilter = CIFilter.colorCubeWithColorSpace()
            cubeFilter.inputImage = workingCI
            cubeFilter.cubeDimension = Float(lut.dimension)
            cubeFilter.cubeData = lut.data
            cubeFilter.colorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
            if let out = cubeFilter.outputImage {
                workingCI = out
            }
        }

        // 5. Cinestill 800T 柔和映画红晕
        if stock.id == "cinestill_800t" {
            let bloom = CIFilter.bloom()
            bloom.inputImage = workingCI
            bloom.intensity = 0.30
            bloom.radius = Float(min(extent.width, extent.height) * 0.018)
            if let out = bloom.outputImage?.cropped(to: extent) {
                workingCI = out
            }
        }

        guard let outCG = context.createCGImage(workingCI, from: extent) else { return sourceImage }
        return UIImage(cgImage: outCG, scale: 1.0, orientation: .up)
    }

    private func loadLUTData(for stock: FilmStock) -> (dimension: Int, data: Data)? {
        if let cached = lutMemoryCache[stock.cubeFileName] { return cached }
        let binURL = lutDirectoryURL.appendingPathComponent("\(stock.id).lutbin")
        if let data = try? Data(contentsOf: binURL) {
            let floatCount = data.count / MemoryLayout<Float>.size
            let dim = Int(round(pow(Double(floatCount / 4), 1.0 / 3.0)))
            let result = (dimension: dim, data: data)
            lutMemoryCache[stock.cubeFileName] = result
            return result
        }
        let (floatData, _) = synthesize3DLUT(for: stock.id, dimension: 32)
        let result = (dimension: 32, data: floatData)
        lutMemoryCache[stock.cubeFileName] = result
        return result
    }

    func parseAndSaveUserCubeFile(from url: URL, customID: String) throws -> (fileName: String, dimension: Int) {
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
        let cubeFileName = "\(customID).cube"
        let binURL = lutDirectoryURL.appendingPathComponent("\(customID).lutbin")
        try data.write(to: binURL)
        lutMemoryCache[cubeFileName] = (dimension, data)
        return (cubeFileName, dimension)
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
        formatRenderer.preferredRange = .extended
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

// MARK: - 4. ViewModel (修复夜景曝光全黑 Bug + 新增闪光灯控制 + 自动横竖屏适配)
final class FilmCameraViewModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureSessionControlsDelegate {
    @Published var stage: AppStage = .shooting
    @Published var allStocks: [FilmStock] = FilmStock.builtInStocks
    @Published var currentStock: FilmStock = FilmStock.builtInStocks[0]
    @Published var currentFormat: FilmFormat = .mm135
    @Published var maxFramesPerRoll: Int = 12

    // 闪光灯模式与焦段
    @Published var flashOption: CameraFlashOption = .auto
    @Published var selectedLens: FocalLensOption = FocalLensOption.iPhone16ProLenses[1]
    private var isUsingTripleCamera: Bool = false

    @Published var savedRolls: [FilmRollData] = []
    @Published var viewingRollID: UUID?

    @Published var activeRollID: UUID = UUID()
    @Published var frames: [FilmFrame] = []
    @Published var isShutterLocked: Bool = false
    @Published var advanceProgress: Double = 0.0
    @Published var isHardwareControlActive: Bool = false
    private var isAdvancingLock: Bool = false

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
        _ = FilmColorEngine.shared
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

                // 关键修复：开启连续自动测光、弱光自动提亮与连续对焦，彻底解决晚上拍出来全黑的问题！
                do {
                    try camDevice.lockForConfiguration()
                    if camDevice.isExposureModeSupported(.continuousAutoExposure) {
                        camDevice.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                        camDevice.exposureMode = .continuousAutoExposure
                    }
                    if camDevice.isFocusModeSupported(.continuousAutoFocus) {
                        camDevice.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                        camDevice.focusMode = .continuousAutoFocus
                    }
                    if camDevice.isLowLightBoostSupported {
                        camDevice.automaticallyEnablesLowLightBoostWhenAvailable = true
                    }
                    camDevice.unlockForConfiguration()
                } catch {}
            }

            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
                self.photoOutput.isHighResolutionCaptureEnabled = true
                // 开启最高画质优先级 (.quality)，激活 iPhone 16 Pro 的 Deep Fusion 与夜景多帧合成
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
            self.applyZoomFactor(for: self.selectedLens, animated: false)
        }
    }

    /// 切换闪光灯状态 (OFF -> AUTO -> ON)
    func toggleFlash() {
        flashOption = flashOption.next()
        HapticManager.shared.playRatchetTick()
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
            // 变焦后重新触发中心自动测光与对焦
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {}
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

    /// 拍摄：使用 Apple 多帧融合最高画质管线 + 闪光灯控制，彻底告别夜景全黑
    func capturePhoto() {
        guard !isShutterLocked, frames.count < maxFramesPerRoll else { return }
        HapticManager.shared.playShutterClick()
        isShutterLocked = true
        isAdvancingLock = false
        advanceProgress = 0.0
        lastHapticStep = 0
        hardwareAdvanceSlider?.value = 0.0

        if session.isRunning {
            let settings: AVCapturePhotoSettings
            if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            } else {
                settings = AVCapturePhotoSettings()
            }
            settings.isHighResolutionPhotoEnabled = true
            // 关键：启用 .quality，触发苹果 Smart HDR 与夜景多帧提亮合成
            settings.photoQualityPrioritization = self.photoOutput.maxPhotoQualityPrioritization
            if let maxDim = self.videoDevice?.activeFormat.supportedMaxPhotoDimensions.last {
                settings.maxPhotoDimensions = maxDim
            }

            // 应用闪光灯开关设置
            if let device = self.videoDevice, device.hasFlash,
               self.photoOutput.supportedFlashModes.contains(self.flashOption.avFlashMode) {
                settings.flashMode = self.flashOption.avFlashMode
            }

            // 根据当前设备握持方向自动设定正确角度
            let rotAngle = currentVideoRotationAngle()
            if let conn = self.photoOutput.connection(with: .video), conn.isVideoRotationAngleSupported(rotAngle) {
                conn.videoRotationAngle = rotAngle
            }
            photoOutput.capturePhoto(with: settings, delegate: self)
        } else {
            saveSimulatedLatentFrame()
        }
    }

    private func currentVideoRotationAngle() -> CGFloat {
        switch UIDevice.current.orientation {
        case .landscapeLeft:
            return 0   // 灵动岛在左，快门在右
        case .landscapeRight:
            return 180 // 灵动岛在右，快门在左
        case .portraitUpsideDown:
            return 270
        default:
            return 90  // 竖屏握持
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let img = UIImage(data: data) else {
            saveSimulatedLatentFrame()
            return
        }
        let normalized = normalizeOrientation(img)
        let cropped = FilmColorEngine.shared.cropToLandscapeFilmAspectRatio(normalized, format: currentFormat)
        saveLatentFrameToDisk(previewImage: cropped)
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
        saveLatentFrameToDisk(previewImage: img)
    }

    private func saveLatentFrameToDisk(previewImage: UIImage) {
        let uuidStr = UUID().uuidString
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let jpgName = "latent_\(uuidStr).jpg"
        let jpgURL = docsDir.appendingPathComponent(jpgName)
        try? previewImage.jpegData(compressionQuality: 1.0)?.write(to: jpgURL)

        DispatchQueue.main.async {
            let newFrame = FilmFrame(
                frameNumber: self.frames.count + 1,
                fallbackJPGName: jpgName,
                captureDate: Date(),
                focalMM: self.selectedLens.mmLabel,
                format: self.currentFormat
            )
            self.frames.append(newFrame)
            self.upsertActiveRollInWarehouse(isDeveloped: false)
        }
    }

    private func upsertActiveRollInWarehouse(isDeveloped: Bool) {
        if let existingIdx = savedRolls.firstIndex(where: { $0.id == activeRollID }) {
            savedRolls[existingIdx].frames = frames
            savedRolls[existingIdx].stockID = currentStock.id
            savedRolls[existingIdx].format = currentFormat
            savedRolls[existingIdx].capacity = maxFramesPerRoll
            if isDeveloped { savedRolls[existingIdx].isDeveloped = true }
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

    func openRollFromWarehouse(_ roll: FilmRollData) {
        viewingRollID = roll.id
        frames = roll.frames
        if let stock = allStocks.first(where: { $0.id == roll.stockID }) {
            currentStock = stock
        }
        currentFormat = roll.format
        stage = .lightTableScanner
    }

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

    func clearAllWarehouseRolls() {
        savedRolls.removeAll()
        saveSavedRolls()
        loadNewRoll(stock: currentStock, format: currentFormat, capacity: maxFramesPerRoll)
    }

    func loadFallbackImage(for frame: FilmFrame) -> UIImage {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(frame.fallbackJPGName)
        return (try? Data(contentsOf: url)).flatMap { UIImage(data: $0) } ?? UIImage()
    }

    func importCubeLUT(from url: URL) throws {
        let customID = "custom_\(UUID().uuidString.prefix(6))"
        let parsed = try FilmColorEngine.shared.parseAndSaveUserCubeFile(from: url, customID: customID)
        let cleanTitle = url.deletingPathExtension().lastPathComponent.uppercased()
        let customStock = FilmStock(
            id: customID,
            name: cleanTitle,
            subtitle: "自定义 3D .cube 胶卷",
            edgeCode: "\(cleanTitle) LUT",
            iso: 400,
            themeColorHex: "#8E44AD",
            cubeFileName: parsed.fileName,
            cubeDimension: parsed.dimension
        )
        allStocks.append(customStock)
        currentStock = customStock
        saveCustomStocks()
    }

    private func saveCustomStocks() {
        let customs = allStocks.filter { $0.id.hasPrefix("custom_") }
        if let data = try? JSONEncoder().encode(customs) { UserDefaults.standard.set(data, forKey: "SavedCustomFilmStocks_v3") }
    }

    private func loadCustomStocks() {
        if let data = UserDefaults.standard.data(forKey: "SavedCustomFilmStocks_v3"),
           let customs = try? JSONDecoder().decode([FilmStock].self, from: data) {
            allStocks = FilmStock.builtInStocks + customs
        }
    }

    private func saveSavedRolls() {
        if let data = try? JSONEncoder().encode(savedRolls) { UserDefaults.standard.set(data, forKey: "SavedFilmRollsWarehouse_v3") }
    }

    private func loadSavedRolls() {
        if let data = UserDefaults.standard.data(forKey: "SavedFilmRollsWarehouse_v3"),
           let rolls = try? JSONDecoder().decode([FilmRollData].self, from: data) {
            savedRolls = rolls
        }
    }

    private func normalizeOrientation(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.preferredRange = .extended
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}

// MARK: - 5. 自适应横竖屏实时取景器 (自动跟随横竖屏旋转保持画面正立，取景框尺寸与比例永远固定不变)
struct AdaptiveCameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var onPhysicalPress: () -> Void

    class VideoPreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var pressHandler: (() -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(updatePreviewRotation),
                name: UIDevice.orientationDidChangeNotification,
                object: nil
            )
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            updatePreviewRotation()
        }

        @objc func updatePreviewRotation() {
            guard let connection = videoPreviewLayer.connection else { return }
            let windowScene = self.window?.windowScene
            let interfaceOrientation = windowScene?.interfaceOrientation ?? .landscapeRight

            // 预览框本身是固定在横向相机布局里的：当系统界面处于竖屏时，外层视图被顺时针旋转了 90 度，所以内部预览层设为 0 度即可在横握时正立；当系统自动切换到横屏时，同步对应角度
            let targetAngle: CGFloat
            switch interfaceOrientation {
            case .landscapeRight:
                targetAngle = 0
            case .landscapeLeft:
                targetAngle = 180
            case .portraitUpsideDown:
                targetAngle = 180
            default:
                // 竖屏模式下，因为外层相机 UI 固定保持横置 (.rotationEffect(90))，设为 0 度保证取景框画面永远横向正立不变
                targetAngle = 0
            }

            if connection.isVideoRotationAngleSupported(targetAngle) {
                connection.videoRotationAngle = targetAngle
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
        uiView.updatePreviewRotation()
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

// MARK: - 舞台一：拍摄界面（无论系统自动切换横屏还是竖屏，相机布局与取景框比例 100% 保持不变 + 新增闪光灯按钮）
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

                HStack(spacing: 12) {
                    // 【左一栏】：竖向钛金属相机顶盖
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
                            VStack {
                                CameraScrewIcon()
                                RoundedRectangle(cornerRadius: 2.5)
                                    .fill(LinearGradient(colors: [.white.opacity(0.8), .gray.opacity(0.35), .white.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                                    .frame(width: 10, height: 26)
                                    .overlay(RoundedRectangle(cornerRadius: 2.5).stroke(Color.black, lineWidth: 1))
                                    .padding(.top, 4)

                                Spacer()

                                Text("HONGSHUXIA · 3D LUT")
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

                            VStack(spacing: 12) {
                                VerticalMechanicalLever(
                                    isLocked: vm.isShutterLocked,
                                    progress: vm.advanceProgress
                                ) { newProgress in
                                    vm.updateFilmAdvance(progress: newProgress)
                                }

                                Spacer()

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

                    // 【中间核心栏】：荔枝纹蒙皮机身 + 顶部红标/闪光灯开关/胶卷仓库 + 固定横向取景框 + 底部焦段按钮排
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
                            HStack {
                                HStack(spacing: 10) {
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

                                    // 新增：机械闪光灯开关 (OFF / AUTO / ON)
                                    Button {
                                        vm.toggleFlash()
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: vm.flashOption.iconName)
                                                .font(.system(size: 11, weight: .bold))
                                            Text("FLASH \(vm.flashOption.rawValue)")
                                                .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                                        }
                                        .foregroundColor(vm.flashOption == .off ? .gray : .yellow)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.black.opacity(0.8))
                                        .cornerRadius(12)
                                        .overlay(
                                            Capsule().stroke(vm.flashOption == .off ? Color.white.opacity(0.15) : Color.yellow.opacity(0.6), lineWidth: 1)
                                        )
                                    }
                                }

                                Spacer()

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

                            // 取景框尺寸与比例永远固定不变
                            let vfHeight: CGFloat = min(landH - 122, 224)
                            let vfWidth: CGFloat = (vm.currentFormat == .medium120) ? vfHeight : (vfHeight * 1.5)

                            ZStack {
                                AdaptiveCameraPreviewView(session: vm.session) {
                                    vm.handlePhysicalCameraButtonPress()
                                }
                                .frame(width: vfWidth, height: vfHeight)
                                .clipShape(RoundedRectangle(cornerRadius: 10))

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
                                            Text("\(vm.selectedLens.mmLabel) · \(vm.currentStock.cubeFileName)")
                                                .font(.system(size: 9, weight: .bold, design: .monospaced))
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

                    // 【右二栏】：竖向过片滑轨条
                    VerticalSlideAdvanceBar(
                        isLocked: vm.isShutterLocked,
                        progress: vm.advanceProgress
                    ) { newProgress in
                        vm.updateFilmAdvance(progress: newProgress)
                    }
                    .frame(width: 52, height: landH - 24)

                    // 【最右侧栏】：三联操控转盘
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
                                title: "导入.cube",
                                accentColor: Color(red: 0.85, green: 0.82, blue: 0.75)
                            )
                        }
                    }
                    .frame(width: 84, height: landH - 24)
                }
                .padding(.horizontal, 14)
                .frame(width: landW, height: landH)
                // 无论系统处于竖屏还是横屏，相机界面布局与取景框永远固定一致
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
                    importAlertMessage = "成功导入 \(first.lastPathComponent) 3D LUT 胶卷！"
                } catch {
                    importAlertMessage = "导入失败：\(error.localizedDescription)"
                }
            }
        }
        .alert("LUT 工坊提示", isPresented: Binding(get: { importAlertMessage != nil }, set: { if !$0 { importAlertMessage = nil } })) {
            Button("确定", role: .cancel) {}
        } message: { Text(importAlertMessage ?? "") }
    }
}

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

                VStack(spacing: 8) {
                    ForEach(0..<18, id: \.self) { idx in
                        Rectangle()
                            .fill(idx % 4 == 0 ? Color.orange.opacity(0.75) : Color.white.opacity(0.2))
                            .frame(width: idx % 4 == 0 ? 14 : 7, height: 1.5)
                    }
                }

                VStack {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundColor(.orange)
                        .padding(.top, 10)
                    Spacer()
                }

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

// MARK: - 拟物化“胶卷仓库”界面
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
                            Text("一卷一盒 · 点击任意金属暗盒进入看片台")
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
                                Text("胶卷仓库暂无存档\n每拍一卷胶卷，会在这里生成一个金属暗盒")
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
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(Color(white: 0.28))
                                                    .frame(width: 34, height: 92)
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

// MARK: - 胶卷与 135/120 画幅装填仓
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

                    Text("3. 点击下方任意胶卷装填（每款胶卷均由专属 32³ .cube 3D LUT 驱动）").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.gray).padding(.horizontal, 16)

                    ForEach(vm.allStocks) { stock in
                        Button {
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
                                    Text("3D LUT：\(stock.cubeFileName) (\(stock.cubeDimension)³)").font(.system(size: 9.5, weight: .bold, design: .monospaced)).foregroundColor(Color(red: 0.88, green: 0.64, blue: 0.22))
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
                Text("当前卷：\(vm.currentStock.name) · \(vm.currentStock.cubeFileName)（共 \(vm.frames.count) 张潜影）").font(.system(size: 12)).foregroundColor(.red.opacity(0.85))

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

// MARK: - 阶段三：全屏发光看片台（3张一排矩阵 + 初始隐藏全部控件 + 右下角四分之一圆滑动调色盘 + GPU 丝滑缩放）
struct LightTableScannerView: View {
    @ObservedObject var vm: FilmCameraViewModel
    @State private var selectedIndex: Int? = nil

    // 控件显隐状态：刚打开看片台时默认全部隐藏，点击或滑动屏幕才浮现
    @State private var showControlsHUD: Bool = false
    @State private var activeDialGroup: DialGroup? = nil
    @State private var activeDialParam: DialParam = .exposure

    // GPU 加速丝滑缩放状态
    @State private var steadyZoom: CGFloat = 1.0
    @GestureState private var pinchMultiplier: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero

    @State private var borderStyle: ExportBorderStyle = .sprocket35mm
    @State private var includeDateStamp: Bool = true
    @State private var saveToastMessage: String?

    // 固定 3 张一列/一排的矩阵组合布局
    private let threeColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        GeometryReader { geo in
            let currentScale = min(max(steadyZoom * pinchMultiplier, 0.8), 3.0)
            let baseCellWidth = max(95, (geo.size.width - 68) / 3.0)

            ZStack {
                // 1. 全屏 5500K 发光看片台底板（点击空白处切换隐藏/显示角落按钮）
                Color(red: 0.95, green: 0.95, blue: 0.93)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            showControlsHUD.toggle()
                            if !showControlsHUD { activeDialGroup = nil }
                        }
                    }

                // 2. 固定 3 列排布的胶卷底片阵列（GPU 级 scaleEffect，双指捏合 120Hz 零卡顿）
                ScrollViewReader { proxy in
                    ScrollView([.vertical, .horizontal], showsIndicators: false) {
                        LazyVGrid(columns: threeColumns, spacing: 16) {
                            ForEach(Array(vm.frames.enumerated()), id: \.element.id) { idx, frame in
                                let displayImg = FilmColorEngine.shared.cachedLightTablePreview(
                                    for: frame,
                                    stock: vm.currentStock,
                                    loadOriginal: { vm.loadFallbackImage(for: frame) }
                                )

                                LightTableContactCell(
                                    image: displayImg,
                                    stock: vm.currentStock,
                                    frame: frame,
                                    cellWidth: baseCellWidth,
                                    isSelected: selectedIndex == idx
                                )
                                .id(frame.id)
                                .onTapGesture {
                                    HapticManager.shared.playRatchetTick()
                                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                                        showControlsHUD = true
                                        if selectedIndex == idx && steadyZoom > 1.35 {
                                            steadyZoom = 1.0
                                            panOffset = .zero
                                            lastPanOffset = .zero
                                        } else {
                                            selectedIndex = idx
                                            steadyZoom = 1.75
                                        }
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            proxy.scrollTo(frame.id, anchor: .center)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(20)
                        .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                        .scaleEffect(currentScale, anchor: .center)
                        .offset(panOffset)
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { val in
                                if !showControlsHUD {
                                    withAnimation(.easeInOut(duration: 0.2)) { showControlsHUD = true }
                                }
                                if steadyZoom > 1.05 {
                                    panOffset = CGSize(
                                        width: lastPanOffset.width + val.translation.width,
                                        height: lastPanOffset.height + val.translation.height
                                    )
                                }
                            }
                            .onEnded { _ in
                                lastPanOffset = panOffset
                            }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .updating($pinchMultiplier) { value, state, _ in
                                state = value
                            }
                            .onEnded { value in
                                steadyZoom = min(max(steadyZoom * value, 0.85), 2.8)
                                if steadyZoom <= 1.05 {
                                    withAnimation(.spring()) {
                                        panOffset = .zero
                                        lastPanOffset = .zero
                                    }
                                }
                                withAnimation(.easeInOut(duration: 0.2)) { showControlsHUD = true }
                            }
                    )
                }

                // 3. 角落悬浮微控 HUD（打开时默认隐藏，滑动或点击屏幕才在四角优雅浮现）
                if showControlsHUD {
                    ZStack {
                        // 【左上角】：极简返回相机与缩放复位小胶囊
                        VStack {
                            HStack(spacing: 8) {
                                Button {
                                    vm.returnToCameraFromScanner()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "chevron.left")
                                        Text("相机")
                                    }
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 7)
                                    .background(Color.black.opacity(0.82))
                                    .clipShape(Capsule())
                                }

                                if steadyZoom != 1.0 {
                                    Button {
                                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                                            steadyZoom = 1.0
                                            panOffset = .zero
                                            lastPanOffset = .zero
                                        }
                                    } label: {
                                        Text(String(format: "%.1fx 复位", steadyZoom))
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundColor(.yellow)
                                            .padding(.horizontal, 9)
                                            .padding(.vertical, 7)
                                            .background(Color.black.opacity(0.82))
                                            .clipShape(Capsule())
                                    }
                                }

                                Spacer()

                                // 【右上角】：小巧的扫描、边框、单张导出与整卷导出按钮组
                                HStack(spacing: 6) {
                                    Button {
                                        borderStyle = (borderStyle == .sprocket35mm) ? .clean : .sprocket35mm
                                        HapticManager.shared.playRatchetTick()
                                    } label: {
                                        Text(borderStyle.rawValue)
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 9)
                                            .padding(.vertical, 7)
                                            .background(Color.black.opacity(0.78))
                                            .clipShape(Capsule())
                                    }

                                    Button {
                                        includeDateStamp.toggle()
                                        HapticManager.shared.playRatchetTick()
                                    } label: {
                                        Text(includeDateStamp ? "日期 ON" : "日期 OFF")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(includeDateStamp ? .orange : .gray)
                                            .padding(.horizontal, 9)
                                            .padding(.vertical, 7)
                                            .background(Color.black.opacity(0.78))
                                            .clipShape(Capsule())
                                    }

                                    Button {
                                        for i in 0..<vm.frames.count { vm.frames[i].isScanned = true }
                                        vm.syncCurrentFramesToWarehouse()
                                        HapticManager.shared.playFilmWoundLock()
                                        showToast("已一键扫描全卷！")
                                    } label: {
                                        HStack(spacing: 3) {
                                            Image(systemName: "wand.and.stars")
                                            Text("全扫")
                                        }
                                        .font(.system(size: 10.5, weight: .bold))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(Color.cyan)
                                        .clipShape(Capsule())
                                    }

                                    if let sel = selectedIndex, vm.frames.indices.contains(sel) {
                                        Button {
                                            exportSinglePhoto(at: sel)
                                        } label: {
                                            Text("存本张")
                                                .font(.system(size: 10.5, weight: .bold))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 7)
                                                .background(Color.orange)
                                                .clipShape(Capsule())
                                        }
                                    }

                                    Button {
                                        batchExportAllPhotos()
                                    } label: {
                                        HStack(spacing: 3) {
                                            Image(systemName: "arrow.down.to.line")
                                            Text("导整卷")
                                        }
                                        .font(.system(size: 10.5, weight: .bold))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(Color.yellow)
                                        .clipShape(Capsule())
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 14)

                            Spacer()

                            // 【左下角】：两个参数选择按钮（按钮1：曝光/色温，按钮2：高光/阴影）
                            HStack(alignment: .bottom) {
                                HStack(spacing: 10) {
                                    // 按钮 1：打开【曝光 / 色温】四分之一圆转盘
                                    Button {
                                        if selectedIndex == nil && !vm.frames.isEmpty { selectedIndex = 0 }
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            if activeDialGroup == .exposureAndTemp {
                                                activeDialParam = (activeDialParam == .exposure) ? .warmth : .exposure
                                            } else {
                                                activeDialGroup = .exposureAndTemp
                                                activeDialParam = .exposure
                                            }
                                        }
                                        HapticManager.shared.playRatchetTick()
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: "sun.max.fill")
                                            Text("曝光 · 色温")
                                        }
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(activeDialGroup == .exposureAndTemp ? .black : .white)
                                        .padding(.horizontal, 13)
                                        .padding(.vertical, 9)
                                        .background(activeDialGroup == .exposureAndTemp ? Color.yellow : Color.black.opacity(0.84))
                                        .clipShape(Capsule())
                                        .shadow(color: .black.opacity(0.25), radius: 5, x: 0, y: 2)
                                    }

                                    // 按钮 2：打开【高光 / 阴影】四分之一圆转盘
                                    Button {
                                        if selectedIndex == nil && !vm.frames.isEmpty { selectedIndex = 0 }
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            if activeDialGroup == .toneRecovery {
                                                activeDialParam = (activeDialParam == .highlights) ? .shadows : .highlights
                                            } else {
                                                activeDialGroup = .toneRecovery
                                                activeDialParam = .highlights
                                            }
                                        }
                                        HapticManager.shared.playRatchetTick()
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: "circle.lefthalf.filled")
                                            Text("高光 · 阴影")
                                        }
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(activeDialGroup == .toneRecovery ? .black : .white)
                                        .padding(.horizontal, 13)
                                        .padding(.vertical, 9)
                                        .background(activeDialGroup == .toneRecovery ? Color.cyan : Color.black.opacity(0.84))
                                        .clipShape(Capsule())
                                        .shadow(color: .black.opacity(0.25), radius: 5, x: 0, y: 2)
                                    }
                                }
                                .padding(.leading, 16)
                                .padding(.bottom, 16)

                                Spacer()
                            }
                        }
                        .transition(.opacity)

                        // 【右下角】：四分之一圆弧滑动调色转盘 (参考图三，贴合右下角，手指沿弧线滑动调节)
                        if let group = activeDialGroup,
                           let sel = selectedIndex ?? (vm.frames.isEmpty ? nil : 0),
                           vm.frames.indices.contains(sel) {
                            QuarterCircleAdjustmentDial(
                                group: group,
                                activeParam: $activeDialParam,
                                value: bindingForParam(activeDialParam, at: sel),
                                range: activeDialParam == .exposure ? (-1.5...1.5) : (-1.0...1.0),
                                frameNumber: vm.frames[sel].frameNumber,
                                onClose: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        activeDialGroup = nil
                                    }
                                }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            if let msg = saveToastMessage {
                Text(msg)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.green)
                    .cornerRadius(16)
                    .padding(.top, 52)
            }
        }
    }

    private func bindingForParam(_ param: DialParam, at index: Int) -> Binding<Double> {
        Binding(
            get: {
                guard vm.frames.indices.contains(index) else { return 0.0 }
                switch param {
                case .exposure: return vm.frames[index].exposureEV
                case .warmth: return vm.frames[index].warmthWB
                case .highlights: return vm.frames[index].highlights
                case .shadows: return vm.frames[index].shadows
                }
            },
            set: { newVal in
                guard vm.frames.indices.contains(index) else { return }
                vm.frames[index].isScanned = true
                switch param {
                case .exposure: vm.frames[index].exposureEV = newVal
                case .warmth: vm.frames[index].warmthWB = newVal
                case .highlights: vm.frames[index].highlights = newVal
                case .shadows: vm.frames[index].shadows = newVal
                }
                vm.syncCurrentFramesToWarehouse()
            }
        )
    }

    private func exportSinglePhoto(at index: Int) {
        vm.frames[index].isScanned = true
        let frame = vm.frames[index]
        let fallbackImg = vm.loadFallbackImage(for: frame)
        let posImg = FilmColorEngine.shared.renderPositive(for: frame, sourceImage: fallbackImg, stock: vm.currentStock)
        let finalImg = FilmColorEngine.shared.composeFinalExportImage(
            positiveImage: posImg,
            stock: vm.currentStock,
            frame: frame,
            borderStyle: borderStyle,
            includeDateStamp: includeDateStamp
        )
        UIImageWriteToSavedPhotosAlbum(finalImg, nil, nil, nil)
        vm.syncCurrentFramesToWarehouse()
        HapticManager.shared.playFilmWoundLock()
        showToast("已导出第 \(frame.frameNumber) 张高清胶片至相册！")
    }

    private func batchExportAllPhotos() {
        for i in 0..<vm.frames.count {
            vm.frames[i].isScanned = true
            let frame = vm.frames[i]
            let fallbackImg = vm.loadFallbackImage(for: frame)
            let posImg = FilmColorEngine.shared.renderPositive(for: frame, sourceImage: fallbackImg, stock: vm.currentStock)
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
        showToast("已将整卷 \(vm.frames.count) 张高清胶片全部导出至相册！")
    }

    private func showToast(_ text: String) {
        withAnimation { saveToastMessage = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation { saveToastMessage = nil }
        }
    }
}

// MARK: - 右下角「四分之一圆」滑动调色转盘组件（100% 复刻参考图三右下角白色半透明圆弧刻度盘）
struct QuarterCircleAdjustmentDial: View {
    let group: DialGroup
    @Binding var activeParam: DialParam
    @Binding var value: Double
    let range: ClosedRange<Double>
    let frameNumber: Int
    let onClose: () -> Void

    @State private var lastTickStep: Int = 0
    private let dialRadius: CGFloat = 215

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // 四分之一圆毛玻璃刻度盘主体（圆心位于右下角顶点）
            Canvas { context, size in
                let center = CGPoint(x: size.width, y: size.height)

                // 扇形半透明白底
                var sector = Path()
                sector.move(to: center)
                sector.addArc(center: center, radius: dialRadius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
                sector.closeSubpath()
                context.fill(sector, with: .color(Color.white.opacity(0.92)))
                context.stroke(sector, with: .color(Color.black.opacity(0.15)), lineWidth: 1.5)

                // 绘制圆弧精密刻度线 (从 190° 到 260°)
                let tickRadiusOuter = dialRadius - 14
                let totalTicks = 28
                for i in 0...totalTicks {
                    let frac = Double(i) / Double(totalTicks)
                    let deg = 190.0 + frac * 70.0
                    let rad = deg * .pi / 180.0
                    let isMajor = (i % 7 == 0)
                    let len: CGFloat = isMajor ? 14 : 7

                    let p1 = CGPoint(
                        x: center.x + CGFloat(cos(rad)) * tickRadiusOuter,
                        y: center.y + CGFloat(sin(rad)) * tickRadiusOuter
                    )
                    let p2 = CGPoint(
                        x: center.x + CGFloat(cos(rad)) * (tickRadiusOuter - len),
                        y: center.y + CGFloat(sin(rad)) * (tickRadiusOuter - len)
                    )
                    var tickPath = Path()
                    tickPath.move(to: p1)
                    tickPath.addLine(to: p2)
                    context.stroke(
                        tickPath,
                        with: .color(isMajor ? Color.black.opacity(0.75) : Color.black.opacity(0.3)),
                        lineWidth: isMajor ? 2.0 : 1.0
                    )
                }

                // 绘制当前数值对应的橙色游标指示针
                let normalized = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
                let clampedNorm = min(max(normalized, 0.0), 1.0)
                let activeDeg = 190.0 + clampedNorm * 70.0
                let activeRad = activeDeg * .pi / 180.0

                let pointerOuter = CGPoint(
                    x: center.x + CGFloat(cos(activeRad)) * (dialRadius - 6),
                    y: center.y + CGFloat(sin(activeRad)) * (dialRadius - 6)
                )
                let pointerInner = CGPoint(
                    x: center.x + CGFloat(cos(activeRad)) * (dialRadius - 36),
                    y: center.y + CGFloat(sin(activeRad)) * (dialRadius - 36)
                )
                var pointerPath = Path()
                pointerPath.move(to: pointerInner)
                pointerPath.addLine(to: pointerOuter)
                context.stroke(pointerPath, with: .color(Color.orange), lineWidth: 3.5)
            }
            .frame(width: dialRadius, height: dialRadius)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        // 根据手指相对于右下角圆心的极坐标角度 (190° ~ 260°) 实时计算参数值
                        let dx = gesture.location.x - dialRadius
                        let dy = gesture.location.y - dialRadius
                        var deg = atan2(dy, dx) * 180.0 / .pi
                        if deg < 0 { deg += 360.0 }

                        let clampedDeg = min(max(deg, 190.0), 260.0)
                        let ratio = (clampedDeg - 190.0) / 70.0
                        let rawVal = range.lowerBound + ratio * (range.upperBound - range.lowerBound)
                        let steppedVal = (rawVal * 20.0).rounded() / 20.0
                        value = min(max(steppedVal, range.lowerBound), range.upperBound)

                        let tick = Int(ratio * 24)
                        if tick != lastTickStep {
                            lastTickStep = tick
                            HapticManager.shared.playScannerStepperPulse()
                        }
                    }
            )

            // 扇形内部的参数读数与子项切换钮
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 6) {
                    Text(String(format: "#%02dA", frameNumber))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.black.opacity(0.5))
                    Button {
                        value = 0.0
                        HapticManager.shared.playRatchetTick()
                    } label: {
                        Text("归零")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.08))
                            .cornerRadius(4)
                    }
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundColor(.black.opacity(0.45))
                    }
                }

                // 当前参数大号读数（复刻图三 +0.42 EV 样式）
                Text(String(format: "%@ %+.2f", activeParam.rawValue, value))
                    .font(.system(size: 16, weight: .heavy, design: .monospaced))
                    .foregroundColor(.black)

                // 组内两个子参数快速切换胶囊
                HStack(spacing: 6) {
                    let options: [DialParam] = (group == .exposureAndTemp) ? [.exposure, .warmth] : [.highlights, .shadows]
                    ForEach(options, id: \.self) { opt in
                        Button {
                            activeParam = opt
                            HapticManager.shared.playRatchetTick()
                        } label: {
                            Text(opt.rawValue)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(activeParam == opt ? .black : .black.opacity(0.55))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(activeParam == opt ? Color.orange.opacity(0.85) : Color.black.opacity(0.08))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(.trailing, 14)
            .padding(.bottom, 14)
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

        VStack(spacing: 3) {
            HStack {
                Text(stock.edgeCode)
                    .font(.system(size: max(5.5, cellWidth * 0.042), weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.90, green: 0.66, blue: 0.20))
                    .lineLimit(1)
                Spacer()
                Text(String(format: "%02d", frame.frameNumber))
                    .font(.system(size: max(6.5, cellWidth * 0.048), weight: .heavy, design: .monospaced))
                    .foregroundColor(Color(red: 0.90, green: 0.66, blue: 0.20))
            }
            .padding(.horizontal, 4)

            if frame.format == .mm135 {
                HStack(spacing: cellWidth * 0.042) {
                    ForEach(0..<8, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1.2)
                            .fill(Color(red: 0.95, green: 0.95, blue: 0.93))
                            .frame(width: cellWidth * 0.062, height: cellWidth * 0.042)
                    }
                }
            }

            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: cellWidth, height: photoHeight)
                .clipped()

            if frame.format == .mm135 {
                HStack(spacing: cellWidth * 0.042) {
                    ForEach(0..<8, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1.2)
                            .fill(Color(red: 0.95, green: 0.95, blue: 0.93))
                            .frame(width: cellWidth * 0.062, height: cellWidth * 0.042)
                    }
                }
            }

            HStack {
                Text(frame.focalMM)
                    .font(.system(size: max(5.5, cellWidth * 0.04), weight: .semibold, design: .monospaced))
                    .foregroundColor(.gray)
                Spacer()
                Text(String(format: "▶ %02dA", frame.frameNumber))
                    .font(.system(size: max(6, cellWidth * 0.045), weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.90, green: 0.66, blue: 0.20))
            }
            .padding(.horizontal, 4)
        }
        .padding(5)
        .background(Color(red: 0.06, green: 0.06, blue: 0.06))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.orange : Color.black, lineWidth: isSelected ? 2.5 : 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 2)
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