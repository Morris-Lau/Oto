import Accelerate
import AVFoundation
import MediaToolbox

/// Attaches an `AVAudioMix` processing tap to an `AVPlayerItem` so decoded PCM can drive UI levels.
enum PlaybackAudioTapInstaller {
    @MainActor
    static func install(on item: AVPlayerItem, generation: UInt64) async {
        do {
            let tracks = try await item.asset.loadTracks(withMediaType: .audio)
            guard let track = tracks.first else { return }
            guard let mix = makeAudioMix(for: track, generation: generation) else { return }
            item.audioMix = mix
        } catch {
            item.audioMix = nil
        }
    }

    private static func makeAudioMix(for track: AVAssetTrack, generation: UInt64) -> AVAudioMix? {
        let params = AVMutableAudioMixInputParameters(track: track)
        let retained = Unmanaged.passRetained(PlaybackTapContext(generation: generation))

        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: retained.toOpaque(),
            init: { _, clientInfo, tapStorageOut in
                tapStorageOut.pointee = clientInfo
            },
            finalize: { tap in
                let raw = MTAudioProcessingTapGetStorage(tap)
                Unmanaged<PlaybackTapContext>.fromOpaque(raw).release()
            },
            prepare: { tap, _, processingFormat in
                let raw = MTAudioProcessingTapGetStorage(tap)
                let ctx = Unmanaged<PlaybackTapContext>.fromOpaque(raw).takeUnretainedValue()
                ctx.audioFormat = processingFormat.pointee
            },
            unprepare: { _ in },
            process: { tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut in
                var sourceFlags: MTAudioProcessingTapFlags = 0
                var framesGot: CMItemCount = 0
                let err = MTAudioProcessingTapGetSourceAudio(
                    tap,
                    numberFrames,
                    bufferListInOut,
                    &sourceFlags,
                    nil,
                    &framesGot
                )
                guard err == noErr, framesGot > 0 else {
                    numberFramesOut.pointee = 0
                    flagsOut.pointee = flags
                    return
                }
                let raw = MTAudioProcessingTapGetStorage(tap)
                let ctx = Unmanaged<PlaybackTapContext>.fromOpaque(raw).takeUnretainedValue()
                ctx.process(bufferList: bufferListInOut, frameCount: Int(framesGot))
                numberFramesOut.pointee = framesGot
                flagsOut.pointee = sourceFlags
            }
        )

        var tap: MTAudioProcessingTap?
        let createErr = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PreEffects,
            &tap
        )
        guard createErr == noErr, let tap else {
            retained.release()
            return nil
        }

        params.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]
        return mix
    }
}

// MARK: - Tap context

private final class PlaybackTapContext: @unchecked Sendable {
    let generation: UInt64
    private let lock = NSLock()
    private var followers: [Float] = [0, 0, 0, 0]
    private var lastMainFlush: CFTimeInterval = 0

    private let fftLog2N: vDSP_Length = 10
    private let fftSize = 1024
    private var fftSetup: FFTSetup?
    private var monoBuffer: [Float]
    private var windowBuffer: [Float]
    private var realParts: [Float]
    private var imagParts: [Float]

    /// Envelope per band after FFT (wider spread → bars don’t move as one blob).
    private let attacks: [Float] = [0.42, 0.58, 0.74, 0.9]
    private let releases: [Float] = [0.52, 0.62, 0.74, 0.86]
    /// Stronger tiering across bands so frequency differences read as height differences.
    private let bandPerceptualGain: [Float] = [0.48, 0.78, 1.12, 1.52]
    /// Amplify each bar’s deviation from the four-bar mean (then clamp). Higher = more contrast.
    private let interBandContrastStretch: Float = 1.62

    /// Hz edges: sub/low, low-mid, mid, high (last band runs to Nyquist).
    private let bandEdgesHz: [Float] = [220, 1800, 6400]

    var audioFormat = AudioStreamBasicDescription()

