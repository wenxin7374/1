import UIKit

/// 快门按下瞬间的水印快照。每次拍照都创建独立实例，避免异步处理导致水印错乱。
struct WatermarkSnapshot {
    let timeText: String
    let note: String
}

enum WatermarkRenderer {
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年MM月dd日 HH:mm:ss"
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        return formatter
    }()

    static func format(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// 去掉备注开头可能已存在的“备注：”前缀，避免合成后出现“备注：备注：”。
    static func normalizedNote(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["备注：", "备注:", "备注 ：", "备注 :"]
        var changed = true
        while changed {
            changed = false
            for p in prefixes where s.hasPrefix(p) {
                s = String(s.dropFirst(p.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                changed = true
            }
        }
        return s
    }

    /// 备注最终展示文本（带统一前缀，或为空）。
    static func displayNote(_ raw: String) -> String {
        let clean = normalizedNote(raw)
        return clean.isEmpty ? "" : "备注：\(clean)"
    }

    /// 将水印按最终照片的实际像素尺寸等比例合成到左下角，保持原始分辨率与长宽比。
    static func render(image: UIImage, snapshot: WatermarkSnapshot) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)

        return renderer.image { context in
            let cg = context.cgContext
            let w = image.size.width
            let h = image.size.height

            // UIImage.draw(in:) 会依据 imageOrientation 将照片摆正，避免横竖颠倒。
            image.draw(in: CGRect(x: 0, y: 0, width: w, height: h))

            // 字号按最终照片宽度等比放大，保证成图上左下角文案清晰易读。
            let timeFontSize = max(22, w * 0.042)
            let noteFontSize = max(19, w * 0.032)
            let maxTextWidth = w * 0.90
            let x = w * 0.035
            let bottomInset = h * 0.05

            let noteText = displayNote(snapshot.note)
            let noteStyle = NSMutableParagraphStyle()
            noteStyle.lineBreakMode = .byWordWrapping
            noteStyle.lineSpacing = noteFontSize * 0.15

            let timeAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: timeFontSize),
                .foregroundColor: UIColor.white
            ]
            let noteAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: noteFontSize, weight: .medium),
                .foregroundColor: UIColor.white,
                .paragraphStyle: noteStyle
            ]

            // 备注高度（可能多行）
            var noteHeight: CGFloat = 0
            if !noteText.isEmpty {
                let rect = (noteText as NSString).boundingRect(
                    with: CGSize(width: maxTextWidth, height: CGFloat.greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: noteAttributes,
                    context: nil
                )
                noteHeight = ceil(rect.height)
            }

            let timeHeight = timeFontSize * 1.3
            let gap: CGFloat = noteHeight > 0 ? noteFontSize * 0.5 : 0

            // 从底部往上排布：备注在最下，时间在备注上方，二者互不重叠。
            let noteTopY = h - bottomInset - noteHeight
            let timeTopY = noteTopY - gap - timeHeight
            let gradientTop = max(0, timeTopY - timeFontSize * 0.6)

            // 半透明黑色渐变，保证明亮背景下文字可读。
            let colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.55).cgColor]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors as CFArray,
                                         locations: [0, 1]) {
                cg.saveGState()
                cg.drawLinearGradient(gradient,
                                      start: CGPoint(x: 0, y: gradientTop),
                                      end: CGPoint(x: 0, y: h),
                                      options: [])
                cg.restoreGState()
            }

            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: max(1, timeFontSize * 0.03)),
                         blur: max(2, timeFontSize * 0.15),
                         color: UIColor.black.withAlphaComponent(0.75).cgColor)

            // 时间在上
            let timeRect = CGRect(x: x, y: timeTopY, width: maxTextWidth, height: timeHeight)
            (snapshot.timeText as NSString).draw(in: timeRect, withAttributes: timeAttributes)

            // 备注在下
            if !noteText.isEmpty {
                let noteRect = CGRect(x: x, y: noteTopY, width: maxTextWidth, height: noteHeight)
                (noteText as NSString).draw(in: noteRect, withAttributes: noteAttributes)
            }
            cg.restoreGState()
        }
    }
}
