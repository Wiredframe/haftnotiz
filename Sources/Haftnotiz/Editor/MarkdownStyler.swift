import AppKit

extension NSAttributedString.Key {
    /// Marks a `- [ ]` / `- [x]` range; the value is `true` when ticked. The characters are drawn
    /// invisible and `CheckboxLayoutManager` paints a circle over them.
    static let haftCheckbox = NSAttributedString.Key("de.wiredframe.haftnotiz.checkbox")
}

/// Turns `MarkdownSyntax` spans into text attributes. The Markdown stays in the text (markers are
/// dimmed, not hidden), so the file is exactly what you see.
struct MarkdownStyler {
    var ink: NSColor
    var secondary: NSColor
    var accent: NSColor

    static let fontSize: CGFloat = 14

    static var bodyFont: NSFont { .systemFont(ofSize: fontSize) }

    static var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.18
        style.paragraphSpacing = 2
        return style
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: Self.bodyFont, .foregroundColor: ink, .paragraphStyle: Self.paragraphStyle]
    }

    /// Restyles the whole paragraphs touching `range`.
    func apply(to storage: NSTextStorage, in range: NSRange) {
        let ns = storage.string as NSString
        let paragraphs = ns.paragraphRange(for: range)
        storage.setAttributes(baseAttributes, range: paragraphs)
        ns.enumerateSubstrings(in: paragraphs, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let line = ns.substring(with: lineRange)
            let spans = MarkdownSyntax.spans(in: line).map {
                MarkdownSyntax.Span(range: NSRange(location: $0.range.location + lineRange.location, length: $0.range.length),
                                    kind: $0.kind)
            }
            // Order matters: fonts first, then colours on top, the checkbox last.
            for span in spans.sorted(by: { Self.order($0.kind) < Self.order($1.kind) }) {
                style(span, in: storage)
            }
        }
    }

    func applyAll(to storage: NSTextStorage) {
        storage.beginEditing()
        if storage.length == 0 {
            storage.setAttributes(baseAttributes, range: NSRange(location: 0, length: 0))
        } else {
            apply(to: storage, in: NSRange(location: 0, length: storage.length))
        }
        storage.endEditing()
    }

    private static func order(_ kind: MarkdownSyntax.Kind) -> Int {
        switch kind {
        case .heading: 0
        case .quote, .done: 1
        case .bold, .italic, .code, .strike: 2
        case .link: 3
        case .marker, .bullet: 4
        case .checkbox: 5
        }
    }

    private func style(_ span: MarkdownSyntax.Span, in storage: NSTextStorage) {
        let r = span.range
        guard r.length > 0, r.upperBound <= storage.length else { return }
        switch span.kind {
        case let .heading(level):
            let size: CGFloat = [1: 21, 2: 18, 3: 16][level] ?? Self.fontSize
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: size, weight: level <= 2 ? .bold : .semibold), range: r)
        case .marker:
            storage.addAttribute(.foregroundColor, value: secondary.withAlphaComponent(0.7), range: r)
        case .bullet:
            storage.addAttribute(.foregroundColor, value: accent, range: r)
        case let .checkbox(done):
            storage.addAttributes([.foregroundColor: NSColor.clear, .haftCheckbox: done], range: r)
        case .done:
            storage.addAttributes([.foregroundColor: secondary, .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                   .strikethroughColor: secondary.withAlphaComponent(0.6)], range: r)
        case .quote:
            storage.addAttribute(.foregroundColor, value: secondary, range: r)
            addTrait(.italicFontMask, in: r, storage)
        case .bold:
            addTrait(.boldFontMask, in: r, storage)
        case .italic:
            addTrait(.italicFontMask, in: r, storage)
        case .code:
            storage.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: Self.fontSize - 1, weight: .regular),
                .backgroundColor: accent.withAlphaComponent(0.16),
            ], range: r)
        case .strike:
            storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: secondary], range: r)
        case let .link(target):
            if let url = URL(string: target) { storage.addAttribute(.link, value: url, range: r) }
        }
    }

    private func addTrait(_ trait: NSFontTraitMask, in range: NSRange, _ storage: NSTextStorage) {
        storage.enumerateAttribute(.font, in: range) { value, sub, _ in
            guard let font = value as? NSFont else { return }
            storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: sub)
        }
    }
}

/// Draws checkbox circles over `.haftCheckbox` ranges (whose characters are invisible).
final class CheckboxLayoutManager: NSLayoutManager {
    var openColor: NSColor = .secondaryLabelColor
    var doneColor: NSColor = .controlAccentColor

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainers.first else { return }
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.haftCheckbox, in: chars) { value, range, _ in
            guard let done = value as? Bool else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let line = lineFragmentUsedRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            let box = boundingRect(forGlyphRange: glyphs, in: container)
            let size: CGFloat = 15
            let rect = NSRect(x: origin.x + box.minX + 1, y: origin.y + line.midY - size / 2, width: size, height: size)
            Self.symbol(done: done, color: done ? doneColor : openColor, size: size)?
                .draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    static func symbol(done: Bool, color: NSColor, size: CGFloat) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
            .applying(.init(paletteColors: [color]))
        return NSImage(systemSymbolName: done ? "checkmark.circle.fill" : "circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }
}
