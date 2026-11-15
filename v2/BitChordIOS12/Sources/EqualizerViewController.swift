import UIKit

/// The equalizer page the Settings row now opens. It has the reference preset
/// curves, seven manual bands, a stereo balance trim and a preamp. Every
/// control writes the keys the audio tap reads, so moving a fader changes the
/// next rendered buffer rather than only redrawing this screen.
final class EqualizerViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let presetButton = UIButton(type: .system)
    private let balanceSlider = UISlider()
    private let preampSlider = UISlider()
    private let balanceValue = UILabel()
    private let preampValue = UILabel()

    private var bands: [Double] = Array(repeating: 0, count: 7)
    private var faders: [EQBandFader] = []
    private var gainLabels: [UILabel] = []

    private let frequencyLabels = ["60", "150", "400", "1k", "2.5k", "6k", "14k"]
    private let manualKey = "BitChord.Audio.EqualizerManual"
    private let bandsKey = "BitChord.Audio.EqBands"
    private let balanceKey = "BitChord.Audio.EqBalance"
    private let preampKey = "BitChord.Audio.EqPreamp"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationItem.largeTitleDisplayMode = .never
        title = "Equalizer"
        loadValues()
        build()
        refreshControls()
    }

    private func loadValues() {
        let store = SettingsStore.shared
        bands = store.doubles(bandsKey, Array(AudioDSP.gains(for: "Flat").prefix(7)))
        if bands.count < 7 {
            bands += Array(repeating: 0, count: 7 - bands.count)
        }
        balanceSlider.value = Float(store.double(balanceKey, 0))
        preampSlider.value = Float(store.double(preampKey, 0))
    }

    private func build() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -30),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40)
        ])

        stack.addArrangedSubview(sectionLabel("PRESET"))
        stylePresetButton()
        stack.addArrangedSubview(presetButton)

        stack.addArrangedSubview(sectionLabel("MANUAL BANDS"))
        let hint = UILabel()
        hint.font = Theme.font(13)
        hint.textColor = Theme.secondaryText
        hint.numberOfLines = 0
        hint.text = "Drag a band to switch to Manual. Values are dB; the centre is flat."
        stack.addArrangedSubview(hint)

        let faderStack = UIStackView()
        faderStack.axis = .horizontal
        faderStack.distribution = .fillEqually
        faderStack.alignment = .fill
        faderStack.spacing = 2
        for index in 0..<7 {
            let column = UIStackView()
            column.axis = .vertical
            column.alignment = .center
            column.spacing = 4

            let gain = UILabel()
            gain.font = Theme.font(10, weight: .medium)
            gain.textColor = Theme.secondaryText
            gain.textAlignment = .center
            gain.text = "0"
            gainLabels.append(gain)
            column.addArrangedSubview(gain)

            let fader = EQBandFader()
            fader.translatesAutoresizingMaskIntoConstraints = false
            fader.tag = index
            fader.value = CGFloat(bands[index])
            fader.addTarget(self, action: #selector(faderChanged(_:)), for: .valueChanged)
            faders.append(fader)
            column.addArrangedSubview(fader)
            fader.widthAnchor.constraint(equalToConstant: 30).isActive = true
            fader.heightAnchor.constraint(equalToConstant: 176).isActive = true

            let frequency = UILabel()
            frequency.font = Theme.font(10)
            frequency.textColor = Theme.secondaryText
            frequency.textAlignment = .center
            frequency.text = frequencyLabels[index]
            column.addArrangedSubview(frequency)

            faderStack.addArrangedSubview(column)
        }
        stack.addArrangedSubview(faderStack)

        stack.addArrangedSubview(sectionLabel("BALANCE"))
        let balance = sliderRow(title: "Left / Right", valueLabel: balanceValue,
                                slider: balanceSlider, minimum: -1, maximum: 1)
        balanceSlider.addTarget(self, action: #selector(balanceChanged), for: .valueChanged)
        stack.addArrangedSubview(balance)

        stack.addArrangedSubview(sectionLabel("PREAMP"))
        let preamp = sliderRow(title: "Output trim", valueLabel: preampValue,
                               slider: preampSlider, minimum: -12, maximum: 12)
        preampSlider.addTarget(self, action: #selector(preampChanged), for: .valueChanged)
        stack.addArrangedSubview(preamp)

        let reset = UIButton(type: .system)
        reset.translatesAutoresizingMaskIntoConstraints = false
        reset.setTitle("Reset equalizer", for: .normal)
        reset.setTitleColor(Theme.primaryText, for: .normal)
        reset.titleLabel?.font = Theme.font(15, weight: .semibold)
        reset.backgroundColor = Theme.surfaceVariant
        reset.layer.cornerRadius = 12
        reset.heightAnchor.constraint(equalToConstant: 50).isActive = true
        reset.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        stack.addArrangedSubview(reset)
    }

    private func sectionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.font = Theme.font(12, weight: .semibold)
        label.textColor = Theme.secondaryText
        label.text = text
        return label
    }

    private func stylePresetButton() {
        presetButton.translatesAutoresizingMaskIntoConstraints = false
        presetButton.backgroundColor = Theme.surfaceVariant
        presetButton.layer.cornerRadius = 12
        presetButton.contentHorizontalAlignment = .left
        presetButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        presetButton.titleLabel?.font = Theme.font(16, weight: .medium)
        presetButton.setTitleColor(Theme.primaryText, for: .normal)
        presetButton.heightAnchor.constraint(equalToConstant: 52).isActive = true
        presetButton.addTarget(self, action: #selector(presetTapped), for: .touchUpInside)
    }

    private func sliderRow(title: String, valueLabel: UILabel, slider: UISlider,
                           minimum: Float, maximum: Float) -> UIView {
        let card = UIView()
        card.backgroundColor = Theme.surfaceVariant
        card.layer.cornerRadius = 12

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = Theme.font(15)
        titleLabel.textColor = Theme.primaryText
        titleLabel.text = title
        card.addSubview(titleLabel)

        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = Theme.font(13)
        valueLabel.textColor = Theme.secondaryText
        valueLabel.textAlignment = .right
        card.addSubview(valueLabel)

        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumValue = minimum
        slider.maximumValue = maximum
        slider.minimumTrackTintColor = Theme.primaryText
        slider.maximumTrackTintColor = Theme.outline
        card.addSubview(slider)

        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: 92),
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            valueLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            valueLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            slider.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            slider.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            slider.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])
        return card
    }

    private func refreshControls() {
        let store = SettingsStore.shared
        let preset = store.string("BitChord.Audio.Equalizer", "Off")
        let manual = store.bool(manualKey, false)
        let label = manual ? "Manual" : preset
        presetButton.setTitle("Preset: \(label)", for: .normal)
        for (index, fader) in faders.enumerated() {
            fader.value = CGFloat(bands[index])
            gainLabels[index].text = formattedBand(bands[index])
        }
        balanceValue.text = String(format: "%+.2f", balanceSlider.value)
        preampValue.text = String(format: "%+.1f dB", preampSlider.value)
    }

    @objc private func presetTapped() {
        let sheet = UIAlertController(title: "Equalizer preset", message: nil, preferredStyle: .actionSheet)
        for preset in AudioDSP.presets {
            sheet.addAction(UIAlertAction(title: preset, style: .default) { [weak self] _ in
                self?.apply(preset: preset)
            })
        }
        sheet.addAction(UIAlertAction(title: "Manual", style: .default) { [weak self] _ in
            self?.applyManual()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(sheet, animated: true, completion: nil)
    }

    private func apply(preset: String) {
        let store = SettingsStore.shared
        store.set(false, for: manualKey)
        store.set(preset, for: "BitChord.Audio.Equalizer")
        if preset == "Off" || preset == "Flat" {
            bands = Array(repeating: 0, count: 7)
        } else {
            bands = Array(AudioDSP.gains(for: preset).prefix(7))
            if bands.count < 7 {
                bands += Array(repeating: 0, count: 7 - bands.count)
            }
        }
        store.set(bands, for: bandsKey)
        refreshControls()
        tableViewChanged()
    }

    private func applyManual() {
        let store = SettingsStore.shared
        store.set(true, for: manualKey)
        store.set("Manual", for: "BitChord.Audio.Equalizer")
        store.set(bands, for: bandsKey)
        refreshControls()
        tableViewChanged()
    }

    @objc private func faderChanged(_ sender: EQBandFader) {
        guard sender.tag >= 0 && sender.tag < bands.count else { return }
        bands[sender.tag] = Double(sender.value)
        let store = SettingsStore.shared
        store.set(true, for: manualKey)
        store.set("Manual", for: "BitChord.Audio.Equalizer")
        store.set(bands, for: bandsKey)
        gainLabels[sender.tag].text = formattedBand(bands[sender.tag])
        presetButton.setTitle("Preset: Manual", for: .normal)
    }

    @objc private func balanceChanged() {
        SettingsStore.shared.set(Double(balanceSlider.value), for: balanceKey)
        balanceValue.text = String(format: "%+.2f", balanceSlider.value)
    }

    @objc private func preampChanged() {
        SettingsStore.shared.set(Double(preampSlider.value), for: preampKey)
        preampValue.text = String(format: "%+.1f dB", preampSlider.value)
    }

    @objc private func resetTapped() {
        let store = SettingsStore.shared
        bands = Array(repeating: 0, count: 7)
        balanceSlider.value = 0
        preampSlider.value = 0
        store.set(false, for: manualKey)
        store.set("Flat", for: "BitChord.Audio.Equalizer")
        store.set(bands, for: bandsKey)
        store.set(0.0, for: balanceKey)
        store.set(0.0, for: preampKey)
        refreshControls()
        tableViewChanged()
    }

    private func tableViewChanged() {
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }

    private func formattedBand(_ value: Double) -> String {
        return String(format: "%+.1f", value)
    }
}

/// A vertical fader drawn by hand. A rotated UISlider keeps horizontal touch
/// geometry on iOS 12, so the reference app's vertical gesture is reproduced
/// rather than approximated with a transform.
final class EQBandFader: UIControl {
    var value: CGFloat = 0 {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: 30, height: 176)
    }

    override func draw(_ rect: CGRect) {
        let top: CGFloat = 12
        let bottom = bounds.height - 12
        let x = bounds.midX
        let track = UIBezierPath()
        track.move(to: CGPoint(x: x, y: top))
        track.addLine(to: CGPoint(x: x, y: bottom))
        Theme.outline.setStroke()
        track.lineWidth = 3
        track.lineCapStyle = .round
        track.stroke()

        let mid = (top + bottom) / 2
        let knobY = y(for: value, top: top, bottom: bottom)
        let fill = UIBezierPath()
        fill.move(to: CGPoint(x: x, y: mid))
        fill.addLine(to: CGPoint(x: x, y: knobY))
        Theme.primaryText.setStroke()
        fill.lineWidth = 3
        fill.lineCapStyle = .round
        fill.stroke()

        Theme.primaryText.setFill()
        UIBezierPath(ovalIn: CGRect(x: x - 8, y: knobY - 8, width: 16, height: 16)).fill()
        Theme.background.setFill()
        UIBezierPath(ovalIn: CGRect(x: x - 3, y: knobY - 3, width: 6, height: 6)).fill()
    }

    private func y(for value: CGFloat, top: CGFloat, bottom: CGFloat) -> CGFloat {
        let normalized = (value + 12) / 24
        return bottom - normalized * (bottom - top)
    }

    private func updateValue(at point: CGPoint) {
        let top: CGFloat = 12
        let bottom = bounds.height - 12
        let normalized = (bottom - point.y) / max(1, bottom - top)
        value = max(-12, min(12, normalized * 24 - 12))
        sendActions(for: .valueChanged)
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        updateValue(at: touch.location(in: self))
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        updateValue(at: touch.location(in: self))
        return true
    }
}
