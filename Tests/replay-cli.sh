#!/bin/bash
# Reale, stumme Headless-Prüfung: Spielstart, Replay-Kompatibilität und Exporttempo.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product exploids
bin_dir="$(swift build -c release --show-bin-path)"
probe="$(mktemp -d)"
trap 'rm -rf "$probe"' EXIT

python3 - "$probe" <<'PY'
import pathlib, plistlib, re, sys
version = int(re.search(r'currentLogicVersion: Int = (\d+)', pathlib.Path('Sources/GameCore/Replay.swift').read_text()).group(1))
replay = dict(version=version, seed=42, startLevel=1, gameMode=0, events=[], frameCount=240,
              autoFire=False, width=1000, height=800)
for name, v in [('current', version), ('odd', version), ('old', version-1)]:
    replay['frameCount'] = 241 if name == 'odd' else 240
    replay['version'] = v
    (pathlib.Path(sys.argv[1]) / (name+'.replay')).write_bytes(plistlib.dumps(replay, fmt=plistlib.FMT_BINARY))
PY

"$bin_dir/exploids" --test-mode --no-sound > "$probe/telemetry.txt"
python3 - "$probe/telemetry.txt" <<'PY'
import pathlib, re, sys
frames = re.findall(r'Frame \d+: .*Vel=\(([-\d.]+), ([-\d.]+)\)', pathlib.Path(sys.argv[1]).read_text())
assert len(frames) == 10, frames
assert any(float(x) != 0 or float(y) != 0 for x,y in frames), 'Kein bewegtes Schiff: Test blieb im Menü'
PY

"$bin_dir/exploids" --replay-verify "$probe/current.replay" --no-sound > "$probe/verify.txt"
if "$bin_dir/exploids" --replay-verify "$probe/old.replay" --no-sound > "$probe/old.txt" 2>&1; then
    echo "FEHLER: alte Logikversion wurde wiedergegeben." >&2; exit 1
else
    [ "$?" -eq 3 ]
fi
grep -q 'Replay inkompatibel' "$probe/old.txt"

for fps in 0 121; do
    if "$bin_dir/exploids" --render-replay "$probe/current.replay" --fps "$fps" --out "$probe/invalid.gif" --no-sound > "$probe/invalid.txt" 2>&1; then
        echo "FEHLER: unzulässige Bildrate $fps akzeptiert." >&2; exit 1
    else
        [ "$?" -eq 4 ]
    fi
    grep -q 'zwischen 1 und 120 FPS' "$probe/invalid.txt"
done

# Manche virtuelle CI-Macs haben kein Metal-Gerät. Grundprüfungen bleiben dort aktiv;
# Renderprüfungen werden ausdrücklich als nicht ausgeführt gemeldet.
metal_status=0
swift - <<'SWIFT' || metal_status=$?
import Metal
import Foundation
exit(MTLCreateSystemDefaultDevice() == nil ? 42 : 0)
SWIFT
if [ "$metal_status" -eq 42 ]; then
    echo "replay-cli: Grundprüfungen OK; GIF/Video übersprungen (kein Metal-Gerät)."
    exit 0
elif [ "$metal_status" -ne 0 ]; then
    exit "$metal_status"
fi

for fps in 24 25 30 60 120; do
    "$bin_dir/exploids" --render-replay "$probe/current.replay" --out "$probe/run-$fps.gif" --scale 160 --fps "$fps" --max-frames 0 --no-sound
done
"$bin_dir/exploids" --render-replay "$probe/odd.replay" --out "$probe/odd.gif" --scale 160 --fps 1 --max-frames 0 --no-sound
"$bin_dir/exploids" --render-replay "$probe/odd.replay" --out "$probe/stride.gif" --scale 160 --fps 1 --stride 120 --max-frames 0 --no-sound
"$bin_dir/exploids" --render-video "$probe/current.replay" --out "$probe/run.mp4" --scale 160 --fps 60 --max-frames 0 --no-sound
swift - "$probe" <<'SWIFT'
import Foundation
import ImageIO
import AVFoundation
let root = URL(fileURLWithPath: CommandLine.arguments[1])
for fps in [24, 25, 30, 60, 120] {
    let gif = CGImageSourceCreateWithURL(root.appendingPathComponent("run-\(fps).gif") as CFURL, nil)!
    let count = CGImageSourceGetCount(gif)
    precondition(count == min(fps * 2, 100), "Falsche GIF-Bildzahl bei \(fps) FPS: \(count)")
    var duration = 0.0
    for i in 0..<count {
        let props = CGImageSourceCopyPropertiesAtIndex(gif, i, nil)! as NSDictionary
        let gifProps = props[kCGImagePropertyGIFDictionary] as! NSDictionary
        duration += (gifProps[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (gifProps[kCGImagePropertyGIFDelayTime] as! Double)
    }
    precondition(abs(duration - 2) < 0.001, "GIF verändert das Abspieltempo bei \(fps) FPS: \(duration)")
}
for (name, expected) in [("odd", 2.01), ("stride", 3.0)] {
    let gif = CGImageSourceCreateWithURL(root.appendingPathComponent(name + ".gif") as CFURL, nil)!
    var duration = 0.0
    for index in 0..<CGImageSourceGetCount(gif) {
        let properties = CGImageSourceCopyPropertiesAtIndex(gif, index, nil)! as NSDictionary
        let timing = properties[kCGImagePropertyGIFDictionary] as! NSDictionary
        duration += (timing[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (timing[kCGImagePropertyGIFDelayTime] as! Double)
    }
    precondition(abs(duration - expected) < 0.001, "Falsche Restdauer/Stride: \(name) = \(duration)")
}
let video = AVURLAsset(url: root.appendingPathComponent("run.mp4"))
precondition(abs(CMTimeGetSeconds(video.duration) - 2) < 0.001, "Video verändert das Abspieltempo")
print("replay-cli: OK (bewegtes Schiff, alte Logik abgelehnt, GIF 1/24/25/30/60/120 FPS und Video 60 FPS in Echtzeit)")
SWIFT
