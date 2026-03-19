import Foundation
import AppKit
import ScreenCaptureKit
import AVFoundation
import Combine

@available(macOS 13.0, *)
class ScreenRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var recordings: [ClipboardItem] = []

    private let settings = SettingsManager.shared

    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var micInput: AVAssetWriterInput?
    private var audioEngine: AVAudioEngine?
    private var micFile: AVAudioFile?

    private var durationTimer: Timer?
    private var recordingStartTime: Date?

    private var sessionStarted = false
    private var videoStarted = false
    private var audioStarted = false
    private var isFinishing = false

    private var tempMicURL: URL?

    var recordingsDirectory: URL {
        let dir = settings.storageDirectory.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    override init() {
        super.init()
        loadExistingRecordings()
    }

    // MARK: - Start Recording

    func startRecording() {
        guard !isRecording else { return }
        NSLog("[ScreenRecorder] startRecording()")

        sessionStarted = false
        videoStarted = false
        audioStarted = false
        isFinishing = false

        Task {
            do {
                // Get shareable content
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else {
                    NSLog("[ScreenRecorder] No display found")
                    return
                }

                // Configure stream
                let config = SCStreamConfiguration()
                config.width = Int(display.width) * 2
                config.height = Int(display.height) * 2
                config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                config.showsCursor = true
                config.pixelFormat = kCVPixelFormatType_32BGRA

                // System audio
                config.capturesAudio = true
                config.sampleRate = 48000
                config.channelCount = 2

                let filter = SCContentFilter(display: display, excludingWindows: [])

                // Setup AVAssetWriter
                let timestamp = Int(Date().timeIntervalSince1970)
                let outputURL = recordingsDirectory.appendingPathComponent("Recording_\(timestamp).mp4")

                let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

                // Video input
                let videoSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: config.width,
                    AVVideoHeightKey: config.height,
                    AVVideoCompressionPropertiesKey: [
                        AVVideoAverageBitRateKey: 6_000_000,
                        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                    ] as [String: Any],
                ]
                let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
                vInput.expectsMediaDataInRealTime = true
                writer.add(vInput)
                self.videoInput = vInput

                // System audio input
                let audioSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 128_000,
                ]
                let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                aInput.expectsMediaDataInRealTime = true
                writer.add(aInput)
                self.audioInput = aInput

                self.assetWriter = writer

                writer.startWriting()

                // Start microphone capture to a separate temp file
                startMicrophoneCapture()

                // Create and start SCStream
                let streamOutput = StreamOutput(recorder: self)
                let newStream = SCStream(filter: filter, configuration: config, delegate: streamOutput)
                try newStream.addStreamOutput(streamOutput, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))
                try newStream.addStreamOutput(streamOutput, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
                try await newStream.startCapture()
                self.stream = newStream

                await MainActor.run {
                    self.isRecording = true
                    self.recordingStartTime = Date()
                    self.recordingDuration = 0
                    self.durationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                        guard let self, let start = self.recordingStartTime else { return }
                        self.recordingDuration = Date().timeIntervalSince(start)
                    }
                }

                NSLog("[ScreenRecorder] Recording started")
            } catch {
                NSLog("[ScreenRecorder] Failed to start: %@", error.localizedDescription)
            }
        }
    }

    // MARK: - Stop Recording

    func stopRecording() {
        guard isRecording, !isFinishing else { return }
        isFinishing = true
        NSLog("[ScreenRecorder] stopRecording()")

        Task {
            // Stop SCStream
            if let stream = self.stream {
                try? await stream.stopCapture()
            }
            self.stream = nil

            // Stop microphone
            stopMicrophoneCapture()

            // Finish writing
            guard let writer = self.assetWriter else { return }
            let outputURL = writer.outputURL

            self.videoInput?.markAsFinished()
            self.audioInput?.markAsFinished()

            await writer.finishWriting()

            // Merge mic audio if we have it
            var finalURL = outputURL
            if let micURL = self.tempMicURL, FileManager.default.fileExists(atPath: micURL.path) {
                let mergedURL = outputURL.deletingLastPathComponent()
                    .appendingPathComponent(outputURL.deletingPathExtension().lastPathComponent + "_merged.mp4")
                let merged = await self.mergeAudioTracks(videoURL: outputURL, micURL: micURL, outputURL: mergedURL)
                if merged {
                    try? FileManager.default.removeItem(at: outputURL)
                    try? FileManager.default.removeItem(at: micURL)
                    finalURL = mergedURL
                } else {
                    try? FileManager.default.removeItem(at: micURL)
                }
            }

            self.assetWriter = nil
            self.videoInput = nil
            self.audioInput = nil
            self.micInput = nil

            let savedURL = finalURL
            await MainActor.run {
                self.isRecording = false
                self.durationTimer?.invalidate()
                self.durationTimer = nil
                self.recordingDuration = 0
                self.isFinishing = false

                // Add to recordings list
                let icon = NSWorkspace.shared.icon(forFile: savedURL.path)
                icon.size = NSSize(width: 40, height: 40)
                let item = ClipboardItem(
                    type: .file,
                    name: savedURL.lastPathComponent,
                    url: savedURL,
                    text: nil,
                    dateAdded: Date(),
                    icon: icon
                )
                self.recordings.insert(item, at: 0)
                NSLog("[ScreenRecorder] Recording saved: %@", savedURL.lastPathComponent)
            }
        }
    }

    // MARK: - Microphone Capture

    private func startMicrophoneCapture() {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            NSLog("[ScreenRecorder] No microphone available")
            return
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        let micURL = NSTemporaryDirectory().appending("mic_\(timestamp).caf")
        let micFileURL = URL(fileURLWithPath: micURL)
        self.tempMicURL = micFileURL

        do {
            let audioFile = try AVAudioFile(forWriting: micFileURL, settings: format.settings)
            self.micFile = audioFile

            inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                try? self?.micFile?.write(from: buffer)
            }

            try engine.start()
            self.audioEngine = engine
            NSLog("[ScreenRecorder] Microphone capture started")
        } catch {
            NSLog("[ScreenRecorder] Mic error: %@", error.localizedDescription)
        }
    }

    private func stopMicrophoneCapture() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        micFile = nil
    }

    // MARK: - Merge Audio Tracks

    private func mergeAudioTracks(videoURL: URL, micURL: URL, outputURL: URL) async -> Bool {
        let videoAsset = AVURLAsset(url: videoURL)
        let micAsset = AVURLAsset(url: micURL)

        let composition = AVMutableComposition()

        do {
            // Video track
            if let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first {
                let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
                let duration = try await videoAsset.load(.duration)
                try compVideoTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: videoTrack, at: .zero)
            }

            // System audio track
            let duration = try await videoAsset.load(.duration)
            if let audioTrack = try await videoAsset.loadTracks(withMediaType: .audio).first {
                let compAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                try compAudioTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: audioTrack, at: .zero)
            }

            // Mic audio track
            if let micTrack = try await micAsset.loadTracks(withMediaType: .audio).first {
                let micDuration = try await micAsset.load(.duration)
                let insertDuration = CMTimeMinimum(micDuration, duration)
                let compMicTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                try compMicTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: insertDuration), of: micTrack, at: .zero)
            }

            // Export
            guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
                return false
            }
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mp4

            await exportSession.export()
            return exportSession.status == .completed
        } catch {
            NSLog("[ScreenRecorder] Merge error: %@", error.localizedDescription)
            return false
        }
    }

    // MARK: - Sample Buffer Handling

    fileprivate func handleVideoSample(_ sampleBuffer: CMSampleBuffer) {
        guard let writer = assetWriter,
              let input = videoInput,
              !isFinishing else { return }

        if !sessionStarted {
            let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startSession(atSourceTime: time)
            sessionStarted = true
        }

        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }

    fileprivate func handleAudioSample(_ sampleBuffer: CMSampleBuffer) {
        guard let input = audioInput,
              sessionStarted,
              !isFinishing else { return }

        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }

    // MARK: - Recordings Management

    private func loadExistingRecordings() {
        let dir = recordingsDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]
        ) else { return }

        let videoExtensions: Set<String> = ["mp4", "mov"]
        let sorted = contents
            .filter { videoExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                let dateB = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                return dateA > dateB
            }

        for url in sorted {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 40, height: 40)
            let item = ClipboardItem(
                type: .file,
                name: url.lastPathComponent,
                url: url,
                text: nil,
                dateAdded: (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date(),
                icon: icon
            )
            recordings.append(item)
        }
        NSLog("[ScreenRecorder] Loaded %d existing recordings", recordings.count)
    }

    func removeRecording(_ item: ClipboardItem) {
        if let url = item.url {
            try? FileManager.default.removeItem(at: url)
        }
        recordings.removeAll { $0.id == item.id }
    }

    func clearAll() {
        for item in recordings {
            if let url = item.url {
                try? FileManager.default.removeItem(at: url)
            }
        }
        recordings.removeAll()
    }

    func copyToClipboard(_ item: ClipboardItem) {
        guard let url = item.url else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([url as NSURL])
    }
}

// MARK: - SCStream Output & Delegate

@available(macOS 13.0, *)
private class StreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    weak var recorder: ScreenRecorder?

    init(recorder: ScreenRecorder) {
        self.recorder = recorder
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }

        switch type {
        case .screen:
            recorder?.handleVideoSample(sampleBuffer)
        case .audio:
            recorder?.handleAudioSample(sampleBuffer)
        case .microphone:
            break
        @unknown default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("[ScreenRecorder] Stream stopped with error: %@", error.localizedDescription)
        DispatchQueue.main.async { [weak self] in
            self?.recorder?.stopRecording()
        }
    }
}
