import UIKit

/// The signed-out card the real Home opens with: a violet-to-crimson panel
/// with "Sign in to YouTube Music" and the white Google pill button.
final class SignInBannerView: UIView {
    static let bannerHeight: CGFloat = 119

    private let gradient = CAGradientLayer()
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
    }

    private func build() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 16
        layer.masksToBounds = true

        // Sampled from the running app: deep violet on the left, bright
        // crimson at the top right, then darker toward the bottom edge.
        gradient.colors = [UIColor(red: 0.45, green: 0.04, blue: 0.44, alpha: 1).cgColor,
                           UIColor(red: 0.66, green: 0.09, blue: 0.35, alpha: 1).cgColor,
                           UIColor(red: 0.80, green: 0.11, blue: 0.23, alpha: 1).cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 0.25)
        layer.addSublayer(gradient)

        let title = UILabel()
        title.text = "Sign in to YouTube Music"
        title.font = Theme.font(20, weight: .semibold)
        title.textColor = .white
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)

        let button = UIButton(type: .custom)
        button.backgroundColor = .white
        button.layer.cornerRadius = 23
        button.addTarget(self, action: #selector(signInTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)

        let mark = GoogleMarkView()
        mark.translatesAutoresizingMaskIntoConstraints = false
        mark.isUserInteractionEnabled = false
        button.addSubview(mark)

        let buttonTitle = UILabel()
        buttonTitle.text = "Sign in with Google"
        buttonTitle.font = Theme.font(15, weight: .semibold)
        buttonTitle.textColor = UIColor(white: 0.15, alpha: 1)
        buttonTitle.isUserInteractionEnabled = false
        buttonTitle.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(buttonTitle)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),

            button.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14),
            button.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            button.heightAnchor.constraint(equalToConstant: 46),
            button.widthAnchor.constraint(equalToConstant: 232),

            mark.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 18),
            mark.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            mark.widthAnchor.constraint(equalToConstant: 18),
            mark.heightAnchor.constraint(equalToConstant: 18),

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
        let line: CGFloat = rect.width * 0.22
        let radius = (rect.width - line) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let colors = [UIColor(red: 0.92, green: 0.26, blue: 0.21, alpha: 1),
                      UIColor(red: 0.98, green: 0.74, blue: 0.02, alpha: 1),
                      UIColor(red: 0.20, green: 0.66, blue: 0.33, alpha: 1),
                      UIColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1)]
        // Start at the top-right gap and sweep clockwise in four arcs.
        let starts: [CGFloat] = [-45, -135, 135, 45]
        let ends: [CGFloat] = [-165, 45, 135, 30]
        for index in 0..<4 {
            let path = UIBezierPath(arcCenter: center,
                                    radius: radius,
                                    startAngle: starts[index] * .pi / 180,
                                    endAngle: ends[index] * .pi / 180,
                                    clockwise: index == 2 ? false : true)
            path.lineWidth = line
            colors[index].setStroke()
            path.stroke()
        }
        // The crossbar of the G.
        let bar = UIBezierPath()
        bar.move(to: CGPoint(x: center.x, y: center.y))
        bar.addLine(to: CGPoint(x: rect.maxX - 1, y: center.y))
        bar.lineWidth = line
        colors[3].setStroke()
        bar.stroke()
    }
}
