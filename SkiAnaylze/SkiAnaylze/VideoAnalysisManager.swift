import Foundation
import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import FallLineCore
// MARK: - 分析步骤

enum AnalysisStep: Int, CaseIterable {
    case reading = 0
    case extracting
    case poseDetection
    case calculating
    case generating

    var label: String {
        switch self {
        case .reading:       return "读取视频"
        case .extracting:    return "抽取关键帧"
        case .poseDetection: return "识别人体姿态"
        case .calculating:   return "计算滑雪动作指标"
        case .generating:    return "生成报告"
        }
    }
}

// MARK: - 分析状态

enum AnalysisState {
    case idle
    case selectingVideo
    case confirmingVideo(url: URL, duration: TimeInterval, estimatedFrames: Int)
    case analyzing(progress: Double, step: AnalysisStep)
    case completed(output: AnalysisOutput)
    case failed(error: String)
}

// MARK: - 视频分析管理器

@MainActor
class VideoAnalysisManager: ObservableObject {
    @Published var state: AnalysisState = .idle
    @Published var historyURLs: [URL] = []

    let trendStore = TrendStore()

    private var allAnalysisOutputs: [URL: AnalysisOutput] = [:]
    private var isCancelled = false

    static let shared = VideoAnalysisManager()

    private init() {
        loadHistory()
        loadOutputs()
        if historyURLs.isEmpty {
            injectDemoEntry()
        }
    }

    // MARK: - 选择视频

    func didPickVideo(url: URL) {
        let asset = AVAsset(url: url)
        Task {
            do {
                let duration = try await asset.load(.duration)
                let totalSeconds = CMTimeGetSeconds(duration)
                let estimatedFrames = Int(totalSeconds.rounded(.up))
                state = .confirmingVideo(
                    url: url,
                    duration: totalSeconds,
                    estimatedFrames: estimatedFrames
                )
            } catch {
                state = .failed(error: "无法读取视频：\(error.localizedDescription)")
            }
        }
    }

    // MARK: - 开始分析

