import UIKit

enum ImageColorExtractor {}

extension UIImage {
    /// 将整张图绘制到 1×1 像素的 RGB 上下文中，取平均色。
    var averageColor: UIColor? {
        guard let cgImage = self.cgImage else { return nil }

        let width = 1
        let height = 1
        let bitsPerComponent = 8
        let bytesPerRow = 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return nil }
        let ptr = data.bindMemory(to: UInt8.self, capacity: 4)
        let r = CGFloat(ptr[0]) / 255.0
        let g = CGFloat(ptr[1]) / 255.0
        let b = CGFloat(ptr[2]) / 255.0

        return UIColor(red: r, green: g, blue: b, alpha: 1.0)
    }
}

extension UIColor {
    /// 将颜色调整为适合作为播放器背景氛围的色调：
    /// - saturation 至少 0.25，避免太灰
    /// - brightness 限制在 0.12…0.55，避免太白/太黑
    var backgroundTint: UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        self.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

        let adjustedS = max(s, 0.25)
        let adjustedB = min(max(b, 0.12), 0.55)

        return UIColor(hue: h, saturation: adjustedS, brightness: adjustedB, alpha: a)
    }
}
