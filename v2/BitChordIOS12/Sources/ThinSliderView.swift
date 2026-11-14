import UIKit

/// Upstream's `ThinSlider`: a hairline capsule with no thumb knob that thickens
/// while a finger is down and settles back when it lifts.
///
/// The track is drawn at `activeHeight` and scaled vertically, so the rounded
/// ends keep the pill shape at both thicknesses and the progress fill can be a
/// single rounded rect rather than a knob plus a line.
final class ThinSliderView: UIControl {
    var idleHeight: CGFloat = 7 {
        didSet { updateThickness(animated: false) }
    }
    var activeHeight: CGFloat = 12 {
        didSet { updateThickness(animated: false) }
    }
    var value: Float = 0 {
        didSet {
            let clamped = min(1, max(0, value))
            if value != clamped { value = clamped; return }
            updateFill()
        }
    }

    var onTrackingBegan: (() -> Void)?
    var onValueChange: ((Float) -> Void)?
    var onValueChangeFinished: ((Float) -> Void)?

    private let bar = UIView()
    private let inactiveLayer = CAShapeLayer()
    private let activeLayer = CAShapeLayer()
    private var dragging = false
    private var currentScale: CGFloat = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false
        isAccessibilityElement = true
        accessibilityTraits = .adjustable

        bar.isUserInteractionEnabled = false
        inactiveLayer.fillColor = UIColor.white.withAlphaComponent(0.26).cgColor
        activeLayer.fillColor = UIColor.white.withAlphaComponent(0.92).cgColor
        bar.layer.addSublayer(inactiveLayer)
        bar.layer.addSublayer(activeLayer)
        addSubview(bar)
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: activeHeight + 22)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = max(1, activeHeight)
        bar.frame = CGRect(x: 0, y: (bounds.height - height) / 2,
                           width: bounds.width, height: height)
        inactiveLayer.frame = bar.bounds
        activeLayer.frame = bar.bounds

        let radius = height / 2
        inactiveLayer.path = UIBezierPath(roundedRect: bar.bounds,
                                          cornerRadius: radius).cgPath
        updateThickness(animated: false)
        bar.layer.transform = CATransform3DMakeScale(1, currentScale, 1)
        updateFill()
    }

    private func updateFill() {
        guard bar.bounds.width > 0 else { return }
        let width = max(0, min(1, CGFloat(value))) * bar.bounds.width
        guard width > 0.01 else {
            activeLayer.path = nil
            return
        }
        let rect = CGRect(x: 0, y: 0, width: width, height: bar.bounds.height)
        activeLayer.path = UIBezierPath(roundedRect: rect,
                                        cornerRadius: min(bar.bounds.height / 2, width / 2)).cgPath
    }

    private func updateThickness(animated: Bool) {
        let ratio = activeHeight > 0 ? max(0.1, idleHeight / activeHeight) : 1
        let target = dragging ? 1 : ratio
        guard target != currentScale else { return }
        let previous = currentScale
        currentScale = target
        bar.layer.transform = CATransform3DMakeScale(1, target, 1)
        guard animated else { return }

        let spring = CASpringAnimation(keyPath: "transform.scale.y")
        spring.fromValue = previous
        spring.toValue = target
        spring.mass = 1
        spring.stiffness = 240
        spring.damping = 20
        spring.duration = spring.settlingDuration
        bar.layer.add(spring, forKey: "thinSliderThickness")
    }

    // MARK: - Tracking

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        dragging = true
        onTrackingBegan?()
        updateThickness(animated: true)
        updateValue(for: touch)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        updateValue(for: touch)
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        dragging = false
        updateThickness(animated: true)
        if let touch = touch {
            updateValue(for: touch, notify: false)
        }
        onValueChangeFinished?(value)
    }

    override func cancelTracking(with event: UIEvent?) {
        dragging = false
        updateThickness(animated: true)
        onValueChangeFinished?(value)
    }

    private func updateValue(for touch: UITouch, notify: Bool = true) {
        guard bounds.width > 0 else { return }
        let x = touch.location(in: self).x
        value = Float(min(1, max(0, x / bounds.width)))
        if notify { onValueChange?(value) }
    }

}
