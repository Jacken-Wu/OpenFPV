"""Rebuild OpenFPV's seven original chiptunes using only Python's standard library.

16 bars each; pulse lead, pulse arpeggio, triangle bass and short noise percussion.
16-bit PCM preserves quiet passages without 8-bit quantization hiss. No samples.
WAV smpl metadata specifies the exact full-track forward loop for Godot's importer.
"""
import array
import json
import math
from pathlib import Path
import random
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "game/audio/music"
RATE = 22050
TABLE = 2048

# Relative semitones; -99 is a rest. Eight chords support the A/A'/B/A'' form.
SCORES = {
    "rustworks": {"title": "齿轮与晨光", "bpm": 112, "root": 45, "minor": True,
                  "chords": [0, 0, 5, 7, 3, 5, 7, 0], "duty": .25,
                  "motif": [12, -99, 12, 15, 19, -99, 15, 12, 10, 12, -99, 7, 10, -99, 12, -99]},
    "verdant": {"title": "绿庭的像素风", "bpm": 96, "root": 48, "minor": False,
                "chords": [0, 7, 9, 5, 2, 7, 5, 0], "duty": .5,
                "motif": [12, -99, 16, 19, 21, 19, 16, -99, 14, -99, 16, 14, 12, -99, 7, -99]},
    "oldtown": {"title": "赤陶巷弄", "bpm": 104, "root": 50, "minor": True,
                "chords": [0, 7, 5, 0, 10, 5, 7, 0], "duty": .125,
                "motif": [12, 14, 15, -99, 19, 17, 15, 14, 12, -99, 10, 7, 10, 14, 12, -99]},
    "canyon": {"title": "峡谷回声", "bpm": 84, "root": 43, "minor": True,
               "chords": [0, 10, 5, 0, 3, 10, 7, 0], "duty": .25,
               "motif": [12, -99, -99, 7, 10, -99, 12, -99, 15, -99, 17, 15, 12, -99, 10, -99]},
    "pine_valley": {"title": "松针间的溪流", "bpm": 92, "root": 55, "minor": False,
                    "chords": [0, 5, 9, 7, 5, 2, 7, 0], "duty": .5,
                    "motif": [12, 19, 16, -99, 14, 16, 19, -99, 21, 19, 16, 14, 12, -99, 7, -99]},
    "sky": {"title": "云端轻航", "bpm": 108, "root": 53, "minor": False,
            "chords": [0, 7, 9, 5, 4, 5, 7, 0], "duty": .25,
            "motif": [19, -99, 24, 23, 19, 16, 19, -99, 21, 19, 16, 14, 16, -99, 19, -99]},
    "underground": {"title": "深层寻路", "bpm": 80, "root": 40, "minor": True,
                    "chords": [0, 0, 8, 7, 5, 8, 7, 0], "duty": .125,
                    "motif": [12, -99, 7, -99, 15, 14, -99, 12, 10, -99, 7, 10, 11, -99, 12, -99]},
}

SCORES.update({'alpine': {'title': '越过苍脊',
            'bpm': 98,
            'root': 48,
            'minor': False,
            'chords': [0, 5, 9, 7, 4, 5, 7, 0],
            'duty': 0.25,
            'motif': [12, 19, 16, -99, 14, 21, 19, 16, 24, -99, 21, 19, 16, 14, 12, -99]},
 'snow_peak': {'title': '银冠之上',
               'bpm': 88,
               'root': 53,
               'minor': False,
               'chords': [0, 5, 9, 7, 4, 5, 7, 0],
               'duty': 0.5,
               'motif': [24, -99, 19, 21, 16, -99, 19, 14, 21, 24, -99, 26, 24, 19, 16, -99]},
 'snowfield': {'title': '寂光漫游',
               'bpm': 82,
               'root': 57,
               'minor': False,
               'chords': [0, 5, 9, 7, 4, 5, 7, 0],
               'duty': 0.125,
               'motif': [12, -99, 16, 19, -99, 21, 19, -99, 14, -99, 17, 21, 19, -99, 16, 12]},
 'ruined_city': {'title': '残墙间的风',
                 'bpm': 94,
                 'root': 45,
                 'minor': True,
                 'chords': [0, 5, 8, 7, 3, 5, 7, 0],
                 'duty': 0.25,
                 'motif': [12, 15, -99, 19, 17, 15, 10, -99, 12, -99, 7, 10, 14, -99, 15, 12]},
 'monument': {'title': '巨门回响',
              'bpm': 78,
              'root': 41,
              'minor': True,
              'chords': [0, 5, 8, 7, 3, 5, 7, 0],
              'duty': 0.5,
              'motif': [12, -99, 7, 12, 15, -99, 19, -99, 17, 15, 12, -99, 10, 7, 10, -99]},
 'ravine': {'title': '赤壁穿风',
            'bpm': 106,
            'root': 50,
            'minor': True,
            'chords': [0, 5, 8, 7, 3, 5, 7, 0],
            'duty': 0.125,
            'motif': [12, 19, -99, 17, 15, 12, 10, 7, 12, -99, 15, 19, 22, 19, 17, -99]},
 'gobi': {'title': '砾石疾行',
          'bpm': 116,
          'root': 46,
          'minor': True,
          'chords': [0, 5, 8, 7, 3, 5, 7, 0],
          'duty': 0.25,
          'motif': [12, 7, 12, -99, 15, 14, 10, -99, 17, 15, 14, 12, 10, 7, 10, -99]},
 'volcano': {'title': '玄焰跃动',
             'bpm': 122,
             'root': 40,
             'minor': True,
             'chords': [0, 5, 8, 7, 3, 5, 7, 0],
             'duty': 0.5,
             'motif': [12, 12, 15, 19, 10, -99, 14, 17, 12, 19, 22, -99, 19, 15, 14, 7]}})


