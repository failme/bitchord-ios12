import io

ROOT = 'C:/Users/natha/Downloads/bitios/'


def rw(p, pairs):
    path = ROOT + p
    t = io.open(path, encoding='utf-8').read()
    for old, new in pairs:
        if old not in t:
            raise SystemExit('MISSING in %s: %r' % (p, old[:70]))
        t = t.replace(old, new)
    io.open(path, 'w', encoding='utf-8', newline='').write(t)
    print('ok', p)


# --- project: compile the asset catalog and take AppIcon from it -----------
rw('project.yml', [
    ('''    sources:
      - path: BitChordIOS12/Sources''',
     '''    sources:
      - path: BitChordIOS12/Sources
      - path: BitChordIOS12/Resources'''),
    ('''        INFOPLIST_FILE: BitChordIOS12/Info.plist''',
     '''        INFOPLIST_FILE: BitChordIOS12/Info.plist
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon'''),
])

# --- Home header: the real mark instead of a redrawn approximation ---------
rw('BitChordIOS12/Sources/HomeViewController.swift', [
    ('''        let logo = UIImageView(image: Icons.image(.logo, size: 30))
        logo.tintColor = Theme.primaryText
        logo.translatesAutoresizingMaskIntoConstraints = false''',
     '''        // The app's own artwork, rasterised from its shipped SVG rather than
        // redrawn by hand.
        let logo = UIImageView(image: UIImage(named: "BrandLogo") ?? Icons.image(.logo, size: 30))
        logo.tintColor = Theme.primaryText
        logo.contentMode = .scaleAspectFit
        logo.translatesAutoresizingMaskIntoConstraints = false'''),
    ('''            logo.widthAnchor.constraint(equalToConstant: 34),
            logo.heightAnchor.constraint(equalToConstant: 34),''',
     '''            logo.widthAnchor.constraint(equalToConstant: 42),
            logo.heightAnchor.constraint(equalToConstant: 28),'''),
])

# --- Info.plist: name the icon set for iOS 11 and later --------------------
rw('BitChordIOS12/Info.plist', [
    ('''\t<key>CFBundleInfoDictionaryVersion</key>''',
     '''\t<key>CFBundleIconName</key>
\t<string>AppIcon</string>
\t<key>CFBundleInfoDictionaryVersion</key>'''),
])

# --- Launch screen: the real mark centred on the app's dark background -----
rw('BitChordIOS12/Sources/LaunchScreen.storyboard', [
    ('''                        <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
                        <color key="backgroundColor"''',
     '''                        <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
                        <subviews>
                            <imageView userInteractionEnabled="NO" contentMode="scaleAspectFit" horizontalHuggingPriority="251" verticalHuggingPriority="251" image="BrandLogo" translatesAutoresizingMaskIntoConstraints="NO" id="BcL-g1-mark">
                                <rect key="frame" x="167" y="422" width="80" height="53"/>
                                <color key="tintColor" white="1" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>
                                <constraints>
                                    <constraint firstAttribute="width" constant="80" id="BcL-w1"/>
                                    <constraint firstAttribute="height" constant="53" id="BcL-h1"/>
                                </constraints>
                            </imageView>
                        </subviews>
                        <color key="backgroundColor"'''),
    ('''                        <viewLayoutGuide key="safeArea" id="6Tk-OE-BBY"/>''',
     '''                        <viewLayoutGuide key="safeArea" id="6Tk-OE-BBY"/>
                        <constraints>
                            <constraint firstItem="BcL-g1-mark" firstAttribute="centerX" secondItem="Ze5-6b-2t3" secondAttribute="centerX" id="BcL-cx"/>
                            <constraint firstItem="BcL-g1-mark" firstAttribute="centerY" secondItem="Ze5-6b-2t3" secondAttribute="centerY" id="BcL-cy"/>
                        </constraints>'''),
])

# --- version bump ---------------------------------------------------------
y = ROOT + 'project.yml'
t = io.open(y, encoding='utf-8').read()
t = t.replace('MARKETING_VERSION: "1.15"', 'MARKETING_VERSION: "1.16"')
t = t.replace('CURRENT_PROJECT_VERSION: "16"', 'CURRENT_PROJECT_VERSION: "17"')
io.open(y, 'w', encoding='utf-8', newline='').write(t)
print('version 1.16 (17)')