    func startAnalysis(videoURL: URL) {
        state = .analyzing(progress: 0, step: .reading)
        isCancelled = false

        Task {
            do {
                try await performAnalysis(videoURL: videoURL)
            } catch is CancellationError {
                // Task 取消不视为失败
                return
            } catch let analysisError as AnalysisError {
                // 已本地化的分析错误：直接使用其中文描述
                if !isCancelled {
                    print("❌ 分析失败(AnalysisError): \(analysisError.errorDescription ?? "")")
                    if case .visionUnavailable(_, let underlying) = analysisError {
                        print("   原始错误: \(underlying)")
                    }
                    state = .failed(error: analysisError.errorDescription ?? "分析失败")
                }
            } catch {
                if !isCancelled {
                    print("❌ 分析失败(unknown): \(error.localizedDescription)")
                    state = .failed(error: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - 取消分析

    func cancelAnalysis() {
        isCancelled = true
        state = .idle
    }

    // MARK: - 获取已保存的分析结果

    func output(for url: URL) -> AnalysisOutput? {
        allAnalysisOutputs[url]
    }

    // MARK: - 核心分析逻辑

    private func performAnalysis(videoURL: URL) async throws {
        // Step 1: 读取视频
        updateProgress(step: .reading, progress: 0.1)
        try Task.checkCancellation()

        let analyzer = VideoAnalyzer(videoURL: videoURL)
        let duration = try await analyzer.asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)
        try Task.checkCancellation()

        // Step 2: 抽取关键帧
        updateProgress(step: .extracting, progress: 0.2)
        try Task.checkCancellation()
        try await Task.sleep(nanoseconds: 500_000_000) // 模拟

        // Step 3: 识别人体姿态
        updateProgress(step: .poseDetection, progress: 0.4)
        try Task.checkCancellation()
        try await Task.sleep(nanoseconds: 500_000_000) // 模拟

        // Step 4: 计算指标
        updateProgress(step: .calculating, progress: 0.6)
        let results = try await analyzer.analyze()
        try Task.checkCancellation()

        let summary = await analyzer.generateSummary(from: results)
        let stability = summary?.stabilityScore ?? 50

        let framesWithMetrics = results.map { frame -> DetectionResult in
            var f = frame
            if let score = frame.poseScore {
                let sm = SkiMetricsCalculator.compute(from: score, stability: stability)
                f.skiMetrics = sm
            }
            return f
        }

        let avgSkiMetrics = SkiMetricsCalculator.average(from: framesWithMetrics, stability: stability)
        let keyMoments = KeyMomentDetector.detect(from: framesWithMetrics, duration: totalSeconds)

        // Step 5: 生成报告
        updateProgress(step: .generating, progress: 0.8)
        let output = AnalysisOutput(
            videoPath: videoURL.lastPathComponent,
            duration: totalSeconds,
            totalFrames: results.count,
            frames: framesWithMetrics,
            summary: summary ?? VideoSummary(
                averageScore: 0,
                bestFrame: FrameScore(time: 0, timeString: "00:00", score: 0),
                worstFrame: FrameScore(time: 0, timeString: "00:00", score: 0),
                stabilityScore: 0,
                scoreConsistencyScore: 0,
                scoreStdDev: 0,
                overallLevel: "未检测到人体"
            ),
            skiMetrics: avgSkiMetrics,
            keyMoments: keyMoments
        )

        try Task.checkCancellation()
        updateProgress(step: .generating, progress: 1.0)
        try await Task.sleep(nanoseconds: 300_000_000) // 收尾

        allAnalysisOutputs[videoURL] = output
        saveHistory(url: videoURL)

        // 进步曲线埋点：记录本次分析，返回新解锁的里程碑并推送本地通知
        let newMilestones = trendStore.record(
            averageScore: output.summary.averageScore,
            overallLevel: output.summary.overallLevel,
            stabilityScore: output.summary.stabilityScore,
            bestFrameScore: output.summary.bestFrame.score
        )
        if !newMilestones.isEmpty {
            Task {
                await TrendNotificationCenter.shared.scheduleMilestoneNotifications(newMilestones)
            }
        }

        state = .completed(output: output)
    }

    private func updateProgress(step: AnalysisStep, progress: Double) {
        state = .analyzing(progress: progress, step: step)
    }

    // MARK: - 历史记录管理

    private func historyFileURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("video_history.json")
    }

    private func loadHistory() {
        let url = historyFileURL()
        guard let data = try? Data(contentsOf: url),
              let paths = try? JSONDecoder().decode([String].self, from: data) else {
            return
        }
        historyURLs = paths.compactMap { URL(string: $0) }
    }

    private func saveHistory(url: URL) {
        if !historyURLs.contains(url) {
            historyURLs.insert(url, at: 0)
        }
        let paths = historyURLs.map { $0.absoluteString }
        if let data = try? JSONEncoder().encode(paths) {
            try? data.write(to: historyFileURL())
        }
        saveOutputs()
    }

    // MARK: - 分析结果持久化

    private func outputsFileURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("analyses.json")
    }

    private func saveOutputs() {
        var dict: [String: AnalysisOutput] = [:]
        for (key, value) in allAnalysisOutputs {
            dict[key.absoluteString] = value
        }
        if let data = try? JSONEncoder().encode(dict) {
            try? data.write(to: outputsFileURL())
        }
    }

    private func loadOutputs() {
        let url = outputsFileURL()
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: AnalysisOutput].self, from: data) else {
            return
        }
        var outputs: [URL: AnalysisOutput] = [:]
        for (key, value) in dict {
            if let url = URL(string: key) {
                outputs[url] = value
            }
        }
        allAnalysisOutputs = outputs
    }

    // MARK: - 默认演示数据

    private func injectDemoEntry() {
        let demoURL = URL(fileURLWithPath: "/Users/mingsen/Project/FallLine/a3_analyzed.mp4")
        let output = DemoData.makeDemoOutput()
        allAnalysisOutputs[demoURL] = output
        historyURLs = [demoURL]
        let paths = historyURLs.map { $0.absoluteString }
        if let data = try? JSONEncoder().encode(paths) {
            try? data.write(to: historyFileURL())
        }
        saveOutputs()
    }

    // MARK: - 删除历史记录

    func removeHistory(at offsets: IndexSet) {
        for index in offsets {
            if index < historyURLs.count {
                let url = historyURLs[index]
                allAnalysisOutputs.removeValue(forKey: url)
                historyURLs.remove(at: index)
            }
        }
        let paths = historyURLs.map { $0.absoluteString }
        if let data = try? JSONEncoder().encode(paths) {
            try? data.write(to: historyFileURL())
        }
        saveOutputs()
    }
}
