import SwiftUI
import AVFoundation
import AVKit
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreHaptics
import Photos
import UniformTypeIdentifiers
import AudioToolbox

// MARK: - 1. 胶卷型号与自定义 LUT 数据模型
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
        FilmStock(id: "fuji_c200", name: "富士 C200", subtitle: "日系青绿 · 街拍绿植", edgeCode: "HONGSHUXIA C200", iso: 200, themeColorHex: "#1E7A4C"),
        FilmStock(id: "kodak_portra400", name: "柯达 Portra 400", subtitle: "暖调人像 · 柔和肤色", edgeCode: "HONGSHUXIA PORTRA", iso: 400, themeColorHex: "#E09F3E"),
        FilmStock(id: "cinestill_800t", name: "Cinestill 800T", subtitle: "电影夜景 · 高光红晕", edgeCode: "HONGSHUXIA 800T", iso: 800, themeColorHex: "#C1292E"),
        FilmStock(id: "ilford_hp5", name: "伊尔福 HP5", subtitle: "高反差黑白 · 粗颗粒", edgeCode: "HONGSHUXIA HP5", iso: 400, themeColorHex: "#6C757D"),
        FilmStock(id: "agfa_100", name: "爱克发 Vista 100", subtitle: "德味浓郁 · 高饱和复古", edgeCode: "HONGSHUXIA AGFA", iso: 100, themeColorHex: "#D9381E")
    ]
}

struct FilmFrame: Identifiable, Codable {
    var id: UUID = UUID()
    var frameNumber: Int
    var rawFileName: String
    var captureDate: Date
    var isScanned: Bool = false
    var scanProgress: Double = 0.0
    var exposureEV: Double = 0.0
    var warmthWB: Double = 0.0
}

enum ExportBorderStyle: String, CaseIterable, Identifiable {
    case sprocket35mm = "35mm 齿孔黑边"
    case clean = "无边框纯享版"
    var id: String { rawValue }
}

enum AppStage: String, Codable {
    case shooting
    case darkroom
    case lightTableScanner
}

// MARK: - 2. 触觉与音效引擎
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

// MARK: - 3. CoreImage 胶卷色彩管线
final class FilmColorEngine {
    static let shared = FilmColorEngine()
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private var lutCache: [String: (dimension: Int, data: Data)] = [:]

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
        return UIImage(cgImage: outCG, scale: sourceImage.scale, orientation: sourceImage.imageOrientation)
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

        current = applyFilmGrainAndVignette(to: current, extent: extent, grainAmount: stock.id == "ilford_hp5" ? 0.14 : 0.06)

