//
//  HealingView.swift
//  WindWhisper
//
//  疗愈界面 - 声景花园 + 每日挑战 + 播放器
//

import SwiftUI

struct HealingView: View {
    @StateObject private var player = AudioPlayerService.shared
    @StateObject private var notification = NotificationManager.shared

    @State private var breatheScale: CGFloat = 1.0
    @State private var showGardenSheet = false
    @State private var listeningTime: TimeInterval = 0
    @State private var listeningTimer: Timer?

    private var recentBGMs: [GeneratedBGM] {
        StorageManager.shared.getRecentBGMs()
    }

    private var dailyTasks: [DailyTask] {
        StorageManager.shared.getDailyTasks()
    }

    private var userProgress: UserProgress {
        StorageManager.shared.getUserProgress()
    }

    var body: some View {
        ZStack {
            ZenTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    headerSection
                        .padding(.top, 20)

                    // 花园预览卡片
                    gardenPreviewCard

                    // 当前播放
                    if player.currentBGM != nil {
                        nowPlayingCard
                    }

                    // 最近生成的BGM
                    if !recentBGMs.isEmpty {
                        recentBGMsSection
                    }

                    // 每日挑战
                    dailyChallengeSection

                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
            }
        }
        .onAppear {
            setupListeningTimer()
            Task {
                await notification.scheduleDailyTaskReminder()
            }
        }
        .onDisappear {
            listeningTimer?.invalidate()
        }
        .sheet(isPresented: $showGardenSheet) {
            GardenFullView()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("疗愈空间")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(ZenTheme.textPrimary)

            Text("放松身心，沉浸自然")
                .font(.system(size: 14))
                .foregroundColor(ZenTheme.textSecondary)
        }
    }

    // MARK: - Garden Preview

    private var gardenPreviewCard: some View {
        Button(action: { showGardenSheet = true }) {
            VStack(spacing: 16) {
                // Canvas预览
                GardenCanvasView(level: userProgress.gardenLevel, leaves: userProgress.totalLeaves)
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                // 统计信息
                HStack(spacing: 20) {
                    gardenStat(icon: "leaf.fill", value: "\(userProgress.totalLeaves)", label: "叶子")
                    gardenStat(icon: "tree.fill", value: "Lv.\(userProgress.gardenLevel)", label: "等级")
                    gardenStat(icon: "waveform", value: "\(userProgress.totalRecordings)", label: "录音")

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundColor(ZenTheme.textSecondary)
                }
            }
            .padding(16)
            .background(ZenTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func gardenStat(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(ZenTheme.freshLeaf)
                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(ZenTheme.textPrimary)
            }
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(ZenTheme.textSecondary)
        }
    }

    // MARK: - Now Playing Card

    private var nowPlayingCard: some View {
        VStack(spacing: 20) {
            // 可视化区域
            ZStack {
                Circle()
                    .fill(ZenTheme.healingPurple.opacity(0.1))
                    .frame(width: 140, height: 140)
                    .scaleEffect(breatheScale)

                Circle()
                    .fill(ZenTheme.healingPurple.opacity(0.2))
                    .frame(width: 100, height: 100)
                    .scaleEffect(breatheScale * 0.9)

                Image(systemName: "leaf.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [ZenTheme.healingPurple, ZenTheme.mintGlow],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .frame(height: 160)
            .onAppear {
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                    breatheScale = 1.15
                }
            }

            // 曲目信息
            if let bgm = player.currentBGM {
                VStack(spacing: 4) {
                    Text(bgm.name)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(ZenTheme.textPrimary)

                    Text("\(bgm.style.displayName) · \(formatDuration(bgm.duration))")
                        .font(.system(size: 13))
                        .foregroundColor(ZenTheme.textSecondary)
                }
            }

            // 进度条
            progressBar

            // 控制按钮
            controlButtons
        }
        .padding(24)
        .background(ZenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var progressBar: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(ZenTheme.forestDeep)
                        .frame(height: 4)

                    Capsule()
                        .fill(ZenTheme.healingPurple)
                        .frame(width: geometry.size.width * (player.duration > 0 ? player.currentTime / player.duration : 0), height: 4)
                }
            }
            .frame(height: 4)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let progress = value.location.x / UIScreen.main.bounds.width
                        let newTime = player.duration * progress
                        player.seek(to: max(0, min(newTime, player.duration)))
                    }
            )

            HStack {
                Text(formatTime(player.currentTime))
                Spacer()
                Text(formatTime(player.duration))
            }
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(ZenTheme.textSecondary)
        }
    }

    private var controlButtons: some View {
        HStack(spacing: 40) {
            Button(action: { player.skipBackward() }) {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 24))
                    .foregroundColor(ZenTheme.textSecondary)
            }

            Button(action: { player.togglePlayPause() }) {
                Circle()
                    .fill(ZenTheme.healingPurple)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .offset(x: player.isPlaying ? 0 : 2)
                    )
                    .shadow(color: ZenTheme.healingPurple.opacity(0.5), radius: 15)
            }

            Button(action: { player.skipForward() }) {
                Image(systemName: "goforward.15")
                    .font(.system(size: 24))
                    .foregroundColor(ZenTheme.textSecondary)
            }
        }
    }

    // MARK: - Recent BGMs

    private var recentBGMsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("最近生成")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(ZenTheme.textPrimary)

                Spacer()

                Text("\(recentBGMs.count) 首")
                    .font(.system(size: 14))
                    .foregroundColor(ZenTheme.textSecondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recentBGMs) { bgm in
                        bgmCard(bgm: bgm)
                    }
                }
            }
        }
    }

    private func bgmCard(bgm: GeneratedBGM) -> some View {
        Button(action: { player.play(bgm: bgm) }) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(styleColor(for: bgm.style).opacity(0.2))
                        .frame(width: 60, height: 60)

                    Image(systemName: "music.note")
                        .font(.system(size: 24))
                        .foregroundColor(styleColor(for: bgm.style))
                }

                VStack(spacing: 2) {
                    Text(bgm.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(ZenTheme.textPrimary)
                        .lineLimit(1)

                    Text(bgm.style.displayName)
                        .font(.system(size: 11))
                        .foregroundColor(ZenTheme.textSecondary)
                }
            }
            .frame(width: 100)
            .padding(.vertical, 16)
            .background(ZenTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button(action: { player.play(bgm: bgm) }) {
                Label("播放", systemImage: "play.fill")
            }
            Button(action: { ShareManager.shared.shareBGM(bgm) }) {
                Label("分享", systemImage: "square.and.arrow.up")
            }
            Divider()
            Button(role: .destructive, action: { deleteBGM(bgm) }) {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func deleteBGM(_ bgm: GeneratedBGM) {
        if player.currentBGM?.id == bgm.id {
            player.stop()
        }
        StorageManager.shared.deleteBGM(bgm.id)
    }

    private func styleColor(for style: BGMStyle) -> Color {
        switch style {
        case .gentle: return ZenTheme.mintGlow
        case .meditation: return ZenTheme.healingPurple
        case .nature: return ZenTheme.freshLeaf
        case .deepSleep: return ZenTheme.captureBlue
        }
    }

    // MARK: - Daily Challenge

    private var dailyChallengeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("每日挑战")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(ZenTheme.textPrimary)

            ForEach(dailyTasks) { task in
                dailyTaskRow(task: task)
            }
        }
    }

    private func dailyTaskRow(task: DailyTask) -> some View {
        HStack(spacing: 16) {
            // 图标
            ZStack {
                Circle()
                    .fill(task.isCompleted ? ZenTheme.freshLeaf.opacity(0.2) : ZenTheme.forestDeep)
                    .frame(width: 50, height: 50)

                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "target")
                    .font(.system(size: 24))
                    .foregroundColor(task.isCompleted ? ZenTheme.freshLeaf : ZenTheme.textSecondary)
            }

            // 信息
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(task.isCompleted ? ZenTheme.textSecondary : ZenTheme.textPrimary)
                    .strikethrough(task.isCompleted)

                Text("进度 \(task.currentCount)/\(task.targetCount) · 奖励 +\(task.rewardLeaves) 叶子")
                    .font(.system(size: 13))
                    .foregroundColor(ZenTheme.textSecondary)

                // 进度条
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(ZenTheme.forestDeep)
                            .frame(height: 4)

                        Capsule()
                            .fill(task.isCompleted ? ZenTheme.freshLeaf : ZenTheme.healingPurple)
                            .frame(width: geometry.size.width * CGFloat(task.progress), height: 4)
                    }
                }
                .frame(height: 4)
            }

            Spacer()
        }
        .padding(16)
        .background(ZenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Helpers

    private func setupListeningTimer() {
        listeningTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            if player.isPlaying {
                listeningTime += 1
                updateListeningTask()
            }
        }
    }

    private func updateListeningTask() {
        var tasks = StorageManager.shared.getDailyTasks()
        if let index = tasks.firstIndex(where: { $0.title == "冥想时刻" && !$0.isCompleted }) {
            tasks[index].currentCount = Int(listeningTime)
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

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Garden Full View

struct GardenFullView: View {
    @Environment(\.dismiss) private var dismiss

    private var userProgress: UserProgress {
        StorageManager.shared.getUserProgress()
    }

    var body: some View {
        NavigationView {
            ZStack {
                ZenTheme.backgroundGradient
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    // 大花园视图
                    GardenCanvasView(level: userProgress.gardenLevel, leaves: userProgress.totalLeaves)
                        .frame(height: 350)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .padding(.horizontal)

                    // 统计卡片
                    GardenStatsView(progress: userProgress)
                        .padding(.horizontal)

                    // 等级进度
                    levelProgressCard

                    Spacer()

                    // 分享按钮
                    Button(action: shareGarden) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("分享我的花园")
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(ZenTheme.forestDeep)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(ZenTheme.freshLeaf)
                        .clipShape(Capsule())
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
                }
                .padding(.top, 20)
            }
            .navigationTitle("我的声景花园")
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

    private var levelProgressCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("等级 \(userProgress.gardenLevel)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(ZenTheme.textPrimary)

                Spacer()

                Text("下一级需要 \(leavesForNextLevel - userProgress.totalLeaves) 叶子")
                    .font(.system(size: 13))
                    .foregroundColor(ZenTheme.textSecondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(ZenTheme.forestDeep)
                        .frame(height: 8)

                    Capsule()
                        .fill(ZenTheme.freshLeaf)
                        .frame(width: geometry.size.width * levelProgress, height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding(20)
        .background(ZenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var leavesForNextLevel: Int {
        userProgress.gardenLevel * 100
    }

    private var levelProgress: CGFloat {
        let currentLevelLeaves = (userProgress.gardenLevel - 1) * 100
        let progress = CGFloat(userProgress.totalLeaves - currentLevelLeaves) / 100.0
        return min(1.0, max(0.0, progress))
    }

    private func shareGarden() {
        ShareManager.shared.shareAchievement(
            title: "Lv.\(userProgress.gardenLevel) 声景花园",
            description: "我已经收集了\(userProgress.totalLeaves)片叶子，录制了\(userProgress.totalRecordings)段自然声音！"
        )
    }
}

#Preview {
    HealingView()
}
