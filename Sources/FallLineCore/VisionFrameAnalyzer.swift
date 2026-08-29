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
        if let r = humanDetectionRequest { requests.append(r) }

        let faceDetectionRequest = options.contains(.faceDetection)
            ? VNDetectFaceRectanglesRequest() : nil
        if let r = faceDetectionRequest { requests.append(r) }

        let textRequest: VNRecognizeTextRequest? = {
            guard options.contains(.textRecognition) else { return nil }
            let r = VNRecognizeTextRequest()
            r.recognitionLevel = .accurate
            r.recognitionLanguages = recognitionLanguages
            return r
        }()
        if let r = textRequest { requests.append(r) }

        let sceneRequest = options.contains(.sceneClassification)
            ? VNClassifyImageRequest() : nil
        if let r = sceneRequest { requests.append(r) }

        let bodyPoseRequest = options.contains(.bodyPose)
            ? VNDetectHumanBodyPoseRequest() : nil
        if let r = bodyPoseRequest { requests.append(r) }

        // 3D 姿态请求（macOS 14+）。与 2D 并行发出，由同一个 VNImageRequestHandler 一次批量执行。
        let bodyPose3DRequest: VNDetectHumanBodyPose3DRequest? = {
            guard options.contains(.bodyPose3D) else { return nil }
            if #available(macOS 14.0, iOS 17.0, *) {
                return VNDetectHumanBodyPose3DRequest()
            } else {
                return nil
            }
        }()
        if let r = bodyPose3DRequest { requests.append(r) }

        if !requests.isEmpty {
            try requestHandler.perform(requests)
        }

        let bodyPose3DObservation: VNHumanBodyPose3DObservation? = {
            if #available(macOS 14.0, iOS 17.0, *) {
                return bodyPose3DRequest?.results?.first
            } else {
                return nil
            }
        }()

        return RawVisionResult(
            humanDetections: humanDetectionRequest?.results ?? [],
            faceDetections: faceDetectionRequest?.results ?? [],
            textObservations: textRequest?.results ?? [],
            sceneClassifications: sceneRequest?.results ?? [],
            bodyPoseObservation: bodyPoseRequest?.results?.first,
            bodyPose3DObservation: bodyPose3DObservation
        )
    }
}
