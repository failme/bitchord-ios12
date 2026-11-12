import io

ROOT = 'C:/Users/natha/Downloads/bitios/'
p = ROOT + 'BitChordIOS12/Sources/NowPlayingViewController.swift'
t = io.open(p, encoding='utf-8').read()


def sub(old, new):
    global t
    if old not in t:
        raise SystemExit('MISSING: %r' % (old[:70],))
    t = t.replace(old, new, 1)


# The sweep was painted white-on-white: the active row's "unsung" colour was
# already white, so the reveal clip changed nothing visible. Every row waits in
# grey; the voice turns the sung words white.
sub('''            // The active line's unsung half is white at half strength; the lines
            // around it are the panel's solid grey, not a dimmed white.
            lyricCell.dimmed = row == lyricHighlight ? .white : Theme.secondaryText''',
    '''            // Every row waits in grey; the karaoke overlay turns the words
            // white as they are sung. Painting the active row white up front
            // would hide the sweep entirely.
            lyricCell.dimmed = Theme.secondaryText''')

# Row 0 lit up from 0:00 even when the voice enters half a minute in. Nothing
# is active until its time arrives, as on the real panel.
sub('''        guard lyricsSynced, !currentLyrics.isEmpty else { return }
        var index = 0
        for (offset, line) in currentLyrics.enumerated() {
            if line.time <= position {
                index = offset
            } else {
                break
            }
        }
        if index != lyricHighlight {
            lyricHighlight = index
            // The active line is set larger, so its measured height is stale.
            lyricHeights.removeAll()
            lyricsTable.reloadData()
            if !userScrolling {
                lyricsTable.scrollToRow(at: IndexPath(row: index, section: 0), at: .middle, animated: true)
            }
            return
        }''',
    '''        guard lyricsSynced, !currentLyrics.isEmpty else { return }
        var index = -1
        for (offset, line) in currentLyrics.enumerated() {
            if line.time <= position {
                index = offset
            } else {
                break
            }
        }
        if index != lyricHighlight {
            lyricHighlight = index
            // The active line is set larger, so its measured height is stale.
            lyricHeights.removeAll()
            lyricsTable.reloadData()
            if index >= 0, !userScrolling {
                lyricsTable.scrollToRow(at: IndexPath(row: index, section: 0), at: .middle, animated: true)
            }
            return
        }''')

io.open(p, 'w', encoding='utf-8', newline='').write(t)
print('ok karaoke')
