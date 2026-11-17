import Foundation
import Speech
import AVFoundation
import Observation

nonisolated enum SpeechLanguage: String, CaseIterable, Identifiable {
    case english = "en-US"
    case arabic = "ar-SA"
    var id: String { rawValue }
    var label: String { self == .english ? "EN" : "AR" }
}

/// Microphone dictation with live partial results. Input only; the app never speaks.
@MainActor
@Observable
final class SpeechService {
    var isRecording = false
    var transcript = ""
    var errorMessage: String?
    var language: SpeechLanguage = .english

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var finishContinuation: CheckedContinuation<Void, Never>?

    func start() async {
        errorMessage = nil
        guard !isRecording else { return }
        guard await Self.requestPermissions(onError: { self.errorMessage = $0 }) else { return }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.rawValue)), recognizer.isAvailable else {
            errorMessage = "Speech recognition for \(language.rawValue) is not available right now. Check your internet connection or try the other language."
            return
        }
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            errorMessage = "No microphone found. Connect one and try again."
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.recognizer = recognizer
        self.request = request
        transcript = ""

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            request.append(buffer)
        }
        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            errorMessage = "Could not start the microphone: \(error.localizedDescription)"
            return
        }
        isRecording = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failure = error
            Task { @MainActor in self?.handle(text: text, isFinal: isFinal, error: failure) }
        }
    }

    /// Stops recording and returns the final transcript once recognition settles (bounded wait).
    func stop() async -> String {
        guard isRecording else { return transcript }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        isRecording = false
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            finishContinuation = continuation
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                self.finish()
            }
        }
        task?.cancel()
        task = nil
        request = nil
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handle(text: String?, isFinal: Bool, error: Error?) {
        if let text { transcript = text }
        if let error, isRecording {
            let code = (error as NSError).code
            if code != 216 && code != 1110 {   // 216: cancelled, 1110: no speech detected
                errorMessage = "Recognition stopped: \(error.localizedDescription)"
            }
            Task { _ = await stop() }
        }
        if isFinal || error != nil { finish() }
    }

    private func finish() {
        finishContinuation?.resume()
        finishContinuation = nil
    }

    private static func requestPermissions(onError: @MainActor (String) -> Void) async -> Bool {
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        guard mic else {
            onError("Microphone access was denied. Allow it in System Settings > Privacy & Security > Microphone.")
            return false
        }
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        switch speech {
        case .authorized: return true
        case .denied:
            onError("Speech recognition was denied. Allow it in System Settings > Privacy & Security > Speech Recognition.")
        case .restricted:
            onError("Speech recognition is restricted on this Mac.")
        case .notDetermined:
            onError("Speech recognition permission was not granted.")
        @unknown default:
            onError("Speech recognition is unavailable.")
        }
        return false
    }
}
