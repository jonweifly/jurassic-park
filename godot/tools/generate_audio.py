"""Generate original placeholder sounds; no external recordings or dependencies.

Run from any cwd. WAV assets are committed outputs and need no Python at runtime.
"""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 24000
OUT = Path(__file__).resolve().parents[1] / "assets/audio"
OUT.mkdir(parents=True, exist_ok=True)
rng = random.Random(65065)


def save(name, values, loop=False):
    if loop:
        # Overlap the tail and head so ambient loops have no boundary click.
        overlap = RATE
        for i in range(overlap):
            blend = i / overlap
            values[i] = values[-overlap + i] * (1 - blend) + values[i] * blend
        values = values[:-overlap]
    peak = max(abs(v) for v in values) or 1
    gain = min(1, 0.85 / peak)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(b"".join(struct.pack("<h", round(v * gain * 32767)) for v in values))


def tone(t, hz):
    return math.sin(math.tau * t * hz)


def chime(name, notes, seconds=0.18):
    samples = []
    for hz in notes:
        for i in range(int(RATE * seconds)):
            t = i / RATE
            envelope = min(1, t / 0.008) * math.exp(-t * 18)
            samples.append(0.42 * envelope * (tone(t, hz) + 0.2 * tone(t, hz * 2)))
    save(name, samples)


chime("click", [740], 0.075)
chime("ready", [392, 523, 659], 0.22)
chime("deposit", [880, 1175], 0.12)
chime("complete", [523, 659, 784], 0.16)
chime("warning", [330, 247], 0.22)
chime("rescue", [659, 880, 659, 988], 0.25)
chime("won", [523, 659, 784, 1047], 0.26)
chime("lost", [392, 330, 262, 196], 0.3)

for name, duration in [("chop", 0.28), ("hammer", 0.24), ("mine", 0.38),
                       ("step", 0.16), ("shot", 0.24), ("bow", 0.3),
                       ("electric", 0.4), ("gate", 0.85), ("hit", 0.3),
                       ("roar", 1.65), ("collapse", 0.8)]:
    values = []
    low = 0.0
    for i in range(int(RATE * duration)):
        t = i / RATE
        noise = rng.uniform(-1, 1)
        low += 0.13 * (noise - low)
        decay = math.exp(-t * (15 if duration < 0.5 else 3))
        if name == "chop": v = (low * 1.1 + tone(t, 155) * 0.3) * decay
        elif name == "hammer": v = (noise * 0.22 + tone(t, 460) * 0.45) * decay
        elif name == "mine": v = (noise * 0.12 + tone(t, 1730) * 0.3 + tone(t, 2430) * 0.16) * decay
        elif name == "step": v = low * 0.65 * decay
        elif name == "shot": v = (noise * 0.65 + low * 0.5) * decay
        elif name == "bow": v = (tone(t, 200 - 190 * t) * 0.4 + noise * 0.2) * decay
        elif name == "electric": v = (noise * 0.3 + tone(t, 105) * 0.35) * (0.5 + 0.5 * tone(t, 47)) * decay
        elif name == "gate": v = (low * 0.45 + tone(t, 145) * 0.15 + tone(t, 291) * 0.08) * math.sin(math.pi * t / duration)
        elif name == "hit": v = (low + tone(t, 90) * 0.35) * decay
        elif name == "collapse": v = low * 1.5 * decay
        else:
            # Layered subharmonics/noise make a growl, not a sampled animal call.
            phase = math.tau * (105 * t - 22 * t * t)
            v = (math.sin(phase) * 0.25 + math.sin(phase * 0.51) * 0.25 + low * 0.9)
            v *= math.sin(math.pi * t / duration) ** 0.6 * (0.8 + 0.2 * tone(t, 23))
        fade = min(1, t / 0.002, (duration - t) / 0.025)
        values.append(v * fade)
    save(name, values)

for name in ("day", "night", "fire", "generator"):
    duration = 17
    values = []
    low = 0.0
    for i in range(RATE * duration):
        t = i / RATE
        noise = rng.uniform(-1, 1)
        low += 0.025 * (noise - low)
        if name in ("day", "night"):
            v = low * (0.6 + 0.2 * tone(t, 0.19))
            if name == "day":
                chirp = t % 3.7
                if 0.4 < chirp < 1.1:
                    e = math.sin(math.pi * (chirp - 0.4) / 0.7) ** 2
                    v += 0.07 * e * tone(chirp, 1800 + 160 * math.sin(chirp * 18))
            else:
                pulse = max(0, tone(t, 3.4)) ** 8
                v += 0.05 * pulse * tone(t, 3100) * (0.65 + 0.35 * tone(t, 0.13))
        elif name == "fire":
            v = low * 0.5 + noise * 0.03
            if rng.random() < 0.0007: v += noise * 0.3
        else:
            v = 0.09 * tone(t, 60) + 0.04 * tone(t, 120) + low * 0.25
            v *= 0.85 + 0.15 * tone(t, 7)
        values.append(v)
    save(name, values, loop=True)
print(f"Generated {len(list(OUT.glob('*.wav')))} original WAV sounds in {OUT}")
