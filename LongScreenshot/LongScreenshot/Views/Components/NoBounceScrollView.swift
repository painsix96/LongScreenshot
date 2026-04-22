import SwiftUI
import UIKit

/// 无弹性滚动的 ScrollView 包装器
/// 滑到顶部或底部时不再继续拉动
struct NoBounceScrollView<Content: View>: UIViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.bounces = false
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never

        let hostingController = UIHostingController(rootView: content)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear

        scrollView.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: scrollView.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            hostingController.view.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        if let hostingView = scrollView.subviews.first {
            let hostingController = UIHostingController(rootView: content)
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            hostingController.view.backgroundColor = .clear

            hostingView.subviews.forEach { $0.removeFromSuperview() }
            hostingView.addSubview(hostingController.view)

            NSLayoutConstraint.activate([
                hostingController.view.leadingAnchor.constraint(equalTo: hostingView.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: hostingView.trailingAnchor),
                hostingController.view.topAnchor.constraint(equalTo: hostingView.topAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: hostingView.bottomAnchor),
                hostingController.view.widthAnchor.constraint(equalTo: hostingView.widthAnchor)
            ])
        }
    }
}
