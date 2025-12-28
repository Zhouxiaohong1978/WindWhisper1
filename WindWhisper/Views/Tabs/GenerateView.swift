//
//  GenerateView.swift
//  WindWhisper
//
//  生成界面 - Core ML转BGM + 触觉反馈
//

import SwiftUI

struct GenerateView: View {
    @StateObject private var generator = BGMGeneratorService.shared
    @StateObject private var subscription = SubscriptionManager.shared

    @State private var selectedRecording: SoundRecording?
    @State private var selectedStyle: BGMStyle = .gentle
    @State private var isGenerating = false
    @State private var rotationAngle: Double = 0
    @State private var showRecordingPicker = false
    @State private var showResultSheet = false
    @State private var generatedBGM: GeneratedBGM?
    @State private var showSubscriptionSheet = false

    private var recordings: [SoundRecording] {
        StorageManager.shared.getRecordings()
    }

    var body: some View {
        ZStack {
            ZenTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerSection
                    .padding(.top, 20)

                Spacer()

                generationSection

                Spacer()

                recordingSelector
                    .padding(.bottom, 16)

                styleSelector
                    .padding(.bottom, 20)

                generateButton
                    .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showRecordingPicker) {
            RecordingPickerSheet(
                recordings: recordings,
                selectedRecording: $selectedRecording
            )
        }
        .sheet(isPresented: $showResultSheet) {
            if let bgm = generatedBGM {
                BGMResultSheet(bgm: bgm)
            }
        }
        .sheet(isPresented: $showSubscriptionSheet) {
            SubscriptionSheet()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("音乐生成")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(ZenTheme.textPrimary)

            Text("AI将您的声音转化为疗愈旋律")
                .font(.system(size: 14))
                .foregroundColor(ZenTheme.textSecondary)
        }
    }

    // MARK: - Generation Section

