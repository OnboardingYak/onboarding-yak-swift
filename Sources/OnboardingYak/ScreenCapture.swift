#if DEBUG && canImport(UIKit) && !os(watchOS)
import UIKit

/// Draws the app's own key window as a small JPEG. Debug builds only; it needs no permission.
@MainActor
enum ScreenCapture {
    static func jpegBase64(width: CGFloat) -> String? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first, window.bounds.width > 0, window.bounds.height > 0 else { return nil }
        let size = CGSize(width: width, height: (width * window.bounds.height / window.bounds.width).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            window.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: false)
        }
        return image.jpegData(compressionQuality: 0.7)?.base64EncodedString()
    }
}
#endif
