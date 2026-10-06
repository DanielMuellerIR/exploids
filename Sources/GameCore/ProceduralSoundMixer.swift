import AVFoundation

/// Vorallokierte Stimmen; der Renderpfad wartet nie auf die Steuerseite und verändert keine Arrays.
final class ProceduralSoundMixer: @unchecked Sendable {
    let lock = NSLock()
    private let voices = (0..<16).map { _ in ActiveSound() }

    func enqueue(_ type: ActiveSound.SoundType, sampleRate: Double) {
        let seed = UInt64.random(in: .min ... .max)
        lock.lock()
        defer { lock.unlock() }
        voices.first { !$0.isActive }?.reset(type: type, sampleRate: sampleRate, seed: seed)
    }

    /// Liefert Stille, wenn gerade Steuerdaten geschrieben werden, statt die Audio-Deadline zu verpassen.
    func render(frameCount: Int, outputData: UnsafeMutablePointer<AudioBufferList>, sampleRate: Double) -> Bool {
        let buffers = UnsafeMutableAudioBufferListPointer(outputData)
        for buffer in buffers {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }
        guard lock.try() else { return false }
        defer { lock.unlock() }
        guard voices.contains(where: { $0.isActive }) else { return false }
        for frame in 0..<frameCount {
            var sum = 0.0
            for voice in voices where voice.isActive {
                if let sample = voice.nextSample(sampleRate: sampleRate) { sum += sample }
            }
            let sample = Float(max(-1, min(1, sum)))
            for buffer in buffers {
                buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
            }
        }
        return true
    }
}
