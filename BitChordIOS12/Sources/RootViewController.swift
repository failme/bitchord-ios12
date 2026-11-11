import UIKit

final class RootViewController: UIViewController {
    private let navigation: UINavigationController
    private let miniBar = MiniPlayerBar()
    private var miniBarHeight: NSLayoutConstraint!
    private let miniBarHeightValue: CGFloat = 56

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        navigation = UINavigationController(rootViewController: SearchViewController())
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    required init?(coder: NSCoder) {
        navigation = UINavigationController(rootViewController: SearchViewController())
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        addChild(navigation)
        navigation.view.translatesAutoresizingMaskIntoConstraints = false
        navigation.view.backgroundColor = Theme.background
        view.addSubview(navigation.view)
        navigation.didMove(toParent: self)

        miniBar.translatesAutoresizingMaskIntoConstraints = false
        miniBar.onTap = { [weak self] in
            self?.presentNowPlaying()
        }
        view.addSubview(miniBar)

        miniBarHeight = miniBar.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            navigation.view.topAnchor.constraint(equalTo: view.topAnchor),
            navigation.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigation.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navigation.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            miniBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            miniBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            miniBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            miniBarHeight
        ])

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(playerChanged),
                                               name: .playerDidChange,
                                               object: nil)
        playerChanged()
    }

    @objc private func playerChanged() {
        let visible = PlayerService.shared.currentTrack != nil
        let height = visible ? miniBarHeightValue : 0
        miniBar.isHidden = !visible
        miniBarHeight.constant = height
        miniBar.refresh()
        navigation.additionalSafeAreaInsets.bottom = height
    }

    func presentNowPlaying() {
        guard PlayerService.shared.currentTrack != nil else { return }
        if presentedViewController is NowPlayingViewController { return }
        let controller = NowPlayingViewController()
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true, completion: nil)
    }
}
