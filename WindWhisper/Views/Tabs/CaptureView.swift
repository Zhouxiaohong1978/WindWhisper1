//
//  CaptureView.swift
//  WindWhisper
//
//  采集界面 - 麦克风+LBS一键捕风声/鸟鸣
//

import CoreLocation
import SwiftUI

struct CaptureView: View {
    @StateObject private var audioCapture = AudioCaptureService.shared
    @StateObject private var classifier = SoundClassifierService.shared
    @StateObject private var location = LocationService.shared

    @State private var isRecording = false
    @State private var recordingProgress: CGFloat = 0.0
    @State private var pulseScale: CGFloat = 1.0
    @State private var showPermissionAlert = false
    @State private var currentRecordingURL: URL?
    @State private var showResultSheet = false
    @State private var lastRecording: SoundRecording?

    private let maxRecordingDuration: TimeInterval = 30

    var body: some View {
        ZStack {
            ZenTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerSection
                    .padding(.top, 20)

                Spacer()

                recordingSection

                Spacer()

                hintSection
                    .padding(.bottom, 40)
            }
        }
        .onAppear {
            location.requestAuthorization()
            Task {
                await audioCapture.checkPermission()
            }
        }
        .alert("需要麦克风权限", isPresented: $showPermissionAlert) {
            Button("去设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("请在设置中允许WindWhisper访问麦克风以采集自然声音")
        }
        .sheet(isPresented: $showResultSheet) {
            if let recording = lastRecording {
                RecordingResultSheet(recording: recording)
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("声音采集")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(ZenTheme.textPrimary)

            HStack(spacing: 4) {
                Image(systemName: "location.fill")
                    .font(.system(size: 12))
                Text("当前位置：\(location.locationName)")
                    .font(.system(size: 14))
            }
            .foregroundColor(ZenTheme.textSecondary)
        }
    }

    // MARK: - Recording Section

    private var recordingSection: some View {
        VStack(spacing: 40) {
            soundWaveView

            ZStack {
                // 脉冲动画
                if isRecording {
                    Circle()
                        .stroke(ZenTheme.captureBlue.opacity(0.3), lineWidth: 2)
                        .frame(width: 160, height: 160)
                        .scaleEffect(pulseScale)

                    Circle()
                        .stroke(ZenTheme.captureBlue.opacity(0.2), lineWidth: 1)
                        .frame(width: 180, height: 180)
                        .scaleEffect(pulseScale * 1.1)
                }

                // 进度环
                Circle()
                    .stroke(ZenTheme.forestDeep, lineWidth: 6)
                    .frame(width: 140, height: 140)

                Circle()
                    .trim(from: 0, to: recordingProgress)
                    .stroke(ZenTheme.captureBlue, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(-90))

                // 主按钮
                Circle()
                    .fill(
                        isRecording ?
                            LinearGradient(colors: [ZenTheme.captureBlue, ZenTheme.captureBlue.opacity(0.7)],
                                         startPoint: .top, endPoint: .bottom) :
                            ZenTheme.leafGradient
                    )
                    .frame(width: 120, height: 120)
                    .shadow(color: (isRecording ? ZenTheme.captureBlue : ZenTheme.freshLeaf).opacity(0.5), radius: 20)

                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.white)
            }
            .onTapGesture {
                toggleRecording()
            }

            VStack(spacing: 8) {
                Text(isRecording ? "正在聆听..." : "轻触开始采集")
                    .font(.system(size: 16))
                    .foregroundColor(isRecording ? ZenTheme.captureBlue : ZenTheme.textSecondary)

                if isRecording {
                    HStack(spacing: 4) {
                        Text("识别中：")
                            .foregroundColor(ZenTheme.textSecondary)
                        Text(classifier.currentClassification.displayName)
                            .foregroundColor(ZenTheme.captureBlue)
                            .fontWeight(.medium)

                        if classifier.confidence > 0.5 {
                            Image(systemName: classifier.currentClassification.icon)
                                .foregroundColor(ZenTheme.captureBlue)
                        }
                    }
                    .font(.system(size: 14))

                    Text(formatTime(audioCapture.recordingDuration))
                        .font(.system(size: 24, weight: .light, design: .monospaced))
                        .foregroundColor(ZenTheme.textPrimary)
                }
            }
        }
    }

    private var soundWaveView: some View {
        HStack(spacing: 4) {
            ForEach(0..<9, id: \.self) { index in
                Capsule()
                    .fill(ZenTheme.captureBlue.opacity(isRecording ? 0.8 : 0.3))
                    .frame(width: 4, height: waveHeight(for: index))
                    .animation(
                        isRecording ?
                            .easeInOut(duration: 0.15 + Double(index) * 0.02)
                            .repeatForever(autoreverses: true) : .default,
                        value: isRecording
                    )
            }
        }
        .frame(height: 60)
    }

    private func waveHeight(for index: Int) -> CGFloat {
        if isRecording {
            let baseHeight: CGFloat = 15
            let audioMultiplier = CGFloat(audioCapture.audioLevel) * 50
            let pattern: [CGFloat] = [0.5, 0.8, 0.6, 1.0, 0.7, 1.0, 0.6, 0.8, 0.5]
            return baseHeight + audioMultiplier * pattern[index]
        } else {
            return 10
        }
    }