        guard let outCG = context.createCGImage(current, from: extent) else { return sourceImage }
        return UIImage(cgImage: outCG, scale: sourceImage.scale, orientation: sourceImage.imageOrientation)
    }

    private func applyBuiltInStockProfile(to image: CIImage, stockID: String) -> CIImage {
        var img = image
        switch stockID {
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
        vignette.intensity = 0.65
        vignette.radius = 1.6
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

    func composeFinalExportImage(positiveImage: UIImage, stock: FilmStock, frameNumber: Int, captureDate: Date, borderStyle: ExportBorderStyle, includeDateStamp: Bool) -> UIImage {
        let baseSize = positiveImage.size
        let hasSprocket = (borderStyle == .sprocket35mm)
        let topBottomBarHeight = hasSprocket ? baseSize.height * 0.16 : 0
        let sideMargin = hasSprocket ? baseSize.width * 0.04 : 0
        let canvasSize = CGSize(width: baseSize.width + sideMargin * 2, height: baseSize.height + topBottomBarHeight * 2)

        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { ctx in
            let cgCtx = ctx.cgContext
            if hasSprocket {
                UIColor(red: 0.06, green: 0.06, blue: 0.06, alpha: 1.0).setFill()
                cgCtx.fill(CGRect(origin: .zero, size: canvasSize))

                let holeCount = 8
                let holeWidth = canvasSize.width * 0.065
                let holeHeight = topBottomBarHeight * 0.42
                let spacing = (canvasSize.width - CGFloat(holeCount) * holeWidth) / CGFloat(holeCount + 1)

                UIColor(red: 0.94, green: 0.94, blue: 0.92, alpha: 1.0).setFill()
                for i in 0..<holeCount {
                    let x = spacing + CGFloat(i) * (holeWidth + spacing)
                    let topRect = CGRect(x: x, y: topBottomBarHeight * 0.34, width: holeWidth, height: holeHeight)
                    let bottomRect = CGRect(x: x, y: canvasSize.height - topBottomBarHeight + topBottomBarHeight * 0.24, width: holeWidth, height: holeHeight)
                    UIBezierPath(roundedRect: topRect, cornerRadius: holeWidth * 0.18).fill()
                    UIBezierPath(roundedRect: bottomRect, cornerRadius: holeWidth * 0.18).fill()
                }

                let fontSize = max(12, topBottomBarHeight * 0.18)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .bold),
                    .foregroundColor: UIColor(red: 0.88, green: 0.64, blue: 0.22, alpha: 0.88)
                ]
                let topText = "\(stock.edgeCode)   ISO \(stock.iso)" as NSString
                topText.draw(at: CGPoint(x: sideMargin, y: topBottomBarHeight * 0.08), withAttributes: attrs)

                let frameCode = String(format: "▶ %02dA", frameNumber) as NSString
                frameCode.draw(at: CGPoint(x: canvasSize.width - sideMargin - fontSize * 4.5, y: canvasSize.height - topBottomBarHeight * 0.25), withAttributes: attrs)
            }

            let photoRect = CGRect(x: sideMargin, y: topBottomBarHeight, width: baseSize.width, height: baseSize.height)
            positiveImage.draw(in: photoRect)

            if includeDateStamp {
                let formatter = DateFormatter()
                formatter.dateFormat = "''yy MM dd"
                let dateStr = formatter.string(from: captureDate) as NSString
                let stampFontSize = max(18, baseSize.width * 0.042)

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
                let stampPoint = CGPoint(x: photoRect.maxX - textSize.width - baseSize.width * 0.05, y: photoRect.maxY - textSize.height - baseSize.height * 0.04)
                dateStr.draw(at: stampPoint, withAttributes: stampAttrs)
            }
        }
    }
}

// MARK: - 4. ViewModel
final class FilmCameraViewModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureSessionControlsDelegate {
    @Published var stage: AppStage = .shooting
    @Published var allStocks: [FilmStock] = FilmStock.builtInStocks
    @Published var currentStock: FilmStock = FilmStock.builtInStocks[0]
    @Published var maxFramesPerRoll: Int = 12

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
    private var hardwareAdvanceSlider: AVCaptureSlider?
    private var lastHapticStep: Int = 0

    override init() {
        super.init()
        loadCustomStocks()
        setupCameraWithHardwareControl()
    }

    func setupCameraWithHardwareControl() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
               let input = try? AVCaptureDeviceInput(device: device),
               self.session.canAddInput(input) {
                self.session.addInput(input)
            }
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
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

    func loadNewRoll(stock: FilmStock, capacity: Int) {
        currentStock = stock
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
        saveLatentImageToDisk(normalizeOrientation(rawImg))
    }

