import AVFoundation
import Vision
import CoreImage
import CoreGraphics

// MARK: - Vision 原始结果

/// Vision 请求的原始结果，用于后续处理
struct RawVisionResult {
    let humanDetections: [VNDetectedObjectObservation]
    let faceDetections: [VNFaceObservation]
    let textObservations: [VNRecognizedTextObservation]
    let sceneClassifications: [VNClassificationObservation]
    let bodyPoseObservation: VNHumanBodyPoseObservation?
}

// MARK: - Vision 帧分析器

/// 封装单帧的 Vision 请求执行和结果收集
///
/// 职责：
/// - 创建并配置所有 Vision 请求
/// - 执行 `VNImageRequestHandler`
/// - 收集并返回原始结果
class VisionFrameAnalyzer {

    /// 文字识别语言
    let recognitionLanguages: [String]

    /// 是否强制在 CPU 上执行 Vision 请求。
    ///
    /// 当 Neural Engine 上下文创建失败（模拟器/沙箱/首次冷启动）时，
    /// `VideoAnalyzer` 会把这个开关切到 true 让整轮分析走 CPU 后备路径。
    /// CPU 路径慢但可用性极高，作为最后的降级手段。
    var usesCPUOnly: Bool = false

    init(recognitionLanguages: [String] = ["zh-Hans", "en-US"]) {
        self.recognitionLanguages = recognitionLanguages
    }

    // MARK: - 主入口

    /// 对单帧图像执行所有 Vision 分析请求
    /// - Parameter cgImage: 输入图像
    /// - Returns: 所有 Vision 请求的原始结果
    func analyze(cgImage: CGImage) async throws -> RawVisionResult {
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        // 1. 人体检测
        let humanDetectionRequest = VNDetectHumanRectanglesRequest()
        humanDetectionRequest.usesCPUOnly = usesCPUOnly

        // 2. 人脸检测
        let faceDetectionRequest = VNDetectFaceRectanglesRequest()
        faceDetectionRequest.usesCPUOnly = usesCPUOnly

        // 3. 文字识别
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.recognitionLanguages = recognitionLanguages
        textRequest.usesCPUOnly = usesCPUOnly

        // 4. 场景分类（结果在 VideoAnalyzer 中按阈值过滤）
        let sceneRequest = VNClassifyImageRequest()
        sceneRequest.usesCPUOnly = usesCPUOnly

        // 5. 人体姿态识别（核心，espresso 上下文最常在此触发）
        let bodyPoseRequest = VNDetectHumanBodyPoseRequest()
        bodyPoseRequest.usesCPUOnly = usesCPUOnly

        try requestHandler.perform([
            humanDetectionRequest,
            faceDetectionRequest,
            textRequest,
            sceneRequest,
            bodyPoseRequest
        ])

        return RawVisionResult(
            humanDetections: humanDetectionRequest.results ?? [],
            faceDetections: faceDetectionRequest.results ?? [],
            textObservations: textRequest.results ?? [],
            sceneClassifications: sceneRequest.results ?? [],
            bodyPoseObservation: bodyPoseRequest.results?.first
        )
    }

    // MARK: - 预热

    /// 用一张 1×1 的白色占位图跑一次核心 Vision 请求，让 espresso 上下文提前初始化。
    ///
    /// - 目的：把 "Failed to create espresso context" 这类初始化错误在正式抽帧之前暴露出来，
    ///   避免用户等 30 秒才被告知"分析失败"。
    /// - 失败时会把原始错误抛给调用方（`VideoAnalyzer` 负责处理 CPU 回退与最终熔断）。
    func warmUp() async throws {
        guard let image = Self.makePlaceholderImage() else { return }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let bodyPoseRequest = VNDetectHumanBodyPoseRequest()
        bodyPoseRequest.usesCPUOnly = usesCPUOnly
        try handler.perform([bodyPoseRequest])
    }

    /// 构造一张 1×1 的白色 CGImage，仅用于预热，不参与业务。
    private static func makePlaceholderImage() -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = 4
        var pixel: [UInt8] = [255, 255, 255, 255]
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        return context.makeImage()
    }
}
