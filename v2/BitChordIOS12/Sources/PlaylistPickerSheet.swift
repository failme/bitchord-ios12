import UIKit

/// The real app's add-to-playlist surface: a full-height sheet with a close
/// cross, a tick to confirm, the track it came from, and a row of tickable
/// playlists. Upstream creates a playlist inside the same sheet, so the create
/// form swaps places with the list instead of raising a system alert.
final class PlaylistPickerSheetViewController: UIViewController {
    private let track: Track
    private let playlists: [Playlist]
    private let onAdd: (Set<String>) -> Void
    private let onCreate: (String) -> Void

    private let content = UIView()
    private let bar = UIView()
    private let closeButton = UIButton(type: .custom)
    private let confirmButton = UIButton(type: .custom)
    private let barTitle = UILabel()
    private let barSubtitle = UILabel()
    private let barDivider = UIView()
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let emptyLabel = UILabel()
    private let form = UIView()
    private let fieldHolder = UIView()
    private let field = UITextField()
    private let clearButton = UIButton(type: .custom)

    private var selected = Set<String>()
    private var creating = false
    private var placed = false
    private var closing = false
    private var opened = false

    init(track: Track, playlists: [Playlist],
         onAdd: @escaping (Set<String>) -> Void,
         onCreate: @escaping (String) -> Void) {
        self.track = track
        self.playlists = playlists
        self.onAdd = onAdd
        self.onCreate = onCreate
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalPresentationCapturesStatusBarAppearance = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var preferredStatusBarStyle: UIStatusBarStyle { return .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        view.isOpaque = true
        content.backgroundColor = Theme.background
        view.addSubview(content)

        bar.addSubview(closeButton)
        closeButton.setImage(Icons.image(.close, size: 20), for: .normal)
        closeButton.tintColor = Theme.primaryText
        closeButton.addTarget(self, action: #selector(leadingTapped), for: .touchUpInside)

        confirmButton.setImage(Icons.image(.check, size: 23), for: .normal)
        confirmButton.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)
        confirmButton.accessibilityLabel = "Add to playlist"
        bar.addSubview(confirmButton)

        barTitle.text = "New playlist"
        barTitle.font = Theme.font(17, weight: .semibold)
        barTitle.textColor = Theme.primaryText
        barTitle.isHidden = true
        bar.addSubview(barTitle)

        barSubtitle.text = "Saved on this device"
        barSubtitle.font = Theme.font(13)
        barSubtitle.textColor = Theme.secondaryText
        barSubtitle.isHidden = true
        bar.addSubview(barSubtitle)

        barDivider.backgroundColor = Theme.outline
        content.addSubview(bar)
        content.addSubview(barDivider)

        content.addSubview(scroll)
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 0
        scroll.addSubview(stack)

        buildList()

        content.addSubview(form)
        form.isHidden = true
        buildForm()

        updateConfirm()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        content.frame = view.bounds
        guard !placed, view.bounds.width > 0 else { return }
        placed = true

        let top = view.safeAreaInsets.top + 4
        bar.frame = CGRect(x: 0, y: top, width: view.bounds.width, height: 48)
        closeButton.frame = CGRect(x: 8, y: 2, width: 44, height: 44)
        confirmButton.frame = CGRect(x: view.bounds.width - 52, y: 2, width: 44, height: 44)
        barTitle.frame = CGRect(x: 58, y: 5, width: view.bounds.width - 116, height: 21)
        barSubtitle.frame = CGRect(x: 58, y: 25, width: view.bounds.width - 116, height: 17)
        barDivider.frame = CGRect(x: 0, y: bar.frame.maxY, width: view.bounds.width, height: 0.5)

        form.frame = CGRect(x: 0, y: bar.frame.maxY + 0.5,
                            width: view.bounds.width, height: view.bounds.height - bar.frame.maxY)
        layoutForm()

        scroll.frame = CGRect(x: 0, y: bar.frame.maxY + 0.5,
                              width: view.bounds.width, height: view.bounds.height - bar.frame.maxY)
        layoutList()

        content.transform = CGAffineTransform(translationX: 0, y: view.bounds.height)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !opened else { return }
        opened = true
        let animator = UIViewPropertyAnimator(duration: 0.34, dampingRatio: 0.92) {
            self.content.transform = .identity
        }
        animator.startAnimation()
    }

    // MARK: - List

    private func buildList() {
        stack.addArrangedSubview(TrackSheetHeader(track: track))

        let heading = UILabel()
        heading.text = "ADD TO PLAYLIST"
        heading.font = Theme.font(12, weight: .semibold)
        heading.textColor = Theme.secondaryText
        heading.translatesAutoresizingMaskIntoConstraints = false
        let headingHolder = UIView()
        headingHolder.addSubview(heading)
        NSLayoutConstraint.activate([
            headingHolder.heightAnchor.constraint(equalToConstant: 32),
            heading.leadingAnchor.constraint(equalTo: headingHolder.leadingAnchor, constant: 22),
            heading.bottomAnchor.constraint(equalTo: headingHolder.bottomAnchor, constant: -4),
        ])
        stack.addArrangedSubview(headingHolder)

        let newRow = SheetActionRow(title: "New playlist", icon: .plus)
        newRow.onTap = { [weak self] in self?.showCreateForm() }
        stack.addArrangedSubview(newRow)

        let rule = UIView()
        rule.backgroundColor = Theme.outline
        let ruleHolder = UIView()
        rule.translatesAutoresizingMaskIntoConstraints = false
        ruleHolder.addSubview(rule)
        NSLayoutConstraint.activate([
            ruleHolder.heightAnchor.constraint(equalToConstant: 13),
            rule.leadingAnchor.constraint(equalTo: ruleHolder.leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: ruleHolder.trailingAnchor),
            rule.centerYAnchor.constraint(equalTo: ruleHolder.centerYAnchor),
            rule.heightAnchor.constraint(equalToConstant: 0.5),
        ])
        stack.addArrangedSubview(ruleHolder)

        if playlists.isEmpty {
            emptyLabel.text = "No playlists yet"
            emptyLabel.font = Theme.font(14)
            emptyLabel.textColor = Theme.secondaryText
            let holder = UIView()
            emptyLabel.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(emptyLabel)
            NSLayoutConstraint.activate([
                holder.heightAnchor.constraint(equalToConstant: 66),
                emptyLabel.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 22),
                emptyLabel.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
            ])
            stack.addArrangedSubview(holder)
        } else {
            for playlist in playlists {
                let row = PlaylistPickRow(playlist: playlist)
                row.onTap = { [weak self] in self?.toggle(playlist.id) }
                stack.addArrangedSubview(row)
            }
        }
    }

