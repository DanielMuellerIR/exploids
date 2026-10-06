import XCTest
import AVFoundation
@testable import GameCore

final class ProceduralSoundMixerTests: XCTestCase {
    private func buffer() -> AVAudioPCMBuffer {
        AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!,
                         frameCapacity: 512)!
    }

    func testRenderReturnsSilenceImmediatelyDuringControlContention() {
        let mixer = ProceduralSoundMixer()
        mixer.enqueue(.laser, sampleRate: 44100)
        let held = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            mixer.lock.lock()
            held.signal()
            _ = release.wait(timeout: .now() + 1)
            mixer.lock.unlock()
            finished.signal()
        }
        XCTAssertEqual(held.wait(timeout: .now() + 1), .success)
        let pcm = buffer()
        let start = ProcessInfo.processInfo.systemUptime
        let audible = mixer.render(frameCount: 512, outputData: pcm.mutableAudioBufferList, sampleRate: 44100)
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        release.signal()
        XCTAssertEqual(finished.wait(timeout: .now() + 1), .success)
        XCTAssertFalse(audible)
        XCTAssertLessThan(elapsed, 0.2, "Der Renderpfad darf nicht auf den gehaltenen Lock warten")
        XCTAssertTrue((0..<512).allSatisfy { pcm.floatChannelData![0][$0] == 0 })
        XCTAssertTrue(mixer.render(frameCount: 512, outputData: pcm.mutableAudioBufferList, sampleRate: 44100))
        XCTAssertTrue((0..<512).contains { pcm.floatChannelData![0][$0] != 0 })
    }

    func testAllEffectsRenderFiniteSamplesAndVoiceSlotsAreReused() {
        let mixer = ProceduralSoundMixer()
        let pcm = buffer()
        for type in [ActiveSound.SoundType.laser, .explosion, .powerUp, .bomb, .ufo, .levelComplete, .implosion] {
            mixer.enqueue(type, sampleRate: 44100)
            for _ in 0..<110 {
                _ = mixer.render(frameCount: 512, outputData: pcm.mutableAudioBufferList, sampleRate: 44100)
                XCTAssertTrue((0..<512).allSatisfy { pcm.floatChannelData![0][$0].isFinite })
            }
            XCTAssertFalse(mixer.render(frameCount: 512, outputData: pcm.mutableAudioBufferList, sampleRate: 44100))
        }
        for _ in 0..<32 { mixer.enqueue(.laser, sampleRate: 44100) }
        XCTAssertTrue(mixer.render(frameCount: 512, outputData: pcm.mutableAudioBufferList, sampleRate: 44100))
    }
}
