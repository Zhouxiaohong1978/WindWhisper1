//
//  AudioPlayerService.swift
//  WindWhisper
//
//  音频播放服务 - 播放生成的BGM
//

import AVFoundation
import Combine
import MediaPlayer

@MainActor
final class AudioPlayerService: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var currentBGM: GeneratedBGM?

    // MARK: - Private Properties

    private var audioPlayer: AVAudioPlayer?
    private var displayLink: CADisplayLink?

    // MARK: - Singleton

    static let shared = AudioPlayerService()

    private init() {
        setupAudioSession()
        setupRemoteTransportControls()
    }

    // MARK: - Audio Session

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("音频会话设置失败: \(error)")
        }
    }

    // MARK: - Playback Control

    func play(bgm: GeneratedBGM) {
        guard let audioPath = bgm.audioFileURL else {
            print("没有音频文件")
            return
        }

        let audioURL = URL(fileURLWithPath: audioPath)

        guard FileManager.default.fileExists(atPath: audioPath) else {
            print("音频文件不存在")
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()

            currentBGM = bgm
            duration = audioPlayer?.duration ?? 0
            isPlaying = true

            startDisplayLink()
            updateNowPlayingInfo()
        } catch {
            print("播放失败: \(error)")
        }
    }

    func togglePlayPause() {
        guard let player = audioPlayer else { return }

        if player.isPlaying {
            player.pause()
            isPlaying = false
            stopDisplayLink()
        } else {
            player.play()
            isPlaying = true
            startDisplayLink()
        }

        updateNowPlayingInfo()
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopDisplayLink()
        updateNowPlayingInfo()
    }

    func resume() {
        audioPlayer?.play()
        isPlaying = true
        startDisplayLink()
        updateNowPlayingInfo()
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentTime = 0
        currentBGM = nil
        stopDisplayLink()
        clearNowPlayingInfo()
    }

    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        currentTime = time
        updateNowPlayingInfo()
    }

    func skipForward(seconds: TimeInterval = 15) {
        guard let player = audioPlayer else { return }
        let newTime = min(player.currentTime + seconds, player.duration)
        seek(to: newTime)
    }

    func skipBackward(seconds: TimeInterval = 15) {
        guard let player = audioPlayer else { return }
        let newTime = max(player.currentTime - seconds, 0)
        seek(to: newTime)
    }

    // MARK: - Display Link

    private func startDisplayLink() {
        stopDisplayLink()
        displayLink = CADisplayLink(target: self, selector: #selector(updatePlaybackTime))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func updatePlaybackTime() {
        guard let player = audioPlayer else { return }

        currentTime = player.currentTime

        // 检查是否播放完成
        if !player.isPlaying && currentTime >= duration - 0.1 {
            handlePlaybackCompletion()
        }
    }

    private func handlePlaybackCompletion() {
        isPlaying = false
        currentTime = 0
        stopDisplayLink()

        // 可以在这里添加自动播放下一首的逻辑
    }

    // MARK: - Remote Controls

    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }

        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            self?.skipForward()
            return .success
        }

        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skipBackward()
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let event = event as? MPChangePlaybackPositionCommandEvent {
                self?.seek(to: event.positionTime)
            }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let bgm = currentBGM else { return }

        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: bgm.name,
            MPMediaItemPropertyArtist: "WindWhisper",
            MPMediaItemPropertyAlbumTitle: bgm.style.displayName,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]

        // 可以添加封面图片
        // if let image = UIImage(named: "albumArt") {
        //     nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        // }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