    private func saveSimulatedLatentFrame() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800))
        let img = renderer.image { ctx in
            UIColor(red: 0.18, green: 0.28, blue: 0.35, alpha: 1.0).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
            UIColor(red: 0.95, green: 0.75, blue: 0.35, alpha: 1.0).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 450, y: 200, width: 300, height: 300))
        }
        saveLatentImageToDisk(img)
    }

    private func saveLatentImageToDisk(_ image: UIImage) {
        let fileName = "latent_\(UUID().uuidString).jpg"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
        try? image.jpegData(compressionQuality: 0.92)?.write(to: url)
        DispatchQueue.main.async {
            self.frames.append(FilmFrame(frameNumber: self.frames.count + 1, rawFileName: fileName, captureDate: Date()))
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
        HapticManager.shared.playFilmWoundLock()
        stage = .lightTableScanner
    }

    func loadRawImage(for frame: FilmFrame) -> UIImage {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(frame.rawFileName)
        return (try? Data(contentsOf: url)).flatMap { UIImage(data: $0) } ?? UIImage()
    }

    func importCubeLUT(from url: URL) throws {
        let parsed = try FilmColorEngine.shared.parseAndSaveCubeFile(from: url)
        let cleanTitle = url.deletingPathExtension().lastPathComponent.uppercased()
        let customStock = FilmStock(id: "custom_\(UUID().uuidString.prefix(6))", name: cleanTitle, subtitle: "自定义 3D LUT 胶卷", edgeCode: "\(cleanTitle) LUT", iso: 400, themeColorHex: "#8E44AD", customCubeFileName: parsed.fileName, cubeDimension: parsed.dimension)
        allStocks.append(customStock)
        currentStock = customStock
        saveCustomStocks()
    }

    private func saveCustomStocks() {
        let customs = allStocks.filter { $0.customCubeFileName != nil }
        if let data = try? JSONEncoder().encode(customs) { UserDefaults.standard.set(data, forKey: "SavedCustomFilmStocks") }
    }

    private func loadCustomStocks() {
        if let data = UserDefaults.standard.data(forKey: "SavedCustomFilmStocks"), let customs = try? JSONDecoder().decode([FilmStock].self, from: data) {
            allStocks = FilmStock.builtInStocks + customs
        }
    }

    private func normalizeOrientation(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return normalized ?? image
    }
}

// MARK: - 5. 视图封装
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