    init(generation: UInt64) {
        self.generation = generation
        monoBuffer = [Float](repeating: 0, count: fftSize)
        windowBuffer = [Float](repeating: 0, count: fftSize)
        realParts = [Float](repeating: 0, count: fftSize / 2)
        imagParts = [Float](repeating: 0, count: fftSize / 2)
        fftSetup = vDSP_create_fftsetup(fftLog2N, FFTRadix(kFFTRadix2))
        windowBuffer.withUnsafeMutableBufferPointer { win in
            guard let w = win.baseAddress else { return }
            vDSP_hann_window(w, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        }
    }

    deinit {
        if let setup = fftSetup {
            vDSP_destroy_fftsetup(setup)
        }
    }

    func process(bufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: Int) {
        guard frameCount > 0 else { return }

        monoBuffer.withUnsafeMutableBufferPointer { mb in
            guard let b = mb.baseAddress else { return }
            vDSP_vclr(b, 1, vDSP_Length(fftSize))
        }
        let filled = fillMono(from: bufferList, frameCount: frameCount)
        guard filled > 0 else { return }

        monoBuffer.withUnsafeMutableBufferPointer { mb in
            guard let base = mb.baseAddress else { return }
            vDSP_vmul(base, 1, windowBuffer, 1, base, 1, vDSP_Length(fftSize))
        }

        let sr = Float(audioFormat.mSampleRate)
        let targets: [Float]
        if let setup = fftSetup, sr > 0, filled >= 32 {
            for j in 0..<(fftSize / 2) {
                realParts[j] = monoBuffer[2 * j]
                imagParts[j] = monoBuffer[2 * j + 1]
            }
            realParts.withUnsafeMutableBufferPointer { rp in
                imagParts.withUnsafeMutableBufferPointer { ip in
                    guard let r = rp.baseAddress, let i = ip.baseAddress else { return }
                    var split = DSPSplitComplex(realp: r, imagp: i)
                    vDSP_fft_zrip(setup, &split, 1, fftLog2N, FFTDirection(kFFTDirection_Forward))
                }
            }
            targets = bandTargetsFromFFT(sampleRate: sr)
        } else {
            targets = bandTargetsFromRMSFallback(bufferList: bufferList, frameCount: frameCount)
        }

        lock.lock()
        for i in 0..<4 {
            let prev = followers[i]
            let target = targets[i]
            if target > prev {
                followers[i] = attacks[i] * target + (1 - attacks[i]) * prev
            } else {
                followers[i] = (1 - releases[i]) * target + releases[i] * prev
            }
        }
        let snapshot = followers
        let now = CACurrentMediaTime()
        let shouldFlush = now - lastMainFlush >= 1.0 / 66.0
        if shouldFlush {
            lastMainFlush = now
        }
        lock.unlock()

        guard shouldFlush else { return }
        let gen = generation
        Task { @MainActor in
            PlayerService.shared.applyVisualizerLevels(snapshot, generation: gen)
        }
    }

    private func bandTargetsFromFFT(sampleRate sr: Float) -> [Float] {
        let n = Float(fftSize)
        var bandPow = [Float](repeating: 0, count: 4)
        var bandBins = [Float](repeating: 0, count: 4)

        func appendBin(freq: Float, power: Float) {
            let b: Int
            if freq < bandEdgesHz[0] { b = 0 }
            else if freq < bandEdgesHz[1] { b = 1 }
            else if freq < bandEdgesHz[2] { b = 2 }
            else { b = 3 }
            bandPow[b] += power
            bandBins[b] += 1
        }

        // Skip k == 0 (DC); Nyquist packed in imagParts[0] after real forward FFT.
        for k in 1..<(fftSize / 2) {
            let f = Float(k) * sr / n
            let p = realParts[k] * realParts[k] + imagParts[k] * imagParts[k]
            appendBin(freq: f, power: p)
        }
        let nyq = imagParts[0] * imagParts[0]
        appendBin(freq: sr * 0.5, power: nyq)

        var out = [Float](repeating: 0, count: 4)
        for i in 0..<4 {
            let meanPow = bandBins[i] > 0 ? bandPow[i] / bandBins[i] : 0
            let mag = sqrt(meanPow) * bandPerceptualGain[i]
            let knee = 1.05 + Float(i) * 0.11
            out[i] = mag / (1 + mag * knee)
        }
        return Self.amplifyInterBandContrast(out, stretch: interBandContrastStretch)
    }

    private func bandTargetsFromRMSFallback(
        bufferList: UnsafeMutablePointer<AudioBufferList>,
        frameCount: Int
    ) -> [Float] {
        let r = Self.rms(from: bufferList, frameCount: frameCount, asbd: audioFormat)
        let u = (r * 10) / (1 + r * 10)
        let raw = [u * 0.38, u * 0.68, u * 1.02, u * 1.38].map { min(1, $0) }
        return Self.amplifyInterBandContrast(raw, stretch: interBandContrastStretch * 0.92)
    }

    /// Pulls quiet bands down and loud bands up vs the frame average so the four columns read more distinctly.
    private static func amplifyInterBandContrast(_ values: [Float], stretch: Float) -> [Float] {
        guard values.count == 4 else { return values }
        let mean = (values[0] + values[1] + values[2] + values[3]) * 0.25
        return values.map { v in
            let y = mean + (v - mean) * stretch
            return min(1, max(0, y))
        }
    }

    private func fillMono(from bufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: Int) -> Int {
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        guard !buffers.isEmpty else { return 0 }
        let asbd = audioFormat
        let ch = max(1, Int(asbd.mChannelsPerFrame))
        let copyFrames = min(frameCount, fftSize)

        if Self.isFloatPCM32(asbd) {
            let nonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
            if nonInterleaved {
                var ptrs: [UnsafePointer<Float>] = []
                ptrs.reserveCapacity(ch)
                for buffer in buffers {
                    guard let base = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    ptrs.append(base)
                    if ptrs.count == ch { break }
                }
                guard ptrs.count == ch else { return 0 }
                for f in 0..<copyFrames {
                    var s: Float = 0
                    for c in 0..<ch { s += ptrs[c][f] }
                    monoBuffer[f] = s / Float(ch)
                }
                return copyFrames
            }
            guard let base = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return 0 }
            for f in 0..<copyFrames {
                var s: Float = 0
                for c in 0..<ch {
                    s += base[f * ch + c]
                }
                monoBuffer[f] = s / Float(ch)
            }
            return copyFrames
        }

        if Self.isIntPCM16(asbd) {
            let nonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
            if nonInterleaved {
                var ptrs: [UnsafePointer<Int16>] = []
                for buffer in buffers {
                    guard let base = buffer.mData?.assumingMemoryBound(to: Int16.self) else { continue }
                    ptrs.append(base)
                    if ptrs.count == ch { break }
                }
                guard ptrs.count == ch else { return 0 }
                for f in 0..<copyFrames {
                    var s: Float = 0
                    for c in 0..<ch {
                        s += Float(ptrs[c][f]) * (1.0 / 32768.0)
                    }
                    monoBuffer[f] = s / Float(ch)
                }
                return copyFrames
            }
            guard let base = buffers[0].mData?.assumingMemoryBound(to: Int16.self) else { return 0 }
            for f in 0..<copyFrames {
                var s: Float = 0
                for c in 0..<ch {
                    s += Float(base[f * ch + c]) * (1.0 / 32768.0)
                }
                monoBuffer[f] = s / Float(ch)
            }
            return copyFrames
        }

        return 0
    }

