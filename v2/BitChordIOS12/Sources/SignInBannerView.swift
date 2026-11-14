import UIKit

/// The signed-out card the real Home opens with: a violet-to-crimson panel
/// with "Sign in to YouTube Music" and the white Google pill button.
final class SignInBannerView: UIView {
    static let bannerHeight: CGFloat = 114

    private let gradient = CAGradientLayer()
    private let shade = CAGradientLayer()
    var onSignIn: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        shade.frame = bounds
    }

    private func build() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 16
        layer.masksToBounds = true

        // Sampled from the real signed-out card: royal blue at the left edge
        // into indigo at the right, with the lower half pressed darker.
        gradient.colors = [UIColor(red: 0.004, green: 0.255, blue: 0.545, alpha: 1).cgColor,
                           UIColor(red: 0.188, green: 0.192, blue: 0.557, alpha: 1).cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0.35)
        gradient.endPoint = CGPoint(x: 1, y: 0.35)
        layer.addSublayer(gradient)

        shade.colors = [UIColor.clear.cgColor,
                        UIColor(white: 0, alpha: 0.22).cgColor]
        shade.startPoint = CGPoint(x: 0.5, y: 0)
        shade.endPoint = CGPoint(x: 0.5, y: 1)
        layer.addSublayer(shade)

        let title = UILabel()
        title.text = "Sign in to YouTube Music"
        title.font = Theme.font(20, weight: .semibold)
        title.textColor = .white
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)

        let button = UIButton(type: .custom)
        button.backgroundColor = .white
        button.layer.cornerRadius = 19
        button.addTarget(self, action: #selector(signInTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)

        let mark = GoogleMarkView()
        mark.translatesAutoresizingMaskIntoConstraints = false
        mark.isUserInteractionEnabled = false
        button.addSubview(mark)

        let buttonTitle = UILabel()
        buttonTitle.text = "Sign in with Google"
        buttonTitle.font = Theme.font(14, weight: .semibold)
        buttonTitle.textColor = UIColor(white: 0.15, alpha: 1)
        buttonTitle.isUserInteractionEnabled = false
        buttonTitle.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(buttonTitle)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),

            button.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14),
            button.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            button.heightAnchor.constraint(equalToConstant: 38),
            button.widthAnchor.constraint(equalToConstant: 208),

            mark.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 17),
            mark.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            mark.widthAnchor.constraint(equalToConstant: 17),
            mark.heightAnchor.constraint(equalToConstant: 17),

            buttonTitle.leadingAnchor.constraint(equalTo: mark.trailingAnchor, constant: 10),
            buttonTitle.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
    }

    @objc private func signInTapped() {
        onSignIn?()
    }
}

/// The four-stroke Google G, drawn rather than shipped as an asset so it stays
/// crisp at the 18pt it is used at.
final class GoogleMarkView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func draw(_ rect: CGRect) {
        let line: CGFloat = rect.width * 0.24
        let radius = (rect.width - line) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // A full four-colour ring, with the small opening at the top right.
        // Each segment owns an increasing-angle sweep in this flipped UIKit
        // space: red over the top, yellow at the left, green below, blue right.
        let segments: [(from: CGFloat, to: CGFloat, color: UIColor)] = [
            (218, 312, UIColor(red: 0.92, green: 0.26, blue: 0.21, alpha: 1)),
            (134, 218, UIColor(red: 0.98, green: 0.74, blue: 0.02, alpha: 1)),
            (50, 134, UIColor(red: 0.20, green: 0.66, blue: 0.33, alpha: 1)),
            (-40, 50, UIColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1))
        ]
        for segment in segments {
            let path = UIBezierPath(arcCenter: center,
                                    radius: radius,
                                    startAngle: segment.from * .pi / 180,
                                    endAngle: segment.to * .pi / 180,
                                    clockwise: true)
            path.lineWidth = line
            path.lineCapStyle = .butt
            segment.color.setStroke()
            path.stroke()
        }
        // The blue crossbar runs from the centre to the ring's right edge.
        let bar = UIBezierPath()
        bar.move(to: CGPoint(x: center.x, y: center.y))
        bar.addLine(to: CGPoint(x: rect.maxX - line / 2, y: center.y))
        bar.lineWidth = line
        bar.lineCapStyle = .butt
        segments[3].color.setStroke()
        bar.stroke()
    }
}