// MARK: - 舞台一：红树下 M 系列机械旁轴美学拍摄界面
struct VintageCameraShootingView: View {
    @ObservedObject var vm: FilmCameraViewModel
    @State private var showRollSheet = false
    @State private var showCubeImporter = false
    @State private var importAlertMessage: String?

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.05).ignoresSafeArea()

            VStack(spacing: 12) {
                // 1. 顶盖机械铭文
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.40, green: 0.40, blue: 0.38),
                                    Color(red: 0.20, green: 0.20, blue: 0.19),
                                    Color(red: 0.30, green: 0.29, blue: 0.27),
                                    Color(red: 0.12, green: 0.12, blue: 0.11)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(
                                    LinearGradient(colors: [.white.opacity(0.5), .clear, .white.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    lineWidth: 1.2
                                )
                        )
                        .shadow(color: .black.opacity(0.85), radius: 10, x: 0, y: 6)

                    VStack(spacing: 8) {
                        HStack {
                            CameraScrewIcon()
                            Text("HONGSHUXIA OPTIK · 35mm F/2.0")
                                .font(.system(size: 8.5, weight: .bold, design: .serif))
                                .tracking(2.2)
                                .foregroundColor(Color(red: 0.92, green: 0.88, blue: 0.80).opacity(0.85))
                            Spacer()
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(LinearGradient(colors: [.white.opacity(0.75), .gray.opacity(0.35), .white.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 30, height: 11)
                                .overlay(RoundedRectangle(cornerRadius: 2.5).stroke(Color.black, lineWidth: 1.2))
                            CameraScrewIcon()
                        }
                        .padding(.horizontal, 14)

                        HStack(spacing: 10) {
                            Button { showRollSheet = true } label: {
                                HStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color(hex: vm.currentStock.themeColorHex))
                                        .frame(width: 5, height: 26)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(vm.currentStock.name)
                                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                            .foregroundColor(Color(red: 1.0, green: 0.86, blue: 0.38))
                                        Text("ISO \(vm.currentStock.iso) / \(vm.maxFramesPerRoll)EXP")
                                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.black.opacity(0.85))
                                .cornerRadius(5)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.2), lineWidth: 1))
                            }

                            Spacer()

                            ZStack {
                                Circle()
                                    .fill(Color.black)
                                    .frame(width: 42, height: 42)
                                    .overlay(Circle().stroke(LinearGradient(colors: [.gray, .black, .white.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2))
                                VStack(spacing: 0) {
                                    Text("FRAME")
                                        .font(.system(size: 5.5, weight: .bold, design: .monospaced))
                                        .foregroundColor(.gray)
                                    Text(String(format: "%02d", vm.frames.count))
                                        .font(.system(size: 15, weight: .black, design: .monospaced))
                                        .foregroundColor(vm.isShutterLocked ? .orange : Color(red: 0.95, green: 0.92, blue: 0.82))
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

                // 2. 机身蒙皮与红树下铭牌
                ZStack {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color(red: 0.08, green: 0.08, blue: 0.09))
                        .overlay(LeatheretteGrainCanvas().clipShape(RoundedRectangle(cornerRadius: 22)).opacity(0.35))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22)
                                .strokeBorder(LinearGradient(colors: [.white.opacity(0.25), .black.opacity(0.95), .white.opacity(0.12)], startPoint: .top, endPoint: .bottom), lineWidth: 2)
                        )
                        .shadow(color: .black.opacity(0.9), radius: 12, x: 0, y: 8)

                    VStack(spacing: 14) {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(
                                        RadialGradient(colors: [Color(red: 0.92, green: 0.16, blue: 0.13), Color(red: 0.60, green: 0.06, blue: 0.05)], center: .topLeading, startRadius: 2, endRadius: 22)
                                    )
                                    .frame(width: 62, height: 20)
                                Text("红树下")
                                    .font(.system(size: 11, weight: .bold, design: .serif))
                                    .foregroundColor(.white)
                            }
                            .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 2)

                            Spacer()

                            HStack(spacing: 5) {
                                Circle()
                                    .fill(vm.isHardwareControlActive ? Color.green : (vm.isShutterLocked ? Color.orange : Color.red))
                                    .frame(width: 6, height: 6)
                                Text(vm.isHardwareControlActive ? "M-CONTROL ACTIVE" : (vm.isShutterLocked ? "LOCKED 待过片" : "READY"))
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(red: 0.85, green: 0.82, blue: 0.75))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(10)
                            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
                        }
                        .padding(.horizontal, 20)

                        ZStack {
                            CameraPreviewView(session: vm.session) { vm.handlePhysicalCameraButtonPress() }
                                .frame(width: 272, height: 202)
                                .clipShape(RoundedRectangle(cornerRadius: 10))

                            ZStack {
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [6, 3]))
                                    .padding(14)
                                Rectangle()
                                    .fill(Color.yellow.opacity(0.15))
                                    .frame(width: 40, height: 28)
                                    .overlay(Rectangle().stroke(Color.yellow.opacity(0.6), lineWidth: 0.8))
                            }
                            .frame(width: 272, height: 202)
                            .allowsHitTesting(false)

                            LinearGradient(colors: [.purple.opacity(0.1), .clear, .cyan.opacity(0.06), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                                .frame(width: 272, height: 202)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .allowsHitTesting(false)

                            if vm.isShutterLocked {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.black.opacity(0.75))
                                    .frame(width: 272, height: 202)
                                    .overlay(
                                        VStack(spacing: 8) {
                                            Image(systemName: "hand.tap.fill")
                                                .font(.system(size: 26))
                                                .foregroundColor(.orange)
                                            Text(vm.frames.count >= vm.maxFramesPerRoll
                                                 ? "整卷已拍满！请滑动相机键退卷送洗"
                                                 : "快门机械锁死 · 请滑动【相机控制键】或拨动扳手过片")
                                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                                .foregroundColor(.white)
                                                .multilineTextAlignment(.center)
                                                .padding(.horizontal, 16)
                                        }
                                    )
                            }
                        }
                        .padding(5)
                        .background(RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [Color(white: 0.25), Color(white: 0.08), Color(white: 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                        .shadow(color: .black.opacity(0.9), radius: 8, x: 0, y: 5)

                        HStack(spacing: 8) {
                            Image(systemName: "camera.aperture")
                                .foregroundColor(.orange)
                            Text("BLIND BOX · 拍满 \(vm.maxFramesPerRoll) 张后方可冲洗查看")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.75))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(6)
                    }
                    .padding(.vertical, 14)
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
                            Circle()
                                .fill(LinearGradient(colors: [Color(white: 0.7), Color(white: 0.25), Color(white: 0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 80, height: 80)
                                .shadow(color: .black.opacity(0.8), radius: 6, x: 0, y: 4)
                            Circle()
                                .stroke(Color.black.opacity(0.6), style: StrokeStyle(lineWidth: 3, dash: [2, 2]))
                                .frame(width: 74, height: 74)
                            Circle()
                                .fill(RadialGradient(colors: vm.isShutterLocked ? [Color(white: 0.3), Color(white: 0.15)] : [Color(red: 0.9, green: 0.18, blue: 0.14), Color(red: 0.55, green: 0.06, blue: 0.05)], center: .topLeading, startRadius: 4, endRadius: 40))
                                .frame(width: 60, height: 60)
                                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                            Circle()
                                .fill(Color(white: 0.1))
                                .frame(width: 16, height: 16)
                                .overlay(Circle().stroke(Color(white: 0.5), lineWidth: 1.2))
                        }
                    }
                    .disabled(vm.isShutterLocked)

                    Button { showRollSheet = true } label: {
                        KnurledMetalDialButton(icon: "film.stack.fill", title: "胶卷仓", accentColor: Color(red: 0.98, green: 0.82, blue: 0.32))
                    }
                }
                .padding(.bottom, 6)
            }
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

