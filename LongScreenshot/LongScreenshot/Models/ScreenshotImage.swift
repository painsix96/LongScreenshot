import SwiftUI

struct ScreenshotImage: Identifiable, Equatable {
    let id = UUID()
    let image: UIImage
    let creationDate: Date
    var order: Int

    var thumbnail: UIImage? {
        let size = CGSize(width: 200, height: 200)
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        defer { UIGraphicsEndImageContext() }

        let aspectRatio = image.size.width / image.size.height
        var drawRect: CGRect

        if aspectRatio > 1 {
            let height = size.width / aspectRatio
            drawRect = CGRect(
                x: 0,
                y: (size.height - height) / 2,
                width: size.width,
                height: height
            )
        } else {
            let width = size.height * aspectRatio
            drawRect = CGRect(
                x: (size.width - width) / 2,
                y: 0,
                width: width,
                height: size.height
            )
        }

        image.draw(in: drawRect)
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

struct StitchedResult {
    let image: UIImage
    let originalCount: Int
    let createdAt: Date
    let dimensions: CGSize
}