    private var generationSection: some View {
        ZStack {
            // 外圈装饰
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(ZenTheme.generateGold.opacity(0.1 + Double(i) * 0.1), lineWidth: 1)
                    .frame(width: CGFloat(200 + i * 40), height: CGFloat(200 + i * 40))
                    .rotationEffect(.degrees(rotationAngle + Double(i * 30)))
            }

            // 音符粒子
            if isGenerating {
                ForEach(0..<8, id: \.self) { i in
                    Image(systemName: "music.note")
                        .font(.system(size: 16))
                        .foregroundColor(ZenTheme.generateGold.opacity(0.6))
                        .offset(
                            x: cos(Double(i) * .pi / 4 + rotationAngle / 30) * 100,
                            y: sin(Double(i) * .pi / 4 + rotationAngle / 30) * 100
                        )
                }
            }

            // 主圆形
            Circle()
                .fill(ZenTheme.cardBackground)
                .frame(width: 180, height: 180)
                .overlay(
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [ZenTheme.generateGold, ZenTheme.generateGold.opacity(0.3), ZenTheme.generateGold],
                                center: .center
                            ),
                            lineWidth: 3
                        )
                        .rotationEffect(.degrees(rotationAngle))
                )

            // 中心内容
            VStack(spacing: 12) {
                Image(systemName: isGenerating ? "waveform" : "waveform.circle")
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [ZenTheme.generateGold, ZenTheme.generateGold.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .opacity(isGenerating ? (Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1) > 0.5 ? 1.0 : 0.7) : 1.0)
                    .animation(isGenerating ? .easeInOut(duration: 0.5).repeatForever() : .default, value: isGenerating)

                if isGenerating {
                    Text("\(Int(generator.progress * 100))%")
                        .font(.system(size: 24, weight: .light, design: .monospaced))
                        .foregroundColor(ZenTheme.generateGold)
                } else if selectedRecording != nil {
                    Text("准备就绪")
                        .font(.system(size: 16))
                        .foregroundColor(ZenTheme.freshLeaf)
                } else {
                    Text("请选择录音")
                        .font(.system(size: 16))
                        .foregroundColor(ZenTheme.textSecondary)
                }
            }
        }
        .frame(height: 300)
    }

    // MARK: - Recording Selector

    private var recordingSelector: some View {
        Button(action: { showRecordingPicker = true }) {
            HStack {
                if let recording = selectedRecording {
                    Image(systemName: recording.soundType.icon)
                        .foregroundColor(ZenTheme.generateGold)
                    Text(recording.soundType.displayName)
                        .foregroundColor(ZenTheme.textPrimary)
                    Text("·")
                        .foregroundColor(ZenTheme.textSecondary)
                    Text(formatDuration(recording.duration))
                        .foregroundColor(ZenTheme.textSecondary)
                } else {
                    Image(systemName: "waveform.badge.plus")
                        .foregroundColor(ZenTheme.textSecondary)
                    Text("选择一段录音")
                        .foregroundColor(ZenTheme.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(ZenTheme.textSecondary)
                    .font(.system(size: 14))
            }
            .font(.system(size: 15))
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(ZenTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Style Selector

    private var styleSelector: some View {
        VStack(spacing: 12) {
            Text("选择风格")
                .font(.system(size: 14))
                .foregroundColor(ZenTheme.textSecondary)

            HStack(spacing: 12) {
                ForEach(BGMStyle.allCases, id: \.self) { style in
                    styleButton(style: style)
                }
            }
        }
    }

    private func styleButton(style: BGMStyle) -> some View {
        let isSelected = selectedStyle == style
        let isLocked = !subscription.isPremium && !subscription.freeUserLimit.availableStyles.contains(style)

        return Button(action: {
            if isLocked {
                showSubscriptionSheet = true
            } else {
                withAnimation(.spring(response: 0.3)) {
                    selectedStyle = style
                }
            }
        }) {
            HStack(spacing: 4) {
                Text(style.displayName)
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                }
            }
            .font(.system(size: 14, weight: isSelected ? .medium : .regular))
            .foregroundColor(isSelected ? ZenTheme.forestDeep : (isLocked ? ZenTheme.textDisabled : ZenTheme.textSecondary))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? ZenTheme.generateGold : ZenTheme.cardBackground)
            )
        }
    }

    // MARK: - Generate Button

    private var generateButton: some View {
        Button(action: startGeneration) {
            HStack(spacing: 8) {
                if isGenerating {
                    ProgressView()
                        .tint(ZenTheme.forestDeep)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18))
                }
                Text(isGenerating ? "生成中..." : "开始生成")
                    .font(.system(size: 16, weight: .medium))
            }
            .foregroundColor(ZenTheme.forestDeep)
            .frame(width: 200, height: 50)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [ZenTheme.generateGold, ZenTheme.generateGold.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .shadow(color: ZenTheme.generateGold.opacity(0.4), radius: 15)
        }
        .disabled(selectedRecording == nil || isGenerating)
        .opacity(selectedRecording == nil ? 0.5 : 1.0)
    }

    // MARK: - Actions

    private func startGeneration() {
        guard let recording = selectedRecording else { return }

        isGenerating = true

        // 旋转动画
        withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
            rotationAngle = 360
        }

        Task {
            do {
                let bgm = try await generator.generateBGM(
                    from: recording,
                    style: selectedStyle
                )

                // 保存BGM
                StorageManager.shared.saveBGM(bgm)

                // 更新每日任务
                updateDailyTask()

                generatedBGM = bgm

                withAnimation {
                    isGenerating = false
                    rotationAngle = 0
                }

                showResultSheet = true

            } catch {
                print("生成失败: \(error)")
                withAnimation {
                    isGenerating = false
                    rotationAngle = 0
                }
            }
        }
    }

    private func updateDailyTask() {
        var tasks = StorageManager.shared.getDailyTasks()
        if let index = tasks.firstIndex(where: { $0.title == "音乐创作者" && !$0.isCompleted }) {
            tasks[index].currentCount += 1
            if tasks[index].currentCount >= tasks[index].targetCount {
                tasks[index].isCompleted = true
            }
            StorageManager.shared.updateTask(tasks[index])
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        return "\(seconds)秒"
    }
}

// MARK: - Recording Picker Sheet

struct RecordingPickerSheet: View {
    let recordings: [SoundRecording]
    @Binding var selectedRecording: SoundRecording?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                ZenTheme.backgroundGradient
                    .ignoresSafeArea()

                if recordings.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "waveform.slash")
                            .font(.system(size: 50))
                            .foregroundColor(ZenTheme.textSecondary)
                        Text("暂无录音")
                            .foregroundColor(ZenTheme.textSecondary)
                        Text("请先去采集页面录制声音")
                            .font(.system(size: 14))
                            .foregroundColor(ZenTheme.textDisabled)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(recordings) { recording in
                                RecordingRow(recording: recording, isSelected: selectedRecording?.id == recording.id)
                                    .onTapGesture {
                                        selectedRecording = recording
                                        dismiss()
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("选择录音")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("取消") { dismiss() }
                        .foregroundColor(ZenTheme.textSecondary)
                }
            }
        }
    }
}