// 辅助组件：顶盖螺丝
struct CameraScrewIcon: View {
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(white: 0.5), Color(white: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 8, height: 8)
            Rectangle().fill(Color.black.opacity(0.8)).frame(width: 5, height: 1).rotationEffect(.degrees(30))
        }
    }
}

// 辅助组件：荔枝皮画布
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

// 辅助组件：滚花转盘
struct KnurledMetalDialButton: View {
    let icon: String
    let title: String
    let accentColor: Color
    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.26), Color(white: 0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 60, height: 60)
                .overlay(Circle().stroke(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 2, dash: [3, 2])))
                .shadow(color: .black.opacity(0.7), radius: 4, x: 0, y: 3)
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                Text(title).font(.system(size: 9, weight: .bold, design: .monospaced))
            }
            .foregroundColor(accentColor)
        }
    }
}

// 机械过片扳手
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

// 苹果相机风格滑动过片条
struct AppleCameraSlideAdvanceBar: View {
    let isLocked: Bool
    let progress: Double
    let onSlideProgress: (Double) -> Void
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "dial.medium.fill").font(.system(size: 10)).foregroundColor(isLocked ? .orange : .gray)
                Text(isLocked ? "滑动机身【相机控制键】或下方滑轨机械过片" : "快门已上弦 · 按实体按键或红钮拍摄")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
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
            .frame(height: 28)
        }
        .padding(8)
        .background(Color(white: 0.1))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
}

// 胶卷选择仓
struct FilmRollSelectorSheet: View {
    @ObservedObject var vm: FilmCameraViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCapacity: Int = 12

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("每卷暗盒张数（盲盒节奏）").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.gray)
                        Picker("每卷张数", selection: $selectedCapacity) {
                            Text("6 EXP · 极速体验").tag(6)
                            Text("12 EXP · 经典半卷").tag(12)
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                    Text("选择装填的 135 胶卷暗盒").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.gray).padding(.horizontal, 16)

                    ForEach(vm.allStocks) { stock in
                        Button {
                            vm.loadNewRoll(stock: stock, capacity: selectedCapacity)
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.22)).frame(width: 22, height: 60)
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(LinearGradient(colors: [Color(hex: stock.themeColorHex), Color.black.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: 44, height: 50)
                                        .overlay(VStack(spacing: 1) {
                                            Text("135").font(.system(size: 7.5, weight: .black, design: .monospaced)).foregroundColor(.white.opacity(0.8))
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
                                    Text(stock.subtitle).font(.system(size: 11.5, weight: .medium)).foregroundColor(.white.opacity(0.7))
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
            .navigationTitle("红树下 胶卷暗盒仓")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("关闭") { dismiss() }.foregroundColor(.orange) }
            }
        }
        .onAppear { selectedCapacity = vm.maxFramesPerRoll }
    }
}