    private func layoutList() {
        let width = view.bounds.width
        stack.frame = CGRect(x: 0, y: 0, width: width, height: 0)
        stack.layoutIfNeeded()
        let fit = stack.systemLayoutSizeFitting(CGSize(width: width, height: 0),
                                                withHorizontalFittingPriority: .required,
                                                verticalFittingPriority: .fittingSizeLevel)
        stack.frame = CGRect(x: 0, y: 0, width: width, height: fit.height)
        scroll.contentSize = CGSize(width: width, height: fit.height + view.safeAreaInsets.bottom)
    }

    private func toggle(_ id: String) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
        for case let row as PlaylistPickRow in stack.arrangedSubviews {
            row.setPicked(selected.contains(row.playlistID))
        }
        UISelectionFeedbackGenerator().selectionChanged()
        updateConfirm()
    }

    private func updateConfirm() {
        let name = (field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let enabled = creating ? !name.isEmpty : !selected.isEmpty
        confirmButton.isEnabled = enabled
        confirmButton.tintColor = enabled ? UIColor.white : UIColor(white: 1, alpha: 0.30)
    }

    @objc private func confirmTapped() {
        if creating {
            submitCreate()
            return
        }
        guard !selected.isEmpty else { return }
        let chosen = selected
        let add = onAdd
        close { add(chosen) }
    }

    // MARK: - Create form

    private func buildForm() {
        fieldHolder.backgroundColor = Theme.surfaceVariant
        fieldHolder.layer.cornerRadius = 11
        form.addSubview(fieldHolder)

        field.attributedPlaceholder = NSAttributedString(
            string: "Playlist name",
            attributes: [.foregroundColor: Theme.secondaryText,
                         .font: Theme.font(17)])
        field.font = Theme.font(17)
        field.textColor = Theme.primaryText
        field.tintColor = Theme.primaryText
        field.returnKeyType = .done
        field.autocapitalizationType = .words
        field.delegate = self
        field.addTarget(self, action: #selector(fieldChanged), for: .editingChanged)
        fieldHolder.addSubview(field)

        clearButton.setImage(Icons.image(.close, size: 13), for: .normal)
        clearButton.tintColor = Theme.secondaryText
        clearButton.isHidden = true
        clearButton.addTarget(self, action: #selector(clearField), for: .touchUpInside)
        fieldHolder.addSubview(clearButton)
    }

    private func layoutForm() {
        guard form.bounds.width > 0 else { return }
        fieldHolder.frame = CGRect(x: 22, y: 16, width: form.bounds.width - 44, height: 48)
        field.frame = CGRect(x: 12, y: 0, width: fieldHolder.bounds.width - 52, height: 48)
        clearButton.frame = CGRect(x: fieldHolder.bounds.width - 40, y: 10, width: 28, height: 28)
    }

    private func showCreateForm() {
        creating = true
        scroll.isHidden = true
        form.isHidden = false
        barTitle.isHidden = false
        barSubtitle.isHidden = false
        closeButton.setImage(Icons.image(.chevronLeft, size: 20), for: .normal)
        confirmButton.accessibilityLabel = "Create playlist"
        updateConfirm()
        field.becomeFirstResponder()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func hideCreateForm() {
        creating = false
        field.resignFirstResponder()
        form.isHidden = true
        scroll.isHidden = false
        barTitle.isHidden = true
        barSubtitle.isHidden = true
        closeButton.setImage(Icons.image(.close, size: 20), for: .normal)
        confirmButton.accessibilityLabel = "Add to playlist"
        updateConfirm()
    }

    @objc private func fieldChanged() {
        clearButton.isHidden = field.text?.isEmpty ?? true
        updateConfirm()
    }

    @objc private func clearField() {
        field.text = ""
        fieldChanged()
    }

    @objc private func leadingTapped() {
        if creating {
            hideCreateForm()
        } else {
            close()
        }
    }

    private func submitCreate() {
        let name = (field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        field.resignFirstResponder()
        let create = onCreate
        close { create(name) }
    }

    private func close(then completion: (() -> Void)? = nil) {
        guard !closing else { return }
        closing = true
        view.endEditing(true)
        UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseIn], animations: {
            self.content.transform = CGAffineTransform(translationX: 0, y: self.view.bounds.height)
        }, completion: { _ in
            self.dismiss(animated: false, completion: completion)
        })
    }
}

extension PlaylistPickerSheetViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        submitCreate()
        return true
    }
}

