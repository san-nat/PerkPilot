import Foundation
import AVFoundation
import Speech
import Combine

// MARK: - SpeechService
//
// Voice input (Speech framework) + spoken answers (AVSpeechSynthesizer).
// Everything else in the app is on-device; speech recognition is the one
// exception — Apple may process audio on its servers. That is disclosed in
// the mic permission prompt, the in-app explanation, and the README.
// Typing always works; voice is purely optional.

enum SpeechAuthState {
    case notDetermined
    case requesting
    case authorized
    case denied
}

@MainActor
final class SpeechService: ObservableObject {
    @Published var isRecording = false
    @Published var liveTranscript = ""
    @Published var authState: SpeechAuthState = .notDetermined
    @Published var errorMessage: String?

    /// Called once when the user stops recording with a final transcript.
    var onFinalTranscript: ((String) -> Void)?

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        refreshAuthState()
    }

    var isAvailable: Bool {
        recognizer?.isAvailable ?? false
    }

    // MARK: - Permissions

    func refreshAuthState() {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined: authState = .notDetermined
        case .authorized: authState = .authorized
        case .denied, .restricted: authState = .denied
        @unknown default: authState = .denied
        }
    }

    /// Asks for speech-recognition + microphone permission, with the
    /// server-processing disclosure shown before the system prompt.
    func requestPermissions(completion: @escaping (Bool) -> Void = { _ in }) {
        authState = .requesting
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                guard status == .authorized else {
                    self.authState = .denied
                    completion(false)
                    return
                }
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    Task { @MainActor in
                        self.authState = granted ? .authorized : .denied
                        completion(granted)
                    }
                }
            }
        }
    }

    // MARK: - Recording

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        errorMessage = nil
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now — type your question instead."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Couldn't start the microphone — type your question instead."
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        // Prefer on-device recognition when the device supports it.
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            errorMessage = "Couldn't start the microphone — type your question instead."
            return
        }

        liveTranscript = ""
        isRecording = true
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.liveTranscript = result.bestTranscription.formattedString
                    if result.isFinal {
                        let final = self.liveTranscript
                        self.stopRecording()
                        if !final.trimmingCharacters(in: .whitespaces).isEmpty {
                            self.onFinalTranscript?(final)
                        }
                    }
                } else if error != nil {
                    // Keep any partial transcript; the UI falls back to typing.
                    self.stopRecording()
                }
            }
        }
    }

    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    // MARK: - Spoken answers

    /// Reads an answer aloud. Markdown markers are stripped first.
    func speak(_ markdown: String) {
        stopSpeaking()
        let plain = markdown
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let utterance = AVSpeechUtterance(string: plain)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
