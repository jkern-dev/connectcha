import Testing
import UIKit
@testable import Connectcha

struct StoryComposerTests {
    @Test("burning text keeps the pixel size and changes the pixels")
    func burnText() {
        let base = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 900), format: {
            let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f
        }()).image { ctx in
            UIColor.blue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 900))
        }
        let out = StoryComposer.burn(text: "Happy birthday Grandma!", into: base)
        #expect(out.pixelSize == CGSize(width: 600, height: 900))
        #expect(out.pngData() != base.pngData())
        #expect(StoryComposer.burn(text: "   ", into: base) === base, "blank text leaves the image untouched")
    }

    @Test("overlay image for videos is transparent and sized to the video")
    func overlay() {
        let overlay = StoryComposer.overlayImage(text: "Lake day", size: CGSize(width: 1080, height: 1920))
        #expect(overlay?.pixelSize == CGSize(width: 1080, height: 1920))
        #expect(StoryComposer.overlayImage(text: "", size: CGSize(width: 10, height: 10)) == nil)
    }
}