extension PlaylistPickerSheetViewController: UIGestureRecognizerDelegate {}

private final class TrackSheetHeader: UIView {
    init(track: Track) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let art = UIImageView()
        art.backgroundColor = Theme.surfaceVariant
        art.layer.cornerRadius = 8
        art.layer.masksToBounds = true
        art.contentMode = .scaleAspectFill
        art.translatesAutoresizingMaskIntoConstraints = false
        addSubview(art)
        loadArtwork(track.artworkURL, into: art)

        let title = UILabel()
        title.text = track.title
        title.font = Theme.font(16, weight: .semibold)
        title.textColor = Theme.primaryText
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = UILabel()
        subtitle.text = track.artist
        subtitle.font = Theme.font(14)
        subtitle.textColor = Theme.secondaryText
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        addSubview(title)
        addSubview(subtitle)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 72),
            art.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            art.centerYAnchor.constraint(equalTo: centerYAnchor),
            art.widthAnchor.constraint(equalToConstant: 52),
            art.heightAnchor.constraint(equalToConstant: 52),
            title.leadingAnchor.constraint(equalTo: art.trailingAnchor, constant: 14),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            title.bottomAnchor.constraint(equalTo: centerYAnchor, constant: 1),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            subtitle.topAnchor.constraint(equalTo: centerYAnchor, constant: 3),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class SheetActionRow: UIControl {
    var onTap: (() -> Void)?
    private let highlight = UIView()

    init(title: String, icon: Icons.Kind) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        highlight.backgroundColor = UIColor(white: 1, alpha: 0.07)
        highlight.isUserInteractionEnabled = false
        highlight.alpha = 0
        addSubview(highlight)

        let glyph = UIImageView(image: Icons.image(icon, size: 22))
        glyph.tintColor = Theme.primaryText
        glyph.translatesAutoresizingMaskIntoConstraints = false
        let label = UILabel()
        label.text = title
        label.font = Theme.font(17)
        label.textColor = Theme.primaryText
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph)
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 56),
            glyph.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: 22),
            glyph.heightAnchor.constraint(equalToConstant: 22),
            label.leadingAnchor.constraint(equalTo: glyph.trailingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -22),
        ])
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        addTarget(self, action: #selector(pressed), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(released), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        highlight.frame = bounds.insetBy(dx: 8, dy: 2)
    }

    @objc private func tapped() { onTap?() }
    @objc private func pressed() { highlight.alpha = 1 }
    @objc private func released() { highlight.alpha = 0 }
}

