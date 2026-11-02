import UIKit

/// Plan G5: text overlays are burned into the media on the device, so every
/// viewer sees the same thing and "save to phone" includes the text.
nonisolated enum StoryComposer {
    /// Renders `text` centred over the image, with a soft shadow for legibility.
    /// Returns the same pixel size as the input.
    static func burn(text: String, into image: UIImage) -> UIImage {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return image }
        let size = image.pixelSize
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            image.draw(in: CGRect(origin: .zero, size: size))
            drawOverlay(text: trimmed, in: CGRect(origin: .zero, size: size), context: ctx.cgContext)
        }
    }

    /// A transparent overlay image for videos (composited by VideoExporter).
    static func overlayImage(text: String, size: CGSize) -> UIImage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, size.width > 0, size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            drawOverlay(text: trimmed, in: CGRect(origin: .zero, size: size), context: ctx.cgContext)
        }
    }

    private static func drawOverlay(text: String, in rect: CGRect, context: CGContext) {
        let fontSize = max(28, rect.width * 0.065)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraph,
        ]
        let inset = rect.width * 0.08
        let maxWidth = rect.width - inset * 2
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: rect.height * 0.6),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes, context: nil)
        let textRect = CGRect(x: inset, y: (rect.height - bounds.height) / 2, width: maxWidth, height: bounds.height)

        // Dark pill behind the text keeps it readable on any photo.
        let pill = textRect.insetBy(dx: -fontSize * 0.6, dy: -fontSize * 0.4)
        context.setFillColor(UIColor.black.withAlphaComponent(0.42).cgColor)
        UIBezierPath(roundedRect: pill, cornerRadius: fontSize * 0.5).fill()
        (text as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
    }
}
