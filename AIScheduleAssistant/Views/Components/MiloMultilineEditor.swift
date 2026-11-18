import AppKit
import SwiftUI

/// A genuine multiline editor with an explicit height, independent of its neighbours.
struct MiloMultilineEditor: View {
    @Binding var text: String
    var placeholder: String
    var font: NSFont
    var color: NSColor
    var lineSpacing: CGFloat = 0
    var minimumLines = 1
    var accessibilityLabel: String
    @Environment(\.isEnabled) private var enabled
    @State private var measuredHeight: CGFloat = 0
    private var minimumHeight: CGFloat { ceil((font.ascender - font.descender + font.leading + lineSpacing) * CGFloat(minimumLines)) + 2 }
    var body: some View {
        NativeEditor(text: $text, height: $measuredHeight, placeholder: placeholder, font: font, color: color,
            lineSpacing: lineSpacing, minimumHeight: minimumHeight, accessibilityLabel: accessibilityLabel, editable: enabled)
            .frame(maxWidth: .infinity).frame(height: max(minimumHeight, measuredHeight), alignment: .topLeading)
    }
    private struct NativeEditor: NSViewRepresentable {
        @Binding var text: String
        @Binding var height: CGFloat
        let placeholder: String
        let font: NSFont
        let color: NSColor
        let lineSpacing: CGFloat
        let minimumHeight: CGFloat
        let accessibilityLabel: String
        let editable: Bool
        func makeCoordinator() -> Coordinator { Coordinator(self) }
        func makeNSView(context: Context) -> GrowingTextView {
            let view = GrowingTextView(frame: NSRect(x: 0, y: 0, width: 280, height: minimumHeight))
            view.isRichText = false; view.drawsBackground = false
            view.textContainerInset = .zero; view.textContainer?.lineFragmentPadding = 0
            view.isVerticallyResizable = false; view.isHorizontallyResizable = false
            view.textContainer?.widthTracksTextView = true; view.textContainer?.heightTracksTextView = false
            view.textContainer?.containerSize = NSSize(width: 280, height: 10_000_000)
            view.isAutomaticTextReplacementEnabled = false
            view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
            view.allowsUndo = true; view.focusRingType = .none
            view.wantsLayer = true; view.layer?.masksToBounds = true
            view.setContentHuggingPriority(.defaultLow, for: .horizontal)
            view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            view.delegate = context.coordinator
            let coordinator = context.coordinator
            view.heightChanged = { [weak coordinator] value in
                DispatchQueue.main.async { [weak coordinator] in
                    guard let coordinator, abs(coordinator.parent.height - value) > 0.5 else { return }
                    coordinator.parent.height = value
                }
            }
            updateNSView(view, context: context)
            return view
        }
        func updateNSView(_ view: GrowingTextView, context: Context) {
            context.coordinator.parent = self
            let contentChanged = view.string != text && !view.hasMarkedText()
            let styleChanged = view.font != font || view.textColor != color || view.defaultParagraphStyle?.lineSpacing != lineSpacing
            if contentChanged {
                let selection = view.selectedRange(); view.string = text
                view.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
            }
            if styleChanged || contentChanged {
                let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = lineSpacing
                view.font = font; view.textColor = color; view.defaultParagraphStyle = paragraph
                view.typingAttributes = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
                if !view.hasMarkedText(), let storage = view.textStorage, storage.length > 0 {
                    storage.addAttributes([.font: font, .foregroundColor: color, .paragraphStyle: paragraph], range: NSRange(location: 0, length: storage.length))
                }
            }
            view.minimumHeight = minimumHeight; view.placeholder = placeholder
            view.isEditable = editable; view.isSelectable = true; view.setAccessibilityLabel(accessibilityLabel)
            view.needsDisplay = true; view.measureContent()
        }
        final class Coordinator: NSObject, NSTextViewDelegate {
            var parent: NativeEditor
            init(_ parent: NativeEditor) { self.parent = parent }
            func textDidChange(_ notification: Notification) {
                guard let view = notification.object as? GrowingTextView else { return }
                parent.text = view.string; view.measureContent(); view.needsDisplay = true
            }
        }
    }
    private final class GrowingTextView: NSTextView {
        var placeholder = ""
        var minimumHeight: CGFloat = 24
        var heightChanged: ((CGFloat) -> Void)?
        private var previousWidth: CGFloat = 0
        private var previousHeight: CGFloat = 0
        override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }
        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            if abs(previousWidth - newSize.width) > 0.5 { previousWidth = newSize.width; measureContent() }
        }
        func measureContent() {
            guard bounds.width > 0, let textContainer, let layoutManager else { return }
            textContainer.containerSize = NSSize(width: bounds.width, height: 10_000_000)
            layoutManager.ensureLayout(for: textContainer)
            let used = layoutManager.usedRect(for: textContainer).maxY
            let extra = layoutManager.extraLineFragmentTextContainer === textContainer ? layoutManager.extraLineFragmentRect.maxY : 0
            let value = max(minimumHeight, ceil(max(used, extra)) + 2)
            if abs(previousHeight - value) > 0.5 { previousHeight = value; heightChanged?(value) }
        }
        override func keyDown(with event: NSEvent) {
            if isEditable, [36, 76].contains(event.keyCode), event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                insertText("\n", replacementRange: selectedRange()); return
            }
            super.keyDown(with: event)
        }
        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            if string.isEmpty { placeholder.draw(in: bounds, withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.placeholderTextColor]) }
        }
    }
}