struct RecordingRow: View {
    let recording: SoundRecording
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(isSelected ? ZenTheme.generateGold.opacity(0.2) : ZenTheme.cardBackground)
                    .frame(width: 50, height: 50)

                Image(systemName: recording.soundType.icon)
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? ZenTheme.generateGold : ZenTheme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(recording.soundType.displayName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(ZenTheme.textPrimary)

                HStack(spacing: 8) {
                    Text(recording.locationName ?? "户外")
                    Text("·")
                    Text(formatDate(recording.timestamp))
                }
                .font(.system(size: 13))
                .foregroundColor(ZenTheme.textSecondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(ZenTheme.generateGold)
            }
        }
        .padding(16)
        .background(ZenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? ZenTheme.generateGold : Color.clear, lineWidth: 2)
        )
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - BGM Result Sheet

struct BGMResultSheet: View {
    let bgm: GeneratedBGM
    @StateObject private var player = AudioPlayerService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                ZenTheme.backgroundGradient
                    .ignoresSafeArea()

                VStack(spacing: 32) {
                    // 成功动画
                    ZStack {
                        Circle()
                            .fill(ZenTheme.generateGold.opacity(0.2))
                            .frame(width: 120, height: 120)

                        Image(systemName: "music.note.list")
                            .font(.system(size: 50))
                            .foregroundColor(ZenTheme.generateGold)
                    }

                    VStack(spacing: 8) {
                        Text("生成完成!")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(ZenTheme.textPrimary)

                        Text(bgm.name)
                            .font(.system(size: 18))
                            .foregroundColor(ZenTheme.generateGold)
                    }

                    // 信息卡片
                    VStack(spacing: 16) {
                        infoRow(icon: "paintpalette", title: "风格", value: bgm.style.displayName)
                        infoRow(icon: "clock", title: "时长", value: formatDuration(bgm.duration))
                    }
                    .padding(20)
                    .background(ZenTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)

                    Spacer()

                    // 操作按钮
                    VStack(spacing: 12) {
                        Button(action: {
                            player.play(bgm: bgm)
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("立即播放")
                            }
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(ZenTheme.forestDeep)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(ZenTheme.generateGold)
                            .clipShape(Capsule())
                        }

                        Button(action: {
                            ShareManager.shared.shareBGM(bgm)
                        }) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("分享")
                            }
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

    private func infoRow(icon: String, title: String, value: String) -> some View {
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

// MARK: - Subscription Sheet

struct SubscriptionSheet: View {
    @StateObject private var subscription = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                ZenTheme.backgroundGradient
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    // 头部
                    VStack(spacing: 16) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 60))
                            .foregroundColor(ZenTheme.generateGold)

                        Text("解锁全部功能")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(ZenTheme.textPrimary)
                    }
                    .padding(.top, 40)

                    // 功能列表
                    VStack(alignment: .leading, spacing: 16) {
                        featureRow(icon: "infinity", text: "无限录音和生成")
                        featureRow(icon: "paintpalette.fill", text: "全部音乐风格")
                        featureRow(icon: "arrow.up.circle.fill", text: "高品质导出")
                        featureRow(icon: "xmark.circle.fill", text: "无广告体验")
                    }
                    .padding(24)
                    .background(ZenTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)

                    Spacer()

                    // 订阅按钮
                    VStack(spacing: 16) {
                        Button(action: {
                            Task {
                                if let product = subscription.getProduct(for: SubscriptionManager.monthlySubscriptionID) {
                                    _ = try? await subscription.purchase(product)
                                }
                            }
                        }) {
                            VStack(spacing: 4) {
                                Text("订阅 Premium")
                                    .font(.system(size: 16, weight: .medium))
                                Text("$4.99/月")
                                    .font(.system(size: 14))
                                    .opacity(0.8)
                            }
                            .foregroundColor(ZenTheme.forestDeep)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(ZenTheme.generateGold)
                            .clipShape(Capsule())
                        }

                        Button(action: {
                            Task {
                                await subscription.restorePurchases()
                            }
                        }) {
                            Text("恢复购买")
                                .font(.system(size: 14))
                                .foregroundColor(ZenTheme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
                }
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

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(ZenTheme.generateGold)
                .frame(width: 24)
            Text(text)
                .foregroundColor(ZenTheme.textPrimary)
        }
        .font(.system(size: 15))
    }
}

#Preview {
    GenerateView()
}