    // MARK: - Hint Section

    private var hintSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                quickTag(icon: "wind", text: "风声")
                quickTag(icon: "bird.fill", text: "鸟鸣")
                quickTag(icon: "drop.fill", text: "雨声")
                quickTag(icon: "leaf.fill", text: "树叶")
            }

            Text("走出户外，发现自然之声")
                .font(.system(size: 13))
                .foregroundColor(ZenTheme.textSecondary.opacity(0.6))
        }
    }

    private func quickTag(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(text)
                .font(.system(size: 12))
        }
        .foregroundColor(ZenTheme.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(ZenTheme.cardBackground)
        .clipShape(Capsule())
    }

    // MARK: - Actions

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard audioCapture.permissionGranted else {
            showPermissionAlert = true
            return
        }

        Task {
            do {
                currentRecordingURL = try await audioCapture.startRecording()

                // 设置音频数据回调
                audioCapture.onAudioBuffer = { samples in
                    Task { @MainActor in
                        classifier.processAudioSamples(samples)
                    }
                }

                withAnimation(.spring(response: 0.3)) {
                    isRecording = true
                }

                startAnimations()

            } catch {
                print("录音失败: \(error)")
            }
        }
    }

    private func stopRecording() {
        guard var recording = audioCapture.stopRecording() else { return }

        // 更新录音信息
        recording = SoundRecording(
            id: recording.id,
            soundType: classifier.currentClassification,
            duration: recording.duration,
            timestamp: recording.timestamp,
            locationName: location.locationName,
            latitude: location.currentLocation?.coordinate.latitude,
            longitude: location.currentLocation?.coordinate.longitude,
            audioFileURL: recording.audioFileURL,
            confidence: classifier.confidence
        )

        // 保存录音
        StorageManager.shared.saveRecording(recording)

        // 更新每日任务
        updateDailyTask(for: recording)

        lastRecording = recording
        classifier.reset()

        withAnimation(.spring(response: 0.3)) {
            isRecording = false
            recordingProgress = 0
            pulseScale = 1.0
        }

        // 显示结果
        showResultSheet = true
    }

    private func startAnimations() {
        // 脉冲动画
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            pulseScale = 1.2
        }

        // 进度动画
        withAnimation(.linear(duration: maxRecordingDuration)) {
            recordingProgress = 1.0
        }

        // 最大录音时间自动停止
        DispatchQueue.main.asyncAfter(deadline: .now() + maxRecordingDuration) {
            if isRecording {
                stopRecording()
            }
        }
    }

    private func updateDailyTask(for recording: SoundRecording) {
        var tasks = StorageManager.shared.getDailyTasks()
        if let index = tasks.firstIndex(where: { $0.title == "声音探索者" && !$0.isCompleted }) {
            tasks[index].currentCount += 1
            if tasks[index].currentCount >= tasks[index].targetCount {
                tasks[index].isCompleted = true
            }
            StorageManager.shared.updateTask(tasks[index])
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Recording Result Sheet

struct RecordingResultSheet: View {
    let recording: SoundRecording
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                ZenTheme.backgroundGradient
                    .ignoresSafeArea()

                VStack(spacing: 32) {
                    // 成功图标
                    ZStack {
                        Circle()
                            .fill(ZenTheme.freshLeaf.opacity(0.2))
                            .frame(width: 120, height: 120)

                        Image(systemName: recording.soundType.icon)
                            .font(.system(size: 50))
                            .foregroundColor(ZenTheme.freshLeaf)
                    }

                    VStack(spacing: 8) {
                        Text("采集成功!")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(ZenTheme.textPrimary)

                        Text("识别为 \(recording.soundType.displayName)")
                            .font(.system(size: 16))
                            .foregroundColor(ZenTheme.textSecondary)
                    }

                    // 详情卡片
                    VStack(spacing: 16) {
                        detailRow(icon: "clock", title: "时长", value: formatDuration(recording.duration))
                        detailRow(icon: "location", title: "位置", value: recording.locationName ?? "户外")
                        detailRow(icon: "waveform", title: "置信度", value: "\(Int(recording.confidence * 100))%")
                    }
                    .padding(20)
                    .background(ZenTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)

                    Spacer()

                    // 操作按钮
                    VStack(spacing: 12) {
                        Button(action: {
                            dismiss()
                            // 导航到生成页面
                        }) {
                            HStack {
                                Image(systemName: "waveform.circle.fill")
                                Text("生成疗愈音乐")
                            }
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(ZenTheme.forestDeep)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(ZenTheme.freshLeaf)
                            .clipShape(Capsule())
                        }

                        Button(action: { dismiss() }) {
                            Text("继续采集")
                                .font(.system(size: 16))
                                .foregroundColor(ZenTheme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
                }
                .padding(.top, 40)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(ZenTheme.textSecondary)
                    }
                }
            }
        }
    }

    private func detailRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(ZenTheme.textSecondary)
                .frame(width: 24)
            Text(title)
                .foregroundColor(ZenTheme.textSecondary)
            Spacer()
            Text(value)
                .foregroundColor(ZenTheme.textPrimary)
        }
        .font(.system(size: 14))
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    CaptureView()
}
