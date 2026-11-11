"""Generate the short, original Hand Defense SFX set.

Requires numpy. No background music is generated; only combat/death/victory cues.
"""
from pathlib import Path
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1] / "assets" / "audio" / "sfx"
ROOT.mkdir(parents=True, exist_ok=True)
SAMPLE_RATE = 22050
RNG = np.random.default_rng(17)


def write_wav(path: Path, samples: np.ndarray) -> None:
    samples = np.clip(samples, -1.0, 1.0)
    pcm = (samples * 32767).astype("<i2")
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(pcm.tobytes())


def envelope(length: int, attack: float, decay: float) -> np.ndarray:
    time = np.arange(length) / SAMPLE_RATE
    return np.minimum(time / max(attack, 1e-5), 1.0) * np.exp(-decay * time)


def sweep(
    duration: float,
    start_hz: float,
    end_hz: float,
    waveform: str = "square",
    volume: float = 0.25,
    noise: float = 0.0,
    decay: float = 14.0,
) -> np.ndarray:
    length = int(duration * SAMPLE_RATE)
    time = np.arange(length) / SAMPLE_RATE
    phase = 2.0 * np.pi * (
        start_hz * time + 0.5 * ((end_hz - start_hz) / duration) * time * time
    )
    if waveform == "square":
        signal = np.sign(np.sin(phase))
    elif waveform == "triangle":
        signal = (2.0 / np.pi) * np.arcsin(np.sin(phase))
    else:
        signal = np.sin(phase)
    signal = 0.78 * signal + 0.22 * np.sin(phase * 2.01)
    if noise:
        signal += noise * RNG.normal(0.0, 1.0, length)
    return signal * envelope(length, 0.0015, decay) * volume


def note(frequency: float, duration: float, volume: float = 0.18) -> np.ndarray:
    length = int(duration * SAMPLE_RATE)
    time = np.arange(length) / SAMPLE_RATE
    signal = 0.65 * np.sign(np.sin(2 * np.pi * frequency * time))
    signal += 0.35 * np.sin(2 * np.pi * frequency * time)
    return signal * envelope(length, 0.003, 7.0) * volume


write_wav(
    ROOT / "shot_pew.wav",
    sweep(0.105, 1250, 390, "square", 0.22, 0.012, 22.0),
)

laser_low = sweep(0.16, 980, 460, "sine", 0.26, 0.006, 11.0)
laser_high = 0.35 * sweep(0.11, 1850, 920, "triangle", 0.12, 0.0, 18.0)
laser = np.zeros(max(len(laser_low), len(laser_high)), dtype=np.float64)
laser[: len(laser_low)] += laser_low
laser[: len(laser_high)] += laser_high
write_wav(ROOT / "laser_shot.wav", laser)

write_wav(
    ROOT / "enemy_down.wav",
    sweep(0.23, 720, 150, "triangle", 0.24, 0.025, 12.0),
)

notes = [
    note(523.25, 0.09, 0.15),
    note(659.25, 0.09, 0.16),
    note(783.99, 0.12, 0.17),
    note(1046.5, 0.22, 0.18),
]
gap = int(0.025 * SAMPLE_RATE)
victory = np.zeros(sum(map(len, notes)) + gap * (len(notes) - 1), dtype=np.float64)
cursor = 0
for index, samples in enumerate(notes):
    victory[cursor : cursor + len(samples)] += samples
    cursor += len(samples) + (gap if index < len(notes) - 1 else 0)
write_wav(ROOT / "level_complete.wav", victory)

print("Generated SFX:", ", ".join(path.name for path in sorted(ROOT.glob("*.wav"))))