private final class PlaylistPickRow: UIControl {
    let playlistID: String
    var onTap: (() -> Void)?
    private let highlight = UIView()
    private let tick = UIImageView()
    private let art = UIImageView()

    init(playlist: Playlist) {
        playlistID = playlist.id
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        highlight.backgroundColor = UIColor(white: 1, alpha: 0.07)
        highlight.isUserInteractionEnabled = false
        highlight.alpha = 0
        addSubview(highlight)

        art.backgroundColor = Theme.surfaceVariant
        art.layer.cornerRadius = 7
        art.layer.masksToBounds = true
        art.contentMode = .scaleAspectFill
        art.translatesAutoresizingMaskIntoConstraints = false
        loadArtwork(playlist.coverURL, into: art)

        let title = UILabel()
        title.text = playlist.title
        title.font = Theme.font(16)
        title.textColor = Theme.primaryText
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = UILabel()
        let count = playlist.tracks.count
        subtitle.text = count == 1 ? "1 song" : "\(count) songs"
        subtitle.font = Theme.font(14)
        subtitle.textColor = Theme.secondaryText
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        tick.contentMode = .scaleAspectFit
        tick.translatesAutoresizingMaskIntoConstraints = false
        setPicked(false)

        addSubview(art)
        addSubview(title)
        addSubview(subtitle)
        addSubview(tick)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 60),
            art.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            art.centerYAnchor.constraint(equalTo: centerYAnchor),
            art.widthAnchor.constraint(equalToConstant: 44),
            art.heightAnchor.constraint(equalToConstant: 44),
            title.leadingAnchor.constraint(equalTo: art.trailingAnchor, constant: 16),
            title.trailingAnchor.constraint(lessThanOrEqualTo: tick.leadingAnchor, constant: -12),
            title.bottomAnchor.constraint(equalTo: centerYAnchor, constant: 1),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: tick.leadingAnchor, constant: -12),
            subtitle.topAnchor.constraint(equalTo: centerYAnchor, constant: 2),
            tick.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            tick.centerYAnchor.constraint(equalTo: centerYAnchor),
            tick.widthAnchor.constraint(equalToConstant: 24),
            tick.heightAnchor.constraint(equalToConstant: 24),
        ])
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        addTarget(self, action: #selector(pressed), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(released), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setPicked(_ picked: Bool) {
        tick.image = Icons.image(picked ? .checkCircle : .circle, size: 24)
        tick.tintColor = picked ? Theme.primaryText : Theme.secondaryText
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        highlight.frame = bounds.insetBy(dx: 8, dy: 1)
    }

    @objc private func tapped() { onTap?() }
    @objc private func pressed() { highlight.alpha = 1 }
    @objc private func released() { highlight.alpha = 0 }
}

/// Sheet artwork is small and optional; one request per row is enough.
private func loadArtwork(_ url: URL?, into imageView: UIImageView) {
    guard let url = url else { return }
    URLSession.shared.dataTask(with: url) { data, _, _ in
        guard let data = data, let image = UIImage(data: data) else { return }
        DispatchQueue.main.async {
            imageView.image = image
        }
    }.resume()
}
