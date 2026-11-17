import AppKit
import SwiftUI

struct LinkAwareTextEditor: View {
    @Binding var text: String
    let placeholder: String
    let font: NSFont
    let minimumHeight: CGFloat
    var strikethrough = false
    var submitOnReturn = false
    var isFocused: Binding<Bool>?
    var onMarkdownTablePaste: (([[String]]) -> Void)?
    var onSubmit: (() -> Void)?
    var onNewTextBlock: (() -> Void)?

    @State private var measuredHeight: CGFloat = 0

    var body: some View {
        LinkTextViewRepresentable(
            text: $text,
            placeholder: placeholder,
            measuredHeight: $measuredHeight,
            font: font,
            minimumHeight: minimumHeight,
            strikethrough: strikethrough,
            submitOnReturn: submitOnReturn,
            isFocused: isFocused,
            onSubmit: onSubmit,
            onNewTextBlock: onNewTextBlock,
            onMarkdownTablePaste: onMarkdownTablePaste
        )
        .frame(height: max(minimumHeight, measuredHeight))
    }
}

private struct LinkTextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    @Binding var measuredHeight: CGFloat
    let font: NSFont
    let minimumHeight: CGFloat
    let strikethrough: Bool
    let submitOnReturn: Bool
    let isFocused: Binding<Bool>?
    let onSubmit: (() -> Void)?
    let onNewTextBlock: (() -> Void)?
    let onMarkdownTablePaste: (([[String]]) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ClickableLinkTextView {
        let textView = ClickableLinkTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 5, height: 7)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.heightDidChange = { height in
            guard abs(measuredHeight - height) > 0.5 else { return }
            DispatchQueue.main.async {
                measuredHeight = height
            }
        }
        configure(textView, coordinator: context.coordinator)
        return textView
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ClickableLinkTextView, context: Context) -> CGSize? {
        // Give AppKit the full block height instead of centering its intrinsic
        // one-line view inside SwiftUI's taller frame.
        CGSize(width: proposal.width ?? nsView.bounds.width,
               height: max(minimumHeight, measuredHeight))
    }

    func updateNSView(_ textView: ClickableLinkTextView, context: Context) {
        context.coordinator.parent = self
        configure(textView, coordinator: context.coordinator)

        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges.filter {
                NSMaxRange($0.rangeValue) <= (text as NSString).length
            }
        }

        context.coordinator.applyFormatting(to: textView)
        textView.invalidateIntrinsicContentSize()
        DispatchQueue.main.async { textView.reportHeight() }

        if isFocused?.wrappedValue == true,
           textView.window?.firstResponder !== textView {
            DispatchQueue.main.async {
                textView.focusIfRequested()
            }
        }
    }

    private func configure(_ textView: ClickableLinkTextView, coordinator: Coordinator) {
        textView.minimumHeight = minimumHeight
        textView.focusRequested = { coordinator.parent.isFocused?.wrappedValue == true }
        textView.font = font
        textView.placeholder = placeholder
        textView.needsDisplay = true
        textView.submitOnReturn = submitOnReturn
        textView.onSubmit = onSubmit
        textView.onNewTextBlock = onNewTextBlock
        textView.markdownTablePasteHandler = { source in
            guard let onMarkdownTablePaste,
                  let table = MarkdownTableParser.parse(source) else { return false }
            onMarkdownTablePaste(table)
            return true
        }
        textView.linkHandler = { value in
            guard let url = value as? URL ?? (value as? String).flatMap(URL.init(string:)),
                  let scheme = url.scheme?.lowercased(),
                  ["https", "http", "mailto"].contains(scheme) else { return }
            NSWorkspace.shared.open(url)
        }
        textView.typingAttributes = coordinator.baseAttributes
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LinkTextViewRepresentable
        private static let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        )

        init(parent: LinkTextViewRepresentable) {
            self.parent = parent
        }

        var baseAttributes: [NSAttributedString.Key: Any] {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: parent.font,
                .foregroundColor: NSColor.labelColor
            ]
            if parent.strikethrough {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attributes[.strikethroughColor] = NSColor.secondaryLabelColor
            }
            return attributes
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.isFocused?.wrappedValue = true
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.isFocused?.wrappedValue = false
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? ClickableLinkTextView else { return }
            parent.text = textView.string
            applyFormatting(to: textView)
            textView.reportHeight()
        }

        func applyFormatting(to textView: NSTextView) {
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            guard fullRange.length > 0 else {
                textView.typingAttributes = baseAttributes
                return
            }

            textView.textStorage?.beginEditing()
            textView.textStorage?.setAttributes(baseAttributes, range: fullRange)
            Self.detector?.enumerateMatches(
                in: textView.string,
                options: [],
                range: fullRange
            ) { match, _, _ in
                guard let match, let url = match.url else { return }
                textView.textStorage?.addAttributes([
                    .link: url,
                    .foregroundColor: NSColor.systemOrange,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ], range: match.range)
            }
            textView.textStorage?.endEditing()
            textView.typingAttributes = baseAttributes
        }
    }
}

private final class ClickableLinkTextView: NSTextView {
    var placeholder = ""
    var focusRequested: (() -> Bool)?
    var minimumHeight: CGFloat = 27
    var heightDidChange: ((CGFloat) -> Void)?
    var submitOnReturn = false
    var onSubmit: (() -> Void)?
    var onNewTextBlock: (() -> Void)?
    var linkHandler: ((Any) -> Void)?
    var markdownTablePasteHandler: ((String) -> Bool)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in self?.focusIfRequested() }
    }

    func focusIfRequested() {
        guard focusRequested?() == true, let window,
              window.firstResponder !== self else { return }
        window.makeFirstResponder(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, let font else { return }
        // Use the same native text origin and font as the insertion point.
        (placeholder as NSString).draw(at: textContainerOrigin, withAttributes: [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.55)
        ])
    }

    override func layout() {
        super.layout()
        reportHeight()
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
        invalidateIntrinsicContentSize()
        reportHeight()
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.shift, .command, .control, .option])
        if (event.keyCode == 36 || event.keyCode == 76),
           modifiers == .shift, !hasMarkedText(), let onNewTextBlock {
            onNewTextBlock()
            return
        }
        if submitOnReturn,
           (event.keyCode == 36 || event.keyCode == 76),
           !event.modifierFlags.contains(.shift) {
            onSubmit?()
            return
        }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        if !event.modifierFlags.contains(.option), let link = link(at: event) {
            linkHandler?(link)
            return
        }
        super.mouseDown(with: event)
    }

    override func paste(_ sender: Any?) {
        if let source = NSPasteboard.general.string(forType: .string),
           markdownTablePasteHandler?(source) == true {
            return
        }
        super.paste(sender)
    }

    func reportHeight() {
        guard bounds.width > 0,
              let textContainer,
              let layoutManager else { return }
        textContainer.containerSize = NSSize(
            width: max(bounds.width - textContainerInset.width * 2, 1),
            height: CGFloat.greatestFiniteMagnitude
        )
        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = layoutManager.usedRect(for: textContainer).height
        heightDidChange?(ceil(max(minimumHeight, usedHeight + textContainerInset.height * 2)))
    }

    private func link(at event: NSEvent) -> Any? {
        guard let textContainer,
              let layoutManager,
              let textStorage,
              !textStorage.string.isEmpty else { return nil }

        let point = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }

        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        )
        guard glyphRect.insetBy(dx: -1, dy: -2).contains(containerPoint) else { return nil }

        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < textStorage.length else { return nil }
        return textStorage.attribute(.link, at: characterIndex, effectiveRange: nil)
    }
}
