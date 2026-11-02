import AVFoundation
import UIKit

/// Plan G6: videos up to 60 seconds, exported to 1080p H.264 MP4 with the
/// moov atom at the front so playback can start before the download ends.
nonisolated enum MediaLimits {
    static let maxVideoSeconds: Double = 60
    static let maxItemsPerPost = 10

    /// Allows a little slack for rounding (60.4 s is a "60 second" clip).
    static func videoDurationIsAllowed(_ seconds: Double) -> Bool {
        seconds > 0 && seconds <= maxVideoSeconds + 0.5
    }
}

nonisolated enum VideoExporter {
    struct Exported: Sendable {
        let fileURL: URL
        let thumbnail: Data
        let pixelSize: CGSize
        let duration: Double
    }

    enum ExportError: Error {
        case tooLong(Double)
        case unreadable
        case exportFailed
    }

    static func duration(of url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let d = try await asset.load(.duration)
        return CMTimeGetSeconds(d)
    }

    /// Transcodes and trims nothing: a clip over the limit is refused.
    static func export(_ sourceURL: URL, overlay: UIImage? = nil) async throws -> Exported {
        let asset = AVURLAsset(url: sourceURL)
        let seconds = CMTimeGetSeconds(try await asset.load(.duration))
        guard MediaLimits.videoDurationIsAllowed(seconds) else { throw ExportError.tooLong(seconds) }

        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw ExportError.unreadable }
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let displaySize = naturalSize.applying(transform)
        let renderSize = CGSize(width: abs(displaySize.width), height: abs(displaySize.height))

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        let preset = max(renderSize.width, renderSize.height) > 1920 ? AVAssetExportPreset1920x1080 : AVAssetExportPresetHighestQuality
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw ExportError.exportFailed }
        session.shouldOptimizeForNetworkUse = true   // moov atom first

        if let overlay {
            session.videoComposition = try await composition(for: asset, track: track, renderSize: renderSize, transform: transform, overlay: overlay)
        }

        try await session.export(to: outputURL, as: .mp4)

        let thumb = try await thumbnail(of: outputURL)
        let scaled = min(1, 1920 / max(renderSize.width, renderSize.height, 1))
        let finalSize = CGSize(width: (renderSize.width * scaled).rounded(), height: (renderSize.height * scaled).rounded())
        return Exported(fileURL: outputURL, thumbnail: thumb, pixelSize: finalSize, duration: seconds)
    }

    static func thumbnail(of url: URL, at seconds: Double = 0.5) async throws -> Data {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 800, height: 800)
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        let (cgImage, _) = try await generator.image(at: time)
        guard let data = ImageProcessor.thumbnail(UIImage(cgImage: cgImage)) else { throw ExportError.exportFailed }
        return data
    }

    /// Burns a text overlay (rendered to an image by the caller) over the whole clip (plan G5).
    private static func composition(for asset: AVAsset, track: AVAssetTrack, renderSize: CGSize, transform: CGAffineTransform, overlay: UIImage) async throws -> AVMutableVideoComposition {
        let composition = AVMutableVideoComposition()
        composition.renderSize = renderSize
        composition.frameDuration = CMTime(value: 1, timescale: 30)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: try await asset.load(.duration))
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layerInstruction.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        composition.instructions = [instruction]

        let parent = CALayer()
        parent.frame = CGRect(origin: .zero, size: renderSize)
        let videoLayer = CALayer()
        videoLayer.frame = parent.frame
        let overlayLayer = CALayer()
        overlayLayer.frame = parent.frame
        overlayLayer.contents = overlay.cgImage
        overlayLayer.contentsGravity = .resizeAspectFill
        parent.addSublayer(videoLayer)
        parent.addSublayer(overlayLayer)
        composition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parent)
        return composition
    }
}