// 阶段二：红光暗房
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

// 阶段三：看片台扫描与导出
struct LightTableScannerView: View {
    @ObservedObject var vm: FilmCameraViewModel
    @State private var selectedIndex: Int = 0
    @State private var borderStyle: ExportBorderStyle = .sprocket35mm
    @State private var includeDateStamp: Bool = true
    @State private var saveToastMessage: String?

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("HONGSHUXIA LIGHT TABLE 5500K").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                    Text("滑动扫描滑轨完成负片反转正片").font(.system(size: 10.5)).foregroundColor(.black.opacity(0.65))
                }
                Spacer()
                Button { vm.loadNewRoll(stock: vm.currentStock, capacity: vm.maxFramesPerRoll) } label: {
                    Text("装新卷").font(.system(size: 11, weight: .bold)).foregroundColor(.white).padding(.horizontal, 10).padding(.vertical, 6).background(Color.black).cornerRadius(6)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(white: 0.95))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(vm.frames.enumerated()), id: \.element.id) { idx, frame in
                        FilmStripNegativeCell(rawImage: vm.loadRawImage(for: frame), stock: vm.currentStock, frame: frame, isSelected: idx == selectedIndex)
                            .onTapGesture { selectedIndex = idx; HapticManager.shared.playRatchetTick() }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Color(red: 0.96, green: 0.96, blue: 0.94))
            .cornerRadius(8)
            .padding(.horizontal, 10)

            if vm.frames.indices.contains(selectedIndex) {
                let currentFrame = vm.frames[selectedIndex]
                let rawImg = vm.loadRawImage(for: currentFrame)
                let negImg = FilmColorEngine.shared.renderOrangeNegative(from: rawImg)
                let posImg = FilmColorEngine.shared.renderPositive(from: rawImg, stock: vm.currentStock, ev: currentFrame.exposureEV, warmth: currentFrame.warmthWB)

                InteractiveScannerStage(
                    negativeImage: negImg,
                    positiveImage: posImg,
                    scanProgress: Binding(
                        get: { vm.frames[selectedIndex].scanProgress },
                        set: { newVal in
                            vm.frames[selectedIndex].scanProgress = newVal
                            if newVal >= 0.98 { vm.frames[selectedIndex].isScanned = true }
                        }
                    )
                )
                .padding(.horizontal, 12)

                VStack(spacing: 8) {
                    HStack(spacing: 14) {
                        HStack {
                            Text("EV").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.orange)
                            Slider(value: Binding(get: { vm.frames[selectedIndex].exposureEV }, set: { vm.frames[selectedIndex].exposureEV = $0 }), in: -1.5...1.5).tint(.orange)
                        }
                        HStack {
                            Text("WB").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.yellow)
                            Slider(value: Binding(get: { vm.frames[selectedIndex].warmthWB }, set: { vm.frames[selectedIndex].warmthWB = $0 }), in: -1.0...1.0).tint(.yellow)
                        }
                    }

                    HStack {
                        Picker("边框", selection: $borderStyle) {
                            ForEach(ExportBorderStyle.allCases) { style in Text(style.rawValue).tag(style) }
                        }
                        .pickerStyle(.segmented)

                        Toggle("荧光日期", isOn: $includeDateStamp).font(.system(size: 11, weight: .semibold)).toggleStyle(.button).tint(.orange)
                    }

                    Button { exportAndSaveToPhotos(positiveImg: posImg, frame: currentFrame) } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down.fill")
                            Text(currentFrame.scanProgress >= 0.95 ? "导出成片至系统相册" : "请先向右拖动扫描滑块完成底片扫描")
                        }
                        .font(.system(size: 13, weight: .bold)).foregroundColor(.black).frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(currentFrame.scanProgress >= 0.95 ? Color.yellow : Color.gray.opacity(0.5)).cornerRadius(8)
                    }
                    .disabled(currentFrame.scanProgress < 0.95)
                }
                .padding(10)
                .background(Color.white.opacity(0.06))
                .cornerRadius(10)
                .padding(.horizontal, 10)
            }
            Spacer(minLength: 2)
        }
        .overlay(alignment: .top) {
            if let msg = saveToastMessage {
                Text(msg).font(.system(size: 12, weight: .bold)).foregroundColor(.black).padding(.horizontal, 14).padding(.vertical, 8).background(Color.green).cornerRadius(16).padding(.top, 50)
            }
        }
    }

    private func exportAndSaveToPhotos(positiveImg: UIImage, frame: FilmFrame) {
        let finalImg = FilmColorEngine.shared.composeFinalExportImage(positiveImage: positiveImg, stock: vm.currentStock, frameNumber: frame.frameNumber, captureDate: frame.captureDate, borderStyle: borderStyle, includeDateStamp: includeDateStamp)
        UIImageWriteToSavedPhotosAlbum(finalImg, nil, nil, nil)
        HapticManager.shared.playFilmWoundLock()
        withAnimation { saveToastMessage = "已成功导出第 \(frame.frameNumber) 张（\(borderStyle.rawValue)）！" }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { withAnimation { saveToastMessage = nil } }
    }
}

