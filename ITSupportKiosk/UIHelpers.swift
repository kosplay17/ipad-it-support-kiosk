import UIKit
import UIKit.UIGestureRecognizerSubclass
import WebKit

/// Сообщает о любом касании экрана, не мешая веб-странице и кнопкам обрабатывать его.
final class ActivityGestureRecognizer: UIGestureRecognizer {
    private let onActivity: () -> Void

    init(onActivity: @escaping () -> Void) {
        self.onActivity = onActivity
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onActivity()
        state = .failed
    }
}

/// WKUserContentController держит обработчик сильной ссылкой.
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

final class ToastLabel: UILabel {
    private let insets = UIEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + insets.left + insets.right,
            height: size.height + insets.top + insets.bottom
        )
    }
}
