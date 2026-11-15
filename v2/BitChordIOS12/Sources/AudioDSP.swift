import AVFoundation
import Foundation
import MediaToolbox

/// Real-time processing for the native AVPlayer path.
///
/// `MTAudioProcessingTap` is the only public way to touch samples while
/// AVPlayer owns the stream. The tap renders a ten-band peaking EQ, optional
/// loudness gain, optional stereo widening and a silence flag for Skip silence.
/// It is installed only when at least one of those settings is on, so the
/// default path stays untouched.
final class AudioDSP {
    static let shared = AudioDSP()

    struct Config {
        var equalizer: String = "Off"
        var loudness = false
        var spatial = false
        var skipSilence = false

        var enabled: Bool {
            return equalizer != "Off" || loudness || spatial || skipSilence
        }

        var gains: [Double] {
            switch equalizer {
            case "Bass": return [7, 6, 5, 3, 1, 0, 0, 0, 0, 0]
            case "Vocal": return [-1, 0, 1, 3, 5, 5, 3, 1, 0, -1]
            case "Treble": return [0, 0, 0, 0, 0, 1, 3, 5, 6, 7]
            default: return Array(repeating: 0, count: 10)
            }
        }
    }

    private(set) var tapAttached = false
    private(set) var processedFrames: Int64 = 0
    private(set) var lastRMS: Float = 0
    private(set) var lastGain: Float = 1
    private(set) var silenceSkips: Int = 0
    private(set) var lastError = ""

    private var config = Config()
    private var item: AVPlayerItem?
    private weak var asset: AVURLAsset?
    private var tap: MTAudioProcessingTap?
    private var sampleRate: Double = 44100
    private var channels: Int = 2
    private var leftBands = [Biquad](repeating: Biquad(), count: 10)
    private var rightBands = [Biquad](repeating: Biquad(), count: 10)
    private var silentFrames: Int64 = 0
    private var skipRequested = false
    private let lock = NSLock()

    private init() {
        refreshConfig()
        NotificationCenter.default.addObserver(
            forName: .settingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.settingsChanged()
        }
    }

    /// Called by the native player after creating an item. Track loading is
    /// async for remote HLS/MP4 assets, so the tap is installed when the audio
    /// track list is available and again on the first ready-to-play tick.
    func attach(to item: AVPlayerItem, asset: AVURLAsset) {
        self.item = item
        self.asset = asset
        tapAttached = false
        lastError = ""
        refreshConfig()
        guard config.enabled else {
            item.audioMix = nil
            return
        }
        loadTrackAndInstall()
    }

    func detach() {
        item?.audioMix = nil
        item = nil
        asset = nil
        tap = nil
        tapAttached = false
    }

    private func loadTrackAndInstall() {
        guard let asset = asset, let item = item else { return }
        asset.loadValuesAsynchronously(forKeys: ["tracks"]) { [weak self, weak item, weak asset] in
            guard let self = self, let item = item, let asset = asset else { return }
            let track = asset.tracks(withMediaType: .audio).first
            DispatchQueue.main.async {
                self.install(track: track, on: item)
            }
        }
    }

