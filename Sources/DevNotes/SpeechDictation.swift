import AVFoundation
import Speech
import SwiftUI

private final class DictationAudioRouter: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func setRequest(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock(); defer { lock.unlock() }
        self.request = request
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        request?.append(buffer)
    }
}

@MainActor
final class SpeechDictation: ObservableObject {
    enum Phase { case idle, preparing, listening, finishing }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var transcript = ""
    @Published var errorMessage: String?
    var isBusy: Bool { phase != .idle }

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var hasTap = false
    private var sessionID: UUID?
    private var completion: ((String) -> Void)?
    private var finishTimeout: Task<Void, Never>?
    private let audioRouter = DictationAudioRouter()
    private var accumulated = DictationTranscript()
    private var recognitionID: UUID?

    func start(completion: @escaping (String) -> Void) async {
        guard !isBusy, !Task.isCancelled else { return }
        let id = UUID()
        sessionID = id
        self.completion = completion
        transcript = ""
        accumulated = DictationTranscript()
        errorMessage = nil
        phase = .preparing

        guard let speech = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU")),
              speech.supportsOnDeviceRecognition else {
            fail("На этом Mac недоступно локальное распознавание русского языка. Аудио не записывалось и не отправлялось на сервер.")
            return
        }
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard sessionID == id else { return }
        guard authorization == .authorized else {
            fail("Разрешите распознавание речи для DevNotes в системных настройках → Конфиденциальность и безопасность.")
            return
        }
        let microphone = await AVCaptureDevice.requestAccess(for: .audio)
        guard sessionID == id else { return }
        guard microphone else {
            fail("Разрешите доступ к микрофону для DevNotes в системных настройках → Конфиденциальность и безопасность → Микрофон.")
            return
        }
        guard speech.isAvailable else {
            fail("Распознавание сейчас недоступно. Попробуйте ещё раз. Облачная обработка отключена.")
            return
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            fail("Микрофон недоступен. Проверьте выбранное устройство ввода в настройках звука.")
            return
        }
        recognizer = speech
        let audioRouter = audioRouter
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            audioRouter.append(buffer)
        }
        hasTap = true
        beginRecognition(session: id)
        do {
            engine.prepare()
            try engine.start()
            phase = .listening
        } catch {
            fail("Не удалось включить микрофон. Проверьте устройство ввода и повторите попытку.")
        }
    }

    private func beginRecognition(session id: UUID) {
        guard let speech = recognizer, sessionID == id else { return }
        let taskID = UUID()
        recognitionID = taskID
        recognition?.cancel()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        self.request = request
        audioRouter.setRequest(request)
        recognition = speech.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.sessionID == id, self.recognitionID == taskID else { return }
                if let result {
                    let segments = result.bestTranscription.segments
                    let start = segments.first?.timestamp
                    let end = segments.last.map { $0.timestamp + $0.duration }
                    self.accumulated.update(result.bestTranscription.formattedString,
                        start: start, end: end,
                        isStable: result.speechRecognitionMetadata != nil || result.isFinal,
                        receivedAt: ProcessInfo.processInfo.systemUptime)
                    self.transcript = self.accumulated.text
                    if result.isFinal {
                        if self.phase == .finishing { self.finishImmediately() }
                        else {
                            self.accumulated.beginNewTask()
                            self.beginRecognition(session: id)
                        }
                        return
                    }
                }
                if error != nil {
                    let hasText = !self.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    self.finishImmediately()
                    self.errorMessage = hasText
                        ? "Диктовка остановилась. Уже распознанный текст добавлен в заметку."
                        : "Не удалось распознать речь. Проверьте микрофон и доступность локального русского языка в macOS."
                }
            }
        }
    }

    func stop() {
        guard phase == .listening else {
            if phase == .preparing { finishImmediately() }
            return
        }
        stopMicrophone()
        phase = .finishing
        request?.endAudio()
        let id = sessionID
        // Some local models never send a final result after endAudio.
        // Preserve the last partial result instead of leaving the UI stuck.
        finishTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self, self.sessionID == id else { return }
            self.finishImmediately()
        }
    }

    func finishImmediately() {
        guard sessionID != nil else { return }
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let onComplete = completion
        sessionID = nil // Ignore late callbacks before cancelling the task.
        recognitionID = nil
        completion = nil
        finishTimeout?.cancel()
        finishTimeout = nil
        stopMicrophone()
        request?.endAudio()
        recognition?.cancel()
        recognition = nil
        request = nil
        recognizer = nil
        transcript = ""
        accumulated = DictationTranscript()
        phase = .idle
        if !text.isEmpty { onComplete?(text) }
    }

    private func stopMicrophone() {
        audioRouter.setRequest(nil)
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
    }

    private func fail(_ message: String) {
        finishImmediately()
        errorMessage = message
    }
}