    private static func isFloatPCM32(_ asbd: AudioStreamBasicDescription) -> Bool {
        asbd.mFormatID == kAudioFormatLinearPCM
            && (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
            && asbd.mBitsPerChannel == 32
    }

    private static func isIntPCM16(_ asbd: AudioStreamBasicDescription) -> Bool {
        asbd.mFormatID == kAudioFormatLinearPCM
            && (asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0
            && asbd.mBitsPerChannel == 16
    }

    private static func rms(
        from bufferList: UnsafeMutablePointer<AudioBufferList>,
        frameCount: Int,
        asbd: AudioStreamBasicDescription
    ) -> Float {
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        guard !buffers.isEmpty else { return 0 }

        if isFloatPCM32(asbd) {
            var sum: Float = 0
            var channels: Float = 0
            for buffer in buffers {
                guard let base = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let byteCount = Int(buffer.mDataByteSize)
                let sampleCount = min(frameCount, byteCount / MemoryLayout<Float>.size)
                guard sampleCount > 0 else { continue }
                var rms: Float = 0
                vDSP_rmsqv(base, 1, &rms, vDSP_Length(sampleCount))
                sum += rms
                channels += 1
            }
            return channels > 0 ? sum / channels : 0
        }

        if isIntPCM16(asbd) {
            var sum: Float = 0
            var channels: Float = 0
            for buffer in buffers {
                guard let base = buffer.mData?.assumingMemoryBound(to: Int16.self) else { continue }
                let byteCount = Int(buffer.mDataByteSize)
                let sampleCount = min(frameCount, byteCount / MemoryLayout<Int16>.size)
                guard sampleCount > 0 else { continue }
                var scratch = [Float](repeating: 0, count: sampleCount)
                let chRms: Float = scratch.withUnsafeMutableBufferPointer { dst in
                    guard let d = dst.baseAddress else { return Float(0) }
                    vDSP_vflt16(base, 1, d, 1, vDSP_Length(sampleCount))
                    var scale: Float = 1.0 / 32768.0
                    vDSP_vsmul(d, 1, &scale, d, 1, vDSP_Length(sampleCount))
                    var rms: Float = 0
                    vDSP_rmsqv(d, 1, &rms, vDSP_Length(sampleCount))
                    return rms
                }
                sum += chRms
                channels += 1
            }
            return channels > 0 ? sum / channels : 0
        }

        return 0
    }
}