    private func install(track: AVAssetTrack?, on item: AVPlayerItem) {
        guard config.enabled else { return }
        guard let track = track else {
            lastError = "no audio track exposed for processing"
            return
        }
        if tapAttached, item.audioMix != nil { return }

        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passUnretained(self).toOpaque(),
            init: audioTapInit,
            finalize: audioTapFinalize,
            prepare: audioTapPrepare,
            unprepare: audioTapUnprepare,
            process: audioTapProcess
        )
        var created: Unmanaged<MTAudioProcessingTap>?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault,
                                                &callbacks,
                                                kMTAudioProcessingTapCreationFlag_PostEffects,
                                                &created)
        guard status == noErr, let created = created else {
            lastError = "tap create failed (\(status))"
            return
        }
        let tap = created.takeRetainedValue()
        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        item.audioMix = mix
        self.tap = tap
        tapAttached = true
        lastError = ""
    }

    private func settingsChanged() {
        refreshConfig()
        guard let item = item else { return }
        if config.enabled {
            if !tapAttached { loadTrackAndInstall() }
        } else if tapAttached {
            item.audioMix = nil
            tap = nil
            tapAttached = false
        }
    }

    private func refreshConfig() {
        let store = SettingsStore.shared
        let next = Config(
            equalizer: store.string("BitChord.Audio.Equalizer", "Off"),
            loudness: store.bool("BitChord.Audio.LoudnessNormalization", false),
            spatial: store.bool("BitChord.Audio.SpatialAudio", false),
            skipSilence: store.bool("BitChord.Audio.SkipSilence", false)
        )
        lock.lock()
        config = next
        lock.unlock()
    }

    private func currentConfig() -> Config {
        lock.lock()
        defer { lock.unlock() }
        return config
    }

    // MARK: - Tap callbacks

    fileprivate func prepare(format: AudioStreamBasicDescription) {
        sampleRate = format.mSampleRate > 0 ? format.mSampleRate : 44100
        channels = max(1, Int(format.mChannelsPerFrame))
        let gains = currentConfig().gains
        let frequencies = [31.0, 62.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0]
        leftBands = frequencies.enumerated().map { index, frequency in
            Biquad(frequency: min(frequency, sampleRate * 0.45),
                   gain: gains[index], sampleRate: sampleRate)
        }
        rightBands = leftBands
        processedFrames = 0
        silentFrames = 0
        skipRequested = false
    }

    fileprivate func process(bufferList: UnsafeMutablePointer<AudioBufferList>,
                             frames: CMItemCount) {
        let config = currentConfig()
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        guard buffers.count > 0 else { return }
        let frameCount = Int(frames)
        guard frameCount > 0 else { return }
        let nonInterleaved = buffers.count > 1
        var rms: Float = 0
        if nonInterleaved, buffers.count >= 2,
           let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
           let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) {
            rms = renderStereo(left, right, frames: frameCount, config: config)
        } else if let data = buffers[0].mData?.assumingMemoryBound(to: Float.self) {
            let channels = max(1, Int(buffers[0].mNumberChannels))
            rms = renderInterleaved(data, frames: frameCount, channels: channels, config: config)
        }
        processedFrames += Int64(frameCount)
        lastRMS = rms
        if config.skipSilence {
            if rms < 0.0025 {
                silentFrames += Int64(frameCount)
                if Double(silentFrames) > sampleRate * 1.2 {
                    lock.lock()
                    skipRequested = true
                    lock.unlock()
                }
            } else {
                silentFrames = 0
            }
        }
    }

    fileprivate func unprepare() {
        tapAttached = false
    }

    // MARK: - Rendering

    private func renderStereo(_ left: UnsafeMutablePointer<Float>,
                              _ right: UnsafeMutablePointer<Float>,
                              frames: Int,
                              config: Config) -> Float {
        let gains = config.gains
        var sum: Float = 0
        for frame in 0..<frames {
            var l = left[frame]
            var r = right[frame]
            if config.equalizer != "Off" {
                for band in 0..<10 {
                    l = leftBands[band].process(l, gain: gains[band])
                    r = rightBands[band].process(r, gain: gains[band])
                }
            }
            sum += (l * l + r * r) * 0.5
        }
        let rms = sqrt(sum / Float(max(1, frames)))
        let gain = config.loudness ? loudnessGain(rms) : 1
        let width: Float = config.spatial ? 1.45 : 1.0
        for frame in 0..<frames {
            var l = left[frame] * gain
            var r = right[frame] * gain
            if config.spatial {
                let mid = (l + r) * 0.5
                let side = (l - r) * 0.5 * width
                l = mid + side
                r = mid - side
            }
            left[frame] = l
            right[frame] = r
        }
        lastGain = gain
        return rms * gain
    }

    private func renderInterleaved(_ data: UnsafeMutablePointer<Float>,
                                   frames: Int,
                                   channels: Int,
                                   config: Config) -> Float {
        let gains = config.gains
        var sum: Float = 0
        for frame in 0..<frames {
            for channel in 0..<channels {
                let index = frame * channels + channel
                var sample = data[index]
                if config.equalizer != "Off" {
                    if channel == 1 {
                        for band in 0..<10 {
                            sample = rightBands[band].process(sample, gain: gains[band])
                        }
                    } else {
                        for band in 0..<10 {
                            sample = leftBands[band].process(sample, gain: gains[band])
                        }
                    }
                }
                data[index] = sample
                sum += sample * sample
            }
        }
        let rms = sqrt(sum / Float(max(1, frames * channels)))
        let gain = config.loudness ? loudnessGain(rms) : 1
        for index in 0..<(frames * channels) {
            data[index] *= gain
        }
        if config.spatial, channels >= 2 {
            for frame in 0..<frames {
                let l = data[frame * channels]
                let r = data[frame * channels + 1]
                let mid = (l + r) * 0.5
                let side = (l - r) * 0.5 * 1.45
                data[frame * channels] = mid + side
                data[frame * channels + 1] = mid - side
            }
        }
        lastGain = gain
        return rms * gain
    }

    private func loudnessGain(_ rms: Float) -> Float {
        guard rms > 0.0001 else { return lastGain }
        let target: Float = 0.12
        let desired = max(0.55, min(2.0, target / rms))
        let smoothed = lastGain * 0.96 + desired * 0.04
        return smoothed
    }

    /// Consumed by PlayerService on the main queue. Returns true once per
    /// detected run of silence.
    func takeSkipSilenceRequest() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard skipRequested else { return false }
        skipRequested = false
        silenceSkips += 1
        return true
    }

    /// Deterministic proof for the report harness: feed a known signal through
    /// the same renderer the tap uses, with the current persisted settings.
    func selfTest(eq: String? = nil, loudness: Bool? = nil, spatial: Bool? = nil) -> String {
        var config = currentConfig()
        if let eq = eq { config.equalizer = eq }
        if let loudness = loudness { config.loudness = loudness }
        if let spatial = spatial { config.spatial = spatial }
        var left = (0..<4096).map { Float(sin(Double($0) * 0.08) * 0.25) }
        var right = left
        let before = sqrt(left.reduce(0) { $0 + $1 * $1 } / Float(left.count))
        if config.equalizer != "Off" {
            let gains = config.gains
            leftBands = frequencies.enumerated().map { index, frequency in
                Biquad(frequency: min(frequency, 44100 * 0.45),
                       gain: gains[index], sampleRate: 44100)
            }
            rightBands = leftBands
        }
        var after: Float = 0
        left.withUnsafeMutableBufferPointer { leftPtr in
            right.withUnsafeMutableBufferPointer { rightPtr in
                if let l = leftPtr.baseAddress, let r = rightPtr.baseAddress {
                    after = renderStereo(l, r, frames: 4096, config: config)
                }
            }
        }
        return "eq=\(config.equalizer) loudness=\(config.loudness) spatial=\(config.spatial)"
            + " skip=\(config.skipSilence) attached=\(tapAttached)"
            + " frames=\(processedFrames) rmsBefore=\(String(format: "%.3f", before))"
            + " rmsAfter=\(String(format: "%.3f", after))"
            + " gain=\(String(format: "%.2f", lastGain))"
    }

    private let frequencies = [31.0, 62.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0]
}

