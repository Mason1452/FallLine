import AVFoundation
import Vision
import CoreImage

// MARK: - Vision 分析选项

/// 控制每帧执行哪些 Vision 请求
///
/// 默认使用 `.skiAnalysis`（仅姿态检测），可以按需启用更多请求。
public struct VisionAnalysisOptions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let humanDetection       = VisionAnalysisOptions(rawValue: 1 << 0)
    public static let faceDetection        = VisionAnalysisOptions(rawValue: 1 << 1)
    public static let textRecognition      = VisionAnalysisOptions(rawValue: 1 << 2)
    public static let sceneClassification  = VisionAnalysisOptions(rawValue: 1 << 3)
    public static let bodyPose             = VisionAnalysisOptions(rawValue: 1 << 4)
    /// 3D 姿态检测（macOS 14+）。启用后与 2D 双路并行执行，3D 可用时优先。
    public static let bodyPose3D           = VisionAnalysisOptions(rawValue: 1 << 5)

    /// 滑雪分析默认：仅 2D 姿态检测（性能最优）
    public static let skiAnalysis: VisionAnalysisOptions = [.bodyPose]
    /// 滑雪 3D 增强：2D + 3D 双路，可解决透视歧义
    public static let skiAnalysis3D: VisionAnalysisOptions = [.bodyPose, .bodyPose3D]
    /// 全部请求
    public static let all: VisionAnalysisOptions = [
        .humanDetection, .faceDetection, .textRecognition,
        .sceneClassification, .bodyPose, .bodyPose3D
    ]
}

// MARK: - Vision 原始结果

/// Vision 请求的原始结果，用于后续处理
public struct RawVisionResult {
    public let humanDetections: [VNDetectedObjectObservation]
    public let faceDetections: [VNFaceObservation]
    public let textObservations: [VNRecognizedTextObservation]
    public let sceneClassifications: [VNClassificationObservation]
    public let bodyPoseObservation: VNHumanBodyPoseObservation?
    /// 可选的 3D 姿态观测（macOS 14+）。为 nil 表示未启用或本帧检测失败。
    public let bodyPose3DObservation: VNHumanBodyPose3DObservation?

    public init(humanDetections: [VNDetectedObjectObservation], faceDetections: [VNFaceObservation], textObservations: [VNRecognizedTextObservation], sceneClassifications: [VNClassificationObservation], bodyPoseObservation: VNHumanBodyPoseObservation?, bodyPose3DObservation: VNHumanBodyPose3DObservation? = nil) {
        self.humanDetections = humanDetections
        self.faceDetections = faceDetections
        self.textObservations = textObservations
        self.sceneClassifications = sceneClassifications
        self.bodyPoseObservation = bodyPoseObservation
        self.bodyPose3DObservation = bodyPose3DObservation
    }
}

// MARK: - Vision 帧分析器

/// 封装单帧的 Vision 请求执行和结果收集
///
/// 职责：
/// - 根据配置选项创建 Vision 请求
/// - 执行 `VNImageRequestHandler`
/// - 收集并返回原始结果
public class VisionFrameAnalyzer {

    /// 文字识别语言
    public let recognitionLanguages: [String]
    /// 控制执行哪些 Vision 请求（默认仅姿态检测）
    public let options: VisionAnalysisOptions

    /// 是否强制在 CPU 上执行 Vision 请求。
    ///
    /// 当 Neural Engine 上下文创建失败（模拟器/沙箱/首次冷启动）时，
    /// `VideoAnalyzer` 可以把这个开关切到 true 让整轮分析走 CPU 后备路径。
    /// CPU 路径慢但可用性极高，作为最后的降级手段。默认 false，CLI 不受影响。
    public var usesCPUOnly: Bool = false

    public init(
        recognitionLanguages: [String] = ["zh-Hans", "en-US"],
        options: VisionAnalysisOptions = .skiAnalysis
    ) {
        self.recognitionLanguages = recognitionLanguages
        self.options = options
    }

    // MARK: - 主入口

