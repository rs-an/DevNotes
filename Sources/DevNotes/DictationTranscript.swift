import Foundation

// A recognition result can be a revision of the current phrase, a new phrase
// after silence, or a cumulative result. Do not append every partial result.
struct DictationTranscript {
    private var previousTasks: [String] = []
    private var completed: [String] = []
    private var draft = ""
    private var firstTime: TimeInterval?
    private var endTime: TimeInterval?
    private var stable = false
    private var lastUpdate: TimeInterval?

    private var taskText: String { (completed + [draft]).filter { !$0.isEmpty }.joined(separator: " ") }
    var text: String { (previousTasks + [taskText]).filter { !$0.isEmpty }.joined(separator: " ") }

    mutating func update(_ value: String, start: TimeInterval?, end: TimeInterval?,
                         isStable: Bool, receivedAt: TimeInterval) {
        let incoming = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !incoming.isEmpty else { return } // Empty finals must not erase speech.
        let old = normalized(draft)
        let new = normalized(incoming)
        let coversWholeText = !completed.isEmpty && new.hasPrefix(normalized(taskText))
        let restoresEarlierAudio = !completed.isEmpty && start != nil && firstTime != nil &&
            start! < firstTime! - 0.1 && end != nil && endTime != nil && end! >= endTime! - 0.1
        if coversWholeText || restoresEarlierAudio {
            // Some OS versions resume returning all text after per-phrase results.
            completed = []
        } else if !draft.isEmpty {
            let laterAudio = start != nil && endTime != nil && start! > endTime! + 0.15
            let hasTiming = (end ?? 0) > (start ?? 0) && (endTime ?? 0) > (firstTime ?? 0)
            let samePhraseRevision = new.hasPrefix(old) || old.hasPrefix(new)
            let newPhraseAfterStable = stable && new != old && !new.hasPrefix(old)
            let silenceWithoutTiming = !hasTiming && (newPhraseAfterStable ||
                (!samePhraseRevision && receivedAt - (lastUpdate ?? receivedAt) > 1.5))
            if laterAudio || silenceWithoutTiming { completed.append(draft) }
        }
        draft = incoming
        firstTime = start
        endTime = end
        stable = isStable
        lastUpdate = receivedAt
    }

    mutating func beginNewTask() {
        if !taskText.isEmpty { previousTasks.append(taskText) }
        completed = []
        draft = ""
        firstTime = nil
        endTime = nil
        stable = false
        lastUpdate = nil
    }

    private func normalized(_ text: String) -> String {
        text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
    }
}