def chunk(name, body):
    return name + struct.pack("<I", len(body)) + body + (b"\0" if len(body) % 2 else b"")


def pulse_table(duty):
    # Band-limited Fourier pulse removes DC and hard-edged aliasing.
    return [sum(2 * math.sin(math.pi * h * duty) / (math.pi * h)
                * math.cos(2 * math.pi * h * (i / TABLE - duty / 2))
                for h in range(1, 9)) for i in range(TABLE)]


def compose(name, score):
    step = 30.0 / score["bpm"]  # eighth note
    count = round(step * 128 * RATE)
    mix = [0.0] * count
    lead = pulse_table(score["duty"])
    arp = pulse_table(.5)
    triangle = [1 - 4 * abs(i / TABLE - .5) for i in range(TABLE)]
    rng = random.Random(30491 + list(SCORES).index(name))

    def note(start, duration, midi, volume, table):
        begin = round(start * RATE)
        size = min(round(duration * RATE), count - begin)
        frequency = 440 * 2 ** ((midi - 69) / 12)
        phase = 0.0
        increment = frequency * TABLE / RATE
        for k in range(size):
            t = k / RATE
            env = min(1, t / .004) * min(1, (size - 1 - k) / (RATE * .018))
            env *= .7 + .3 * math.exp(-t * 9)
            mix[begin + k] += table[int(phase) % TABLE] * env * volume
            phase += increment

    for tick in range(128):
        bar = tick // 8
        degree = score["chords"][bar // 2]
        tonic = score["root"] + degree
        third = 3 if score["minor"] and degree in [0, 5, 7] else 4
        start = tick * step
        melody = score["motif"][tick % 16]
        # Phrase development: higher B section, answer cadences, final tonic.
        if melody != -99:
            shift = degree if bar < 8 else [0, 3, 5, 7][(bar - 8) // 2]
            if bar >= 14:
                shift = 0
            if tick == 126:
                melody, shift = 12, 0
            note(start, step * .82, score["root"] + melody + shift, .16, lead)
        arp_note = [0, third, 7, 12][tick % 4]
        note(start, step * .65, tonic + 12 + arp_note, .055, arp)
        if tick % 2 == 0:
            note(start, step * 1.7, tonic - 12 + (7 if tick % 8 == 4 else 0), .17, triangle)
        # Kick, snare and soft hats have short attack/release, no noise bed.
        if tick % 4 == 0:
            length = int(.12 * RATE)
            phase = 0.0
            for k in range(length):
                t = k / RATE
                phase += 2 * math.pi * (48 + 85 * math.exp(-t * 55)) / RATE
                mix[round(start * RATE) + k] += math.sin(phase) * math.exp(-t * 40) * min(1, t / .002) * .18
        length = int((.085 if tick % 8 == 4 else .025) * RATE)
        low = 0.0
        for k in range(length):
            t = k / RATE
            low += .22 * (rng.uniform(-1, 1) - low)
            env = min(1, t / .001) * math.exp(-t * (65 if tick % 8 == 4 else 160))
            mix[round(start * RATE) + k] += low * env * (.15 if tick % 8 == 4 else .055)
    # One-step gap at the end plus per-note tails makes the loop boundary quiet.
    pcm = array.array("h", [round(max(-.95, min(.95, x)) * 32767) for x in mix])
    if sys.byteorder != "little":
        pcm.byteswap()
    fmt = struct.pack("<HHIIHH", 1, 1, RATE, RATE * 2, 2, 16)
    smpl = struct.pack("<9I", 0, 0, round(1e9 / RATE), 60, 0, 0, 0, 1, 0)
    smpl += struct.pack("<6I", 0, 0, 0, count - 1, 0, 0)
    body = b"WAVE" + chunk(b"fmt ", fmt) + chunk(b"smpl", smpl) + chunk(b"data", pcm.tobytes())
    path = DEST / (name + ".wav")
    path.write_bytes(b"RIFF" + struct.pack("<I", len(body)) + body)
    print(f"{name}: {score['title']} / {score['bpm']} BPM / {count / RATE:.2f}s / peak {max(abs(x) for x in mix):.3f}")


if __name__ == "__main__":
    DEST.mkdir(parents=True, exist_ok=True)
    for name, score in SCORES.items():
        compose(name, score)
    (DEST / "scores.json").write_text(json.dumps(SCORES, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