    /// 对单帧图像执行配置的 Vision 分析请求
    /// - Parameter cgImage: 输入图像
    /// - Returns: 所有 Vision 请求的原始结果（未启用的请求返回空结果）
    public func analyze(cgImage: CGImage) async throws -> RawVisionResult {
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        var requests: [VNRequest] = []

        // 仅当对应选项启用时才创建并添加请求
        let humanDetectionRequest = options.contains(.humanDetection)
            ? VNDetectHumanRectanglesRequest() : nil
        if let r = humanDetectionRequest { r.usesCPUOnly = usesCPUOnly; requests.append(r) }

        let faceDetectionRequest = options.contains(.faceDetection)
            ? VNDetectFaceRectanglesRequest() : nil
        if let r = faceDetectionRequest { r.usesCPUOnly = usesCPUOnly; requests.append(r) }

        let textRequest: VNRecognizeTextRequest? = {
            guard options.contains(.textRecognition) else { return nil }
            let r = VNRecognizeTextRequest()
            r.recognitionLevel = .accurate
            r.recognitionLanguages = recognitionLanguages
            return r
        }()
        if let r = textRequest { r.usesCPUOnly = usesCPUOnly; requests.append(r) }

        let sceneRequest = options.contains(.sceneClassification)
            ? VNClassifyImageRequest() : nil
        if let r = sceneRequest { r.usesCPUOnly = usesCPUOnly; requests.append(r) }

        let bodyPoseRequest = options.contains(.bodyPose)
            ? VNDetectHumanBodyPoseRequest() : nil
        if let r = bodyPoseRequest { r.usesCPUOnly = usesCPUOnly; requests.append(r) }

        // 3D 姿态请求（macOS 14+）：不与 2D 同批，改为下方「2D 检出姿态后再补跑」。
        let wantsBodyPose3D: Bool = {
            guard options.contains(.bodyPose3D) else { return false }
            if #available(macOS 14.0, iOS 17.0, *) { return true } else { return false }
        }()

        // 第一阶段：除 3D 外的全部请求（含 2D 姿态），一次批量执行。
        if !requests.isEmpty {
            try autoreleasepool {
                try requestHandler.perform(requests)
            }
        }

        // 第二阶段：仅当 2D 检出姿态时才在同一图像上补跑 3D。
        // 3D 结果只在 PoseMetrics3DAdapter.fuse（且 2D 也检测到姿态）时被采用，
        // 2D 未检出时跑 3D 纯属浪费（约占三成调用）。两阶段在同一图像上独立推理，
        // 3D 输出与旧的「单次批量双路」一致，故结果不变、成本下降。
        var bodyPose3DObservation: VNHumanBodyPose3DObservation?
        if wantsBodyPose3D, bodyPoseRequest?.results?.first != nil {
            let bodyPose3DRequest = VNDetectHumanBodyPose3DRequest()
            bodyPose3DRequest.revision = VNDetectHumanBodyPose3DRequestRevision1
            bodyPose3DRequest.usesCPUOnly = usesCPUOnly
            try autoreleasepool {
                try requestHandler.perform([bodyPose3DRequest])
            }
            if #available(macOS 14.0, iOS 17.0, *) {
                bodyPose3DObservation = bodyPose3DRequest.results?.first
            }
        }

        return RawVisionResult(
            humanDetections: humanDetectionRequest?.results ?? [],
            faceDetections: faceDetectionRequest?.results ?? [],
            textObservations: textRequest?.results ?? [],
            sceneClassifications: sceneRequest?.results ?? [],
            bodyPoseObservation: bodyPoseRequest?.results?.first,
            bodyPose3DObservation: bodyPose3DObservation
        )
    }

    // MARK: - 预热

    /// 用一张 1×1 的白色占位图跑一次核心 Vision 姿态请求，让 espresso 上下文提前初始化。
    ///
    /// - 目的：把 "Failed to create espresso context" 这类初始化错误在正式抽帧之前暴露出来，
    ///   避免用户等 30 秒才被告知"分析失败"。
    /// - 失败时会把原始错误抛给调用方（`VideoAnalyzer` 负责处理 CPU 回退与最终熔断）。
    /// - 仅在 iOS/沙箱环境有意义；CLI 场景一般不需要调用。
    public func warmUp() async throws {
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
