import AVFoundation
import Foundation
import ScreenCaptureKit

struct RecordingOptions {
    var framesPerSecond: Int
    var showsCursor: Bool
    var showsClicks: Bool
    var capturesSystemAudio: Bool
    var microphoneID: String?
}

final class Recorder: NSObject, SCStreamDelegate, SCRecordingOutputDelegate {
    var onFinish: ((Result<URL, Error>) -> Void)?

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var outputURL: URL?

    var isRecording: Bool { stream != nil }

    func start(target: CaptureTarget, options: RecordingOptions, outputURL: URL) async throws {
        guard stream == nil else { throw CaptureError.alreadyRecording }

        let resolved = try await ResolvedCapture.resolve(target)
        let size = resolved.pixelSize(even: true)

        let configuration = SCStreamConfiguration()
        if let sourceRect = resolved.sourceRect {
            configuration.sourceRect = sourceRect
        }
        configuration.width = size.width
        configuration.height = size.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(options.framesPerSecond, 1)))
        configuration.queueDepth = 8
        configuration.showsCursor = options.showsCursor
        configuration.showMouseClicks = options.showsClicks
        configuration.capturesAudio = options.capturesSystemAudio
        configuration.excludesCurrentProcessAudio = true
        if let microphoneID = options.microphoneID {
            configuration.captureMicrophone = true
            configuration.microphoneCaptureDeviceID = microphoneID
        }

        let outputConfiguration = SCRecordingOutputConfiguration()
        outputConfiguration.outputURL = outputURL
        outputConfiguration.outputFileType = .mov
        outputConfiguration.videoCodecType = (size.width > 4096 || size.height > 2304) ? .hevc : .h264

        let stream = SCStream(filter: resolved.filter, configuration: configuration, delegate: self)
        let recordingOutput = SCRecordingOutput(configuration: outputConfiguration, delegate: self)
        try stream.addRecordingOutput(recordingOutput)

        self.stream = stream
        self.recordingOutput = recordingOutput
        self.outputURL = outputURL

        do {
            try await stream.startCapture()
        } catch {
            reset()
            throw error
        }
    }

    func stop() async {
        guard let stream else { return }
        do {
            try await stream.stopCapture()
        } catch {
            finish(.failure(error))
        }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        guard let url = outputURL else { return }
        finish(.success(url))
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        finish(.failure(error))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard let url = outputURL else {
            finish(.failure(error))
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            if FileManager.default.fileExists(atPath: url.path) {
                self?.finish(.success(url))
            } else {
                self?.finish(.failure(error))
            }
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream != nil else { return }
            self.reset()
            self.onFinish?(result)
        }
    }

    private func reset() {
        stream = nil
        recordingOutput = nil
        outputURL = nil
    }
}