private struct Biquad {
    var b0: Float = 1
    var b1: Float = 0
    var b2: Float = 0
    var a1: Float = 0
    var a2: Float = 0
    var x1: Float = 0
    var x2: Float = 0
    var y1: Float = 0
    var y2: Float = 0

    init() {}

    init(frequency: Double, gain: Double, sampleRate: Double) {
        let A = pow(10, gain / 40)
        let w = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(w) / (2 * 1.0)
        let cosw = cos(w)
        let a0 = 1 + alpha / A
        b0 = Float((1 + alpha * A) / a0)
        b1 = Float((-2 * cosw) / a0)
        b2 = Float((1 - alpha * A) / a0)
        a1 = Float((-2 * cosw) / a0)
        a2 = Float((1 - alpha / A) / a0)
    }

    mutating func process(_ input: Float, gain: Double) -> Float {
        if gain == 0 { return input }
        let output = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = input
        y2 = y1
        y1 = output
        return output
    }
}

private func audioTapInit(_ tap: MTAudioProcessingTap,
                          _ clientInfo: UnsafeMutableRawPointer?,
                          _ tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>) {
    tapStorageOut.pointee = clientInfo
}

private func audioTapFinalize(_ tap: MTAudioProcessingTap) {
}

private func audioTapPrepare(_ tap: MTAudioProcessingTap,
                             _ maxFrames: CMItemCount,
                             _ processingFormat: UnsafePointer<AudioStreamBasicDescription>) {
    let storage = MTAudioProcessingTapGetStorage(tap)
    let dsp = Unmanaged<AudioDSP>.fromOpaque(storage).takeUnretainedValue()
    dsp.prepare(format: processingFormat.pointee)
}

private func audioTapUnprepare(_ tap: MTAudioProcessingTap) {
    let storage = MTAudioProcessingTapGetStorage(tap)
    let dsp = Unmanaged<AudioDSP>.fromOpaque(storage).takeUnretainedValue()
    dsp.unprepare()
}

private func audioTapProcess(_ tap: MTAudioProcessingTap,
                             _ numberFrames: CMItemCount,
                             _ flags: MTAudioProcessingTapFlags,
                             _ bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
                             _ numberFramesOut: UnsafeMutablePointer<CMItemCount>,
                             _ flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>) {
    let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut,
                                                    flagsOut, nil, numberFramesOut)
    guard status == noErr else { return }
    let storage = MTAudioProcessingTapGetStorage(tap)
    let dsp = Unmanaged<AudioDSP>.fromOpaque(storage).takeUnretainedValue()
    dsp.process(bufferList: bufferListInOut, frames: numberFrames)
}
