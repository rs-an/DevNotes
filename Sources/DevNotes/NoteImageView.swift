import AppKit
import SwiftUI

/// Shared image geometry for editing and compact previews.
enum NoteImageSizing {
    static func fraction(_ value: Double?) -> CGFloat {
        guard let value, value.isFinite else { return 1 }
        return CGFloat(min(max(value, 0.25), 1))
    }

    static func height(for image: NSImage, width: CGFloat) -> CGFloat {
        width * max(image.size.height, 1) / max(image.size.width, 1)
    }
}

struct NoteImageContent: View {
    let image: NSImage
    var cornerRadius: CGFloat = 12

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

struct NoteImagePreview: View {
    let image: NSImage
    let widthFraction: Double?

    var body: some View {
        ImagePreviewLayout(image: image, fraction: NoteImageSizing.fraction(widthFraction)) {
            NoteImageContent(image: image, cornerRadius: 9)
        }
    }
}

private struct ImagePreviewLayout: Layout {
    let image: NSImage
    let fraction: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(proposal.width ?? image.size.width, 0)
        return CGSize(width: width, height: NoteImageSizing.height(for: image, width: width * fraction))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = bounds.width * fraction
        subviews.first?.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: width, height: NoteImageSizing.height(for: image, width: width))
        )
    }
}
