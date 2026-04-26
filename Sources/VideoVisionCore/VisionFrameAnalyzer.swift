import AVFoundation
import Vision
import CoreImage

// MARK: - Vision 原始结果

/// Vision 请求的原始结果，用于后续处理
public struct RawVisionResult {
    public let humanDetections: [VNDetectedObjectObservation]
    public let faceDetections: [VNFaceObservation]
    public let textObservations: [VNRecognizedTextObservation]
    public let sceneClassifications: [VNClassificationObservation]
    public let bodyPoseObservation: VNHumanBodyPoseObservation?

    public init(humanDetections: [VNDetectedObjectObservation], faceDetections: [VNFaceObservation], textObservations: [VNRecognizedTextObservation], sceneClassifications: [VNClassificationObservation], bodyPoseObservation: VNHumanBodyPoseObservation?) {
        self.humanDetections = humanDetections
        self.faceDetections = faceDetections
        self.textObservations = textObservations
        self.sceneClassifications = sceneClassifications
        self.bodyPoseObservation = bodyPoseObservation
    }
}

// MARK: - Vision 帧分析器

/// 封装单帧的 Vision 请求执行和结果收集
///
/// 职责：
/// - 创建并配置所有 Vision 请求
/// - 执行 `VNImageRequestHandler`
/// - 收集并返回原始结果
public class VisionFrameAnalyzer {

    /// 文字识别语言
    public let recognitionLanguages: [String]

    public init(recognitionLanguages: [String] = ["zh-Hans", "en-US"]) {
        self.recognitionLanguages = recognitionLanguages
    }

    // MARK: - 主入口

    /// 对单帧图像执行所有 Vision 分析请求
    /// - Parameter cgImage: 输入图像
    /// - Returns: 所有 Vision 请求的原始结果
    public func analyze(cgImage: CGImage) async throws -> RawVisionResult {
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        // 1. 人体检测
        let humanDetectionRequest = VNDetectHumanRectanglesRequest()

        // 2. 人脸检测
        let faceDetectionRequest = VNDetectFaceRectanglesRequest()

        // 3. 文字识别
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.recognitionLanguages = recognitionLanguages

        // 4. 场景分类（结果在 VideoAnalyzer 中按阈值过滤）
        let sceneRequest = VNClassifyImageRequest()

        // 5. 人体姿态识别
        let bodyPoseRequest = VNDetectHumanBodyPoseRequest()

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
}
