//
//  SoundClassifierService.swift
//  WindWhisper
//
//  声音分类服务 - Core ML模型分类 wind/bird/rain
//

import Accelerate
import Combine
import Foundation

@MainActor
final class SoundClassifierService: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var currentClassification: SoundType = .unknown
    @Published private(set) var confidence: Float = 0.0
    @Published private(set) var isProcessing = false

    // MARK: - Private Properties

    private var audioBuffer: [Float] = []
    private let bufferSize = 44100 // 1秒的样本 @ 44.1kHz
    private var classificationHistory: [SoundType] = []
    private let historySize = 10

    // MARK: - Singleton

    static let shared = SoundClassifierService()

    private init() {}

    // MARK: - Classification

    /// 处理音频样本并进行分类
    func processAudioSamples(_ samples: [Float]) {
        audioBuffer.append(contentsOf: samples)

        // 保持缓冲区大小
        if audioBuffer.count > bufferSize {
            audioBuffer = Array(audioBuffer.suffix(bufferSize))
        }

        // 每积累足够样本后进行分类
        if audioBuffer.count >= bufferSize / 2 {
            classifyCurrentBuffer()
        }
    }

    /// 对当前缓冲区进行分类
    private func classifyCurrentBuffer() {
        isProcessing = true

        // 提取特征
        let features = extractFeatures(from: audioBuffer)

        // 使用简化的分类逻辑（实际应使用Core ML模型）
        let (soundType, conf) = classifyFromFeatures(features)

        // 更新历史记录以平滑结果
        classificationHistory.append(soundType)
        if classificationHistory.count > historySize {
            classificationHistory.removeFirst()
        }

        // 使用投票机制确定最终分类
        let finalType = getMostFrequentType()

        currentClassification = finalType
        confidence = conf
        isProcessing = false
    }

    // MARK: - Feature Extraction

    private struct AudioFeatures {
        var zeroCrossingRate: Float
        var spectralCentroid: Float
        var rmsEnergy: Float
        var spectralFlatness: Float
        var highFrequencyRatio: Float
    }

    private func extractFeatures(from samples: [Float]) -> AudioFeatures {
        let count = samples.count
        guard count > 0 else {
            return AudioFeatures(
                zeroCrossingRate: 0,
                spectralCentroid: 0,
                rmsEnergy: 0,
                spectralFlatness: 0,
                highFrequencyRatio: 0
            )
        }

        // 1. 过零率 (Zero Crossing Rate)
        var zeroCrossings = 0
        for i in 1..<count {
            if (samples[i] >= 0 && samples[i-1] < 0) || (samples[i] < 0 && samples[i-1] >= 0) {
                zeroCrossings += 1
            }
        }
        let zcr = Float(zeroCrossings) / Float(count)

        // 2. RMS能量
        var sumSquares: Float = 0
        vDSP_svesq(samples, 1, &sumSquares, vDSP_Length(count))
        let rms = sqrt(sumSquares / Float(count))

        // 3. 简化的频谱分析（使用FFT需要更复杂实现，这里用近似）
        // 通过高通滤波估计高频成分
        var highFreqEnergy: Float = 0
        var prevSample: Float = 0
        for sample in samples {
            let highPass = sample - prevSample
            highFreqEnergy += highPass * highPass
            prevSample = sample
        }
        let hfRatio = sqrt(highFreqEnergy / Float(count)) / max(rms, 0.001)

        // 4. 谱平坦度近似（使用变化率）
        var variance: Float = 0
        var mean: Float = 0
        vDSP_meanv(samples, 1, &mean, vDSP_Length(count))
        for sample in samples {
            variance += (sample - mean) * (sample - mean)
        }
        let flatness = variance / Float(count) / max(rms * rms, 0.0001)

        return AudioFeatures(
            zeroCrossingRate: zcr,
            spectralCentroid: hfRatio * 1000, // 近似
            rmsEnergy: rms,
            spectralFlatness: min(1.0, flatness),
            highFrequencyRatio: min(1.0, hfRatio)
        )
    }

    // MARK: - Classification Logic

    private func classifyFromFeatures(_ features: AudioFeatures) -> (SoundType, Float) {
        // 基于特征的简化分类规则
        // 实际项目应使用训练好的Core ML模型

        var scores: [SoundType: Float] = [:]

        // 风声特征：低频为主，持续稳定，低过零率
        let windScore = (1.0 - features.highFrequencyRatio) * 0.4 +
                        (1.0 - features.zeroCrossingRate * 10) * 0.3 +
                        features.spectralFlatness * 0.3
        scores[.wind] = max(0, min(1, windScore))

        // 鸟鸣特征：高频突发，高过零率，不规则
        let birdScore = features.highFrequencyRatio * 0.4 +
                        features.zeroCrossingRate * 5 * 0.3 +
                        (1.0 - features.spectralFlatness) * 0.3
        scores[.bird] = max(0, min(1, birdScore))

        // 雨声特征：宽频噪声，中等能量，高平坦度
        let rainScore = features.spectralFlatness * 0.5 +
                        (0.5 - abs(features.rmsEnergy - 0.3)) * 0.3 +
                        features.highFrequencyRatio * 0.2
        scores[.rain] = max(0, min(1, rainScore))

        // 溪流特征：低中频，持续变化
        let streamScore = (0.5 - abs(features.highFrequencyRatio - 0.3)) * 0.4 +
                          features.spectralFlatness * 0.3 +
                          features.rmsEnergy * 0.3
        scores[.stream] = max(0, min(1, streamScore))

        // 树叶特征：间歇性沙沙声，中等过零率
        let leavesScore = (0.5 - abs(features.zeroCrossingRate * 10 - 0.5)) * 0.4 +
                          features.highFrequencyRatio * 0.3 +
                          (1.0 - features.rmsEnergy * 2) * 0.3
        scores[.leaves] = max(0, min(1, leavesScore))

        // 选择最高分
        var bestType: SoundType = .unknown
        var bestScore: Float = 0.3 // 最低阈值

        for (type, score) in scores {
            if score > bestScore {
                bestScore = score
                bestType = type
            }
        }

        return (bestType, bestScore)
    }

    private func getMostFrequentType() -> SoundType {
        guard !classificationHistory.isEmpty else { return .unknown }

        var counts: [SoundType: Int] = [:]
        for type in classificationHistory {
            counts[type, default: 0] += 1
        }

        return counts.max(by: { $0.value < $1.value })?.key ?? .unknown
    }

    // MARK: - Public Methods

    func reset() {
        audioBuffer.removeAll()
        classificationHistory.removeAll()
        currentClassification = .unknown
        confidence = 0.0
    }

    /// 对完整录音进行分类
    func classifyRecording(_ recording: SoundRecording, audioSamples: [Float]) -> SoundRecording {
        reset()
        processAudioSamples(audioSamples)

        return SoundRecording(
            id: recording.id,
            soundType: currentClassification,
            duration: recording.duration,
            timestamp: recording.timestamp,
            locationName: recording.locationName,
            latitude: recording.latitude,
            longitude: recording.longitude,
            audioFileURL: recording.audioFileURL,
            confidence: confidence
        )
    }
}
