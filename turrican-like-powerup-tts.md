# Lokale Power-Up-Sprachsamples (Turrican-Stil)

## Ziel

Für ein Computerspiel sollen kurze, digitalisierte Sprachsamples im Stil alter
Amiga/C64-Action-Spiele erzeugt werden – also Ansagen wie **„Power Up!"**,
**„Extra Life!"**, **„Game Over!"** im rauen, krächzig-metallischen Turrican-Sound.

Der Sound entsteht in **zwei Schritten**:

1. **Saubere Stimme** lokal per TTS generieren (Qwen3-TTS oder F5-TTS, beide via MLX auf Apple Silicon).
2. **Retro-Charakter** per Post-Processing (Bitcrusher + Downsampling) aufprägen.

Das Modell liefert die Basis – die Körnung kommt aus dem Post-Processing. Kein
TTS-Modell erzeugt den digitalisierten Amiga-Klang von sich aus.

---

## Setup

```bash
# Framework für lokales TTS auf Apple Silicon
pip install mlx-audio

# Post-Processing (Bitcrusher etc.) – Spotifys pedalboard
pip install pedalboard soundfile numpy
```

> Vor der Umsetzung die **aktuelle API von `mlx-audio`** prüfen (Importpfade/Funktionsnamen
> ändern sich noch), z. B. via `pip show mlx-audio` und der Projekt-README. Die Snippets
> unten sind als Gerüst gedacht, nicht als garantiert lauffähige Signatur.

---

## Variante A: Qwen3-TTS (VoiceDesign)

**Wann:** Wenn die Stimme **per Textbeschreibung** entworfen werden soll
(„robotic retro game announcer, metallic"). Qwen3-TTS ist Apache-2.0 (quelloffen
seit 22.01.2026) und über MLX-Audio Apple-Silicon-optimiert. Es gibt eine
**VoiceDesign**-Variante (Stimme aus Beschreibung) und **CustomVoice** (Stil-/Timbre-Steuerung).

**Caveat:** Viele Stimmen haben beim Englischen einen hörbaren chinesischen Akzent.
Für kurze, stark bitcrushte Ein-Wort-Samples meist vernachlässigbar – nach dem
Crushen ist der Akzent kaum noch herauszuhören. Bei Bedarf 2–3 Takes generieren und besten wählen.

```python
# Gerüst – exakte Importpfade gegen aktuelle mlx-audio-README abgleichen
from mlx_audio.tts.generate import generate_audio

generate_audio(
    text="Power Up!",
    model="mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign",  # Modell-ID prüfen
    voice_description="robotic retro arcade announcer, metallic, punchy, energetic",
    file_path="raw/power_up.wav",
)
```

Sample-Liste fürs Spiel als Schleife generieren:

```python
samples = ["Power Up!", "Extra Life!", "Game Over!", "Bonus!", "Level Complete!"]
for s in samples:
    fname = "raw/" + s.lower().replace(" ", "_").replace("!", "") + ".wav"
    generate_audio(text=s, model="...VoiceDesign", voice_description="...", file_path=fname)
```

---

## Variante B: F5-TTS (MLX)

**Wann:** Wenn eine **bestimmte Stimme geklont** werden soll (Voice-Cloning aus
einem ~5–10 s Referenz-Sample). Praktisch, falls eine konkrete Sprecher-Stimme
(z. B. eigene Aufnahme) als Ansager dienen soll.

```python
# Gerüst – F5-TTS-MLX-Port, API gegen Projekt-README abgleichen
from f5_tts_mlx.generate import generate

generate(
    text="Power Up!",
    ref_audio_path="ref/announcer_ref.wav",   # Referenzstimme
    ref_text="Reference transcript here.",      # Transkript der Referenz
    output_path="raw/power_up.wav",
)
```

**Faustregel:** Qwen3-TTS = schnellster Weg zu einer *erfundenen* Roboter-Ansagerstimme.
F5-TTS = wenn die Identität einer *vorhandenen* Stimme erhalten bleiben soll.

---

## Schritt 2: Bitcrusher / Turrican-Sound

Der digitalisierte Amiga-Klang = **niedrige Sample-Rate (~8 kHz)** + **geringe
Bit-Tiefe (8 bit oder weniger)** + etwas Sättigung. Optional ein Hauch
Ringmodulation für die metallische Kante.

```python
import numpy as np
import soundfile as sf
from pedalboard import Pedalboard, Bitcrush, Resample, Distortion, Gain

def crush(infile: str, outfile: str, target_sr: int = 8000, bits: int = 8):
    audio, sr = sf.read(infile, dtype="float32")
    if audio.ndim > 1:                      # auf Mono mischen (Retro = mono)
        audio = audio.mean(axis=1)

    board = Pedalboard([
        Resample(target_sample_rate=target_sr),  # Downsampling -> kerniger Aliasing-Sound
        Bitcrush(bit_depth=bits),                # 8 bit; für mehr Grit auf 6 senken
        Distortion(drive_db=6.0),                # leichte Sättigung
        Gain(gain_db=2.0),                       # nach dem Crushen etwas anheben
    ])
    out = board(audio, sr)

    # OPTIONAL: metallische Ringmodulation (robotic edge)
    # carrier = np.sin(2 * np.pi * 440 * np.arange(len(out)) / sr)
    # out = out * (0.5 + 0.5 * carrier)

    out = np.clip(out, -1.0, 1.0)
    sf.write(outfile, out, sr)

crush("raw/power_up.wav", "fx/power_up.wav")
```

### Tuning-Knöpfe

| Parameter            | Effekt                                        | Startwert |
|----------------------|-----------------------------------------------|-----------|
| `target_sr`          | niedriger = krächziger/dumpfer                 | 8000 Hz   |
| `bits`               | niedriger = mehr Quantisierungsrauschen        | 8 (6 = extrem) |
| `Distortion drive`   | mehr = aggressiver/verzerrter                  | 6 dB      |
| Ringmod-Frequenz     | höher = metallischer/roboterhafter             | 440 Hz    |

### Optional: noch authentischer

- **Pitch leicht anheben** (~+1 bis +2 Halbtöne) für den „kleinen" Arcade-Charakter.
- **Hart normalisieren / leicht clippen** statt sauberem Limiter – passt zum Lo-Fi-Ideal.
- **Sehr kurzes Fade-In/Out** (2–5 ms), um Klicks an den Sample-Rändern zu vermeiden.
- Wer den Originalklang *ohne* TTS will: **SAM** (Software Automatic Mouth) liefert den
  C64-Sprachsynth-Sound direkt – als Vergleichs-/Fallback-Pfad.

---

## Vorgeschlagener Workflow

```
text -> [Qwen3-TTS oder F5-TTS] -> raw/*.wav -> [crush()] -> fx/*.wav -> ins Spiel
```

1. Sample-Liste definieren (alle benötigten Ansagen).
2. Batch durch TTS → `raw/`.
3. Batch durch `crush()` → `fx/`.
4. A/B-Hören, `bits`/`target_sr` pro Sample feinjustieren.
5. Finale WAVs ins Asset-Verzeichnis des Spiels.
