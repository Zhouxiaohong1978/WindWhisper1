//
//  BGMGeneratorService.swift
//  WindWhisper
//
//  BGM生成服务 - AI频率调制生成疗愈音乐
//

import AVFoundation
import Combine
import UIKit

@MainActor
final class BGMGeneratorService: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var isGenerating = false
    @Published private(set) var progress: Float = 0.0
    @Published private(set) var currentBGM: GeneratedBGM?

    // MARK: - Private Properties

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var audioFile: AVAudioFile?

    // 生成参数
    private let sampleRate: Double = 44100
    private let duration: TimeInterval = 180 // 3分钟

    // MARK: - Singleton

    static let shared = BGMGeneratorService()

    private init() {}

    // MARK: - Generation

    /// 基于声音录制生成BGM
    func generateBGM(
        from recording: SoundRecording,
        style: BGMStyle,
        onProgress: ((Float) -> Void)? = nil
    ) async throws -> GeneratedBGM {
        isGenerating = true
        progress = 0.0

        defer {
            isGenerating = false
        }

        // 触觉反馈 - 开始
        await triggerHaptic(.medium)

        // 根据声音类型和风格确定生成参数
        let params = getGenerationParams(soundType: recording.soundType, style: style)

        // 生成音频数据
        let audioData = try await generateAudioData(params: params) { prog in
            Task { @MainActor in
                self.progress = prog
                onProgress?(prog)
            }
        }

        // 保存音频文件
        let fileURL = try saveAudioFile(audioData, sampleRate: sampleRate)

        // 触觉反馈 - 完成
        await triggerHaptic(.success)

        // 创建BGM对象
        let bgm = GeneratedBGM(
            name: generateBGMName(soundType: recording.soundType, style: style),
            style: style,
            basedOnRecording: recording.id,
            duration: duration,
            audioFileURL: fileURL.path
        )

        currentBGM = bgm
        progress = 1.0

        return bgm
    }

    // MARK: - Audio Generation

    private struct GenerationParams {
        var baseFrequency: Float
        var harmonics: [Float]
        var modulationDepth: Float
        var modulationRate: Float
        var noiseLevel: Float
        var attackTime: Float
        var releaseTime: Float
        var reverbMix: Float
    }

    private func getGenerationParams(soundType: SoundType, style: BGMStyle) -> GenerationParams {
        // 基础参数根据声音类型调整
        var baseFreq: Float = 220.0
        var harmonics: [Float] = [1.0, 0.5, 0.25]
        var noiseLevel: Float = 0.1

        switch soundType {
        case .wind:
            baseFreq = 110.0
            noiseLevel = 0.3
            harmonics = [1.0, 0.3, 0.1]
        case .bird:
            baseFreq = 440.0
            noiseLevel = 0.05
            harmonics = [1.0, 0.7, 0.5, 0.3]
        case .rain:
            baseFreq = 165.0
            noiseLevel = 0.4
            harmonics = [1.0, 0.4, 0.2]
        case .stream:
            baseFreq = 196.0
            noiseLevel = 0.25
            harmonics = [1.0, 0.5, 0.3, 0.15]
        case .leaves:
            baseFreq = 247.0
            noiseLevel = 0.15
            harmonics = [1.0, 0.6, 0.35]
        case .unknown:
            baseFreq = 220.0
        }

        // 风格调整
        var modDepth: Float = 0.3
        var modRate: Float = 0.5
        var reverbMix: Float = 0.4

        switch style {
        case .gentle:
            modDepth = 0.2
            modRate = 0.3
            reverbMix = 0.5
        case .meditation:
            modDepth = 0.15
            modRate = 0.1
            baseFreq *= 0.5 // 更低频
            reverbMix = 0.6
        case .nature:
            modDepth = 0.35
            modRate = 0.4
            noiseLevel *= 1.5
            reverbMix = 0.3
        case .deepSleep:
            modDepth = 0.1
            modRate = 0.05
            baseFreq *= 0.25 // 极低频
            reverbMix = 0.7
        }

        return GenerationParams(
            baseFrequency: baseFreq,
            harmonics: harmonics,
            modulationDepth: modDepth,
            modulationRate: modRate,
            noiseLevel: noiseLevel,
            attackTime: 2.0,
            releaseTime: 3.0,
            reverbMix: reverbMix
        )
    }

    private func generateAudioData(
        params: GenerationParams,
        onProgress: @escaping (Float) -> Void
    ) async throws -> [Float] {
        let totalSamples = Int(sampleRate * duration)
        var audioData = [Float](repeating: 0, count: totalSamples)

        let updateInterval = totalSamples / 100

        for i in 0..<totalSamples {
            let t = Float(i) / Float(sampleRate)

            // 基础波形（正弦波叠加）
            var sample: Float = 0
            for (index, amplitude) in params.harmonics.enumerated() {
                let freq = params.baseFrequency * Float(index + 1)
                let phase = 2.0 * Float.pi * freq * t

                // 添加缓慢的频率调制
                let modulation = sin(2.0 * Float.pi * params.modulationRate * t) * params.modulationDepth
                sample += amplitude * sin(phase * (1.0 + modulation))
            }

            // 添加噪声（模拟自然声）
            let noise = (Float.random(in: -1...1)) * params.noiseLevel
            sample += noise

            // 淡入淡出包络
            let envelope = calculateEnvelope(
                sampleIndex: i,
                totalSamples: totalSamples,
                attackSamples: Int(params.attackTime * Float(sampleRate)),
                releaseSamples: Int(params.releaseTime * Float(sampleRate))
            )

            audioData[i] = sample * envelope * 0.3 // 整体音量控制

            // 更新进度
            if i % updateInterval == 0 {
                onProgress(Float(i) / Float(totalSamples))
            }

            // 让出CPU避免阻塞
            if i % 10000 == 0 {
                await Task.yield()
            }
        }

        // 应用简单的混响效果
        audioData = applySimpleReverb(audioData, mix: params.reverbMix)

        return audioData
    }

    private func calculateEnvelope(
        sampleIndex: Int,
        totalSamples: Int,
        attackSamples: Int,
        releaseSamples: Int
    ) -> Float {
        if sampleIndex < attackSamples {
            // 淡入
            return Float(sampleIndex) / Float(attackSamples)
        } else if sampleIndex > totalSamples - releaseSamples {
            // 淡出
            return Float(totalSamples - sampleIndex) / Float(releaseSamples)
        }
        return 1.0
    }

    private func applySimpleReverb(_ input: [Float], mix: Float) -> [Float] {
        var output = input
        let delays = [Int(0.03 * sampleRate), Int(0.05 * sampleRate), Int(0.07 * sampleRate)]
        let decays: [Float] = [0.5, 0.35, 0.25]

        for (delay, decay) in zip(delays, decays) {
            for i in delay..<input.count {
                output[i] += input[i - delay] * decay * mix
            }
        }

        // 归一化
        let maxAmp = output.map { abs($0) }.max() ?? 1.0
        if maxAmp > 1.0 {
            output = output.map { $0 / maxAmp }
        }

        return output
    }

    // MARK: - File Operations

    private func saveAudioFile(_ audioData: [Float], sampleRate: Double) throws -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "bgm_\(Date().timeIntervalSince1970).wav"
        let fileURL = documentsPath.appendingPathComponent(fileName)

        // 创建音频格式
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

        // 创建音频文件
        let audioFile = try AVAudioFile(forWriting: fileURL, settings: format.settings)

        // 创建buffer并填充数据
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audioData.count))!
        buffer.frameLength = AVAudioFrameCount(audioData.count)

        let channelData = buffer.floatChannelData![0]
        for i in 0..<audioData.count {
            channelData[i] = audioData[i]
        }

        try audioFile.write(from: buffer)

        return fileURL
    }

    // MARK: - Haptic Feedback

    private func triggerHaptic(_ type: HapticType) async {
        let generator: UIImpactFeedbackGenerator

        switch type {
        case .light:
            generator = UIImpactFeedbackGenerator(style: .light)
        case .medium:
            generator = UIImpactFeedbackGenerator(style: .medium)
        case .heavy:
            generator = UIImpactFeedbackGenerator(style: .heavy)
        case .success:
            let notificationGenerator = UINotificationFeedbackGenerator()
            notificationGenerator.notificationOccurred(.success)
            return
        }

        generator.impactOccurred()
    }

    private enum HapticType {
        case light, medium, heavy, success
    }

    // MARK: - Helpers

    private func generateBGMName(soundType: SoundType, style: BGMStyle) -> String {
        let timeOfDay: String
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: timeOfDay = "晨间"
        case 12..<18: timeOfDay = "午后"
        case 18..<22: timeOfDay = "黄昏"
        default: timeOfDay = "夜晚"
        }

        return "\(timeOfDay)\(soundType.displayName)"
    }
}