struct FilmStripNegativeCell: View {
    let rawImage: UIImage
    let stock: FilmStock
    let frame: FilmFrame
    let isSelected: Bool
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 5) { ForEach(0..<4, id: \.self) { _ in RoundedRectangle(cornerRadius: 1).fill(Color(red: 0.96, green: 0.96, blue: 0.94)).frame(width: 8, height: 5) } }
            Image(uiImage: frame.isScanned ? FilmColorEngine.shared.renderPositive(from: rawImage, stock: stock, ev: frame.exposureEV, warmth: frame.warmthWB) : FilmColorEngine.shared.renderOrangeNegative(from: rawImage))
                .resizable().scaledToFill().frame(width: 76, height: 52).clipped()
            HStack(spacing: 5) {
                Text(String(format: "%02dA", frame.frameNumber)).font(.system(size: 6.5, weight: .bold, design: .monospaced)).foregroundColor(.orange)
                ForEach(0..<2, id: \.self) { _ in RoundedRectangle(cornerRadius: 1).fill(Color(red: 0.96, green: 0.96, blue: 0.94)).frame(width: 8, height: 5) }
            }
        }
        .padding(4).background(Color.black).overlay(Rectangle().stroke(isSelected ? Color.orange : Color.clear, lineWidth: 2))
    }
}

struct InteractiveScannerStage: View {
    let negativeImage: UIImage
    let positiveImage: UIImage
    @Binding var scanProgress: Double
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let scannerX = width * CGFloat(scanProgress)
            ZStack(alignment: .leading) {
                Image(uiImage: negativeImage).resizable().scaledToFit().frame(width: width, height: height)
                Image(uiImage: positiveImage).resizable().scaledToFit().frame(width: width, height: height)
                    .mask(HStack(spacing: 0) { Rectangle().frame(width: max(0, scannerX)); Spacer(minLength: 0) })
                ZStack {
                    Rectangle().fill(Color.cyan).frame(width: 3, height: height).shadow(color: .cyan, radius: 8)
                    VStack {
                        Spacer()
                        HStack(spacing: 4) { Image(systemName: "viewfinder"); Text("扫描中").font(.system(size: 9, weight: .bold)) }
                            .foregroundColor(.black).padding(.horizontal, 6).padding(.vertical, 4).background(Color.cyan).cornerRadius(6).padding(.bottom, 10)
                    }
                }
                .offset(x: min(max(0, scannerX - 30), width - 60))
            }
            .background(Color(white: 0.95)).cornerRadius(10).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let ratio = min(max(Double(value.location.x / width), 0.0), 1.0)
                if abs(ratio - scanProgress) > 0.025 { HapticManager.shared.playScannerStepperPulse() }
                scanProgress = ratio
            })
        }
        .frame(height: 220)
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