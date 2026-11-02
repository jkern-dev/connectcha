import UIKit

/// Photo preparation (plan 3.7): a 2048 px JPEG plus a 400 px thumbnail.
/// Runs off the main actor; call from a Task.
nonisolated enum ImageProcessor {
    struct Prepared: Sendable {
        let full: Data
        let thumb: Data
        let pixelSize: CGSize
    }

    static let fullMaxDimension: CGFloat = 2048
    static let thumbMaxDimension: CGFloat = 400

    static func prepare(_ image: UIImage) -> Prepared? {
        let normalized = image.normalizedOrientation()
        guard let full = normalized.resized(maxDimension: fullMaxDimension),
              let fullData = full.jpegData(compressionQuality: 0.85),
              let thumb = normalized.resized(maxDimension: thumbMaxDimension),
              let thumbData = thumb.jpegData(compressionQuality: 0.8)
        else { return nil }
        return Prepared(full: fullData, thumb: thumbData, pixelSize: full.pixelSize)
    }

    /// Thumbnail for a video frame (already a UIImage from AVAssetImageGenerator).
    static func thumbnail(_ image: UIImage) -> Data? {
        image.resized(maxDimension: thumbMaxDimension)?.jpegData(compressionQuality: 0.8)
    }
}

nonisolated extension UIImage {
    var pixelSize: CGSize { CGSize(width: size.width * scale, height: size.height * scale) }

    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func resized(maxDimension: CGFloat) -> UIImage? {
        let px = pixelSize
        let longest = max(px.width, px.height)
        let ratio = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: (px.width * ratio).rounded(.down), height: (px.height * ratio).rounded(.down))
        guard target.width > 0, target.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
