#!/usr/bin/env python3
"""Make Balance's placeholder sounds and music, and the sound bank that names them.

Run from the repo root:  python tools/make_sounds.py

Everything is synthesised here from tones and noise (numpy), so it is original and free of
licences. These are placeholders: the real sound comes in M10 or later, and replacing a sound
needs no code change, only another file in data/sounds/sound_bank.tres (or the same file name).

Writes assets/audio/<event>[_<n>].wav (mono, 16-bit, 22050 Hz) and data/sounds/sound_bank.tres,
which lists every event: its files (one is picked at random each time), its volume, how much its
pitch varies, its audio bus (Effects or Music) and the shortest time between two plays.
"""
import os
import wave

import numpy as np

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
AUDIO = os.path.join(ROOT, 'assets', 'audio')
BANK = os.path.join(ROOT, 'data', 'sounds', 'sound_bank.tres')
RATE = 22050
rng = np.random.default_rng(3)


# --- building blocks ---------------------------------------------------------------------------------
def t_of(seconds):
    return np.arange(int(seconds * RATE)) / RATE


def env(n, attack=0.005, release=None, curve=4.0):
    """An envelope: a quick rise, then an exponential fall over the whole length (or `release`)."""
    t = np.arange(n) / RATE
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    length = release or (n / RATE)
    return a * np.exp(-curve * t / length)


def tone(freq, seconds, kind='sine', vibrato=0.0):
    t = t_of(seconds)
    f = np.broadcast_to(np.asarray(freq, float), t.shape) if np.ndim(freq) else np.full(t.shape, float(freq))
    if vibrato:
        f = f * (1 + vibrato * np.sin(2 * np.pi * 5.5 * t))
    phase = 2 * np.pi * np.cumsum(f) / RATE
    if kind == 'square':
        return np.sign(np.sin(phase)) * 0.6
    if kind == 'saw':
        return ((phase / (2 * np.pi)) % 1.0) * 2 - 1
    if kind == 'tri':
        return 2 * np.abs(((phase / (2 * np.pi)) % 1.0) * 2 - 1) - 1
    return np.sin(phase)


def sweep(f0, f1, seconds):
    return np.geomspace(f0, f1, len(t_of(seconds)))


def noise(seconds, colour='white'):
    n = rng.standard_normal(len(t_of(seconds)))
    if colour == 'brown':
        n = np.cumsum(n)
        n -= np.convolve(n, np.ones(200) / 200, 'same')
        n /= np.max(np.abs(n)) + 1e-9
    return n


def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / RATE)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def at(x, seconds, total=None):
    """Delay a sound by `seconds` (padding with silence)."""
    pad = np.zeros(int(seconds * RATE))
    out = np.concatenate([pad, x])
    if total:
        out = np.concatenate([out, np.zeros(max(0, int(total * RATE) - len(out)))])[:int(total * RATE)]
    return out


def note(name):
    """'A4' -> Hz."""
    names = {'C': -9, 'C#': -8, 'D': -7, 'D#': -6, 'E': -5, 'F': -4, 'F#': -3, 'G': -2, 'G#': -1, 'A': 0,
             'A#': 1, 'B': 2}
    return 440.0 * 2 ** ((names[name[:-1]] + 12 * (int(name[-1]) - 4)) / 12)


def pluck(freq, seconds, bright=0.5):
    x = tone(freq, seconds, 'tri') * 0.6 + tone(freq * 2, seconds) * 0.25 * bright + tone(freq * 3, seconds) * 0.1 * bright
    return x * env(len(x), 0.004, seconds, 5.0)


def bell(freq, seconds):
    x = sum(tone(freq * r, seconds) * g for r, g in ((1, 1), (2.76, 0.4), (5.4, 0.2), (8.9, 0.1)))
    return x * env(len(x), 0.002, seconds, 6.0)


def norm(x, peak=0.8):
    return x / (np.max(np.abs(x)) + 1e-9) * peak


def write(name, x):
    x = np.clip(x, -1, 1)
    fade = min(len(x), int(0.004 * RATE))
    x[-fade:] *= np.linspace(1, 0, fade)
    with wave.open(os.path.join(AUDIO, name + '.wav'), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((x * 32767).astype('<i2').tobytes())


# --- the effects -------------------------------------------------------------------------------------
def click():
    x = mix(tone(1800, 0.03) * env(len(t_of(0.03)), 0.001, 0.03, 8), noise(0.01) * 0.3 * env(len(t_of(0.01)), 0.0005))
    return norm(x, 0.5)


def select(pitch):
    a = tone(note('E5') * pitch, 0.07, 'tri') * env(len(t_of(0.07)), 0.003, 0.07, 3)
    b = tone(note('B5') * pitch, 0.09, 'tri') * env(len(t_of(0.09)), 0.003, 0.09, 4)
    return norm(mix(a, at(b, 0.05)), 0.45)


def order(pitch):
    f = sweep(520 * pitch, 380 * pitch, 0.12)
    x = tone(f, 0.12, 'square') * env(len(f), 0.004, 0.12, 3)
    return norm(lowpass(x, 2200), 0.45)


def order_attack(pitch):
    x = mix(order(pitch * 0.85), at(order(pitch * 1.1) * 0.8, 0.07))
    return norm(x, 0.5)


def denied():
    a = tone(220, 0.09, 'square') * env(len(t_of(0.09)), 0.003, 0.09, 2)
    return norm(lowpass(mix(a, at(a, 0.12)), 1500), 0.4)


def hit(seed):
    local = np.random.default_rng(seed)
    clang = sum(tone(f * local.uniform(0.9, 1.1), 0.18) * g for f, g in ((1250, 0.6), (2730, 0.35), (3900, 0.2)))
    clang *= env(len(clang), 0.001, 0.18, 7)
    thud = noise(0.06) * env(len(t_of(0.06)), 0.001, 0.06, 6)
    return norm(mix(highpass(thud, 600) * 0.7, clang * 0.6), 0.6)


def shot():
    boom = tone(sweep(150, 45, 0.35), 0.35) * env(len(t_of(0.35)), 0.002, 0.35, 5)
    crack = noise(0.12) * env(len(t_of(0.12)), 0.0005, 0.12, 9)
    return norm(mix(boom, highpass(crack, 900) * 0.6, at(lowpass(noise(0.3, 'brown'), 900) * env(len(t_of(0.3)), 0.01) * 0.5, 0.1)), 0.75)


def explosion(seconds=0.9):
    body = lowpass(noise(seconds, 'brown'), 700) * env(len(t_of(seconds)), 0.004, seconds, 3.5)
    sub = tone(sweep(90, 30, seconds), seconds) * env(len(t_of(seconds)), 0.002, seconds, 4)
    crackle = highpass(noise(seconds), 2000) * (rng.random(len(t_of(seconds))) > 0.985) * env(len(t_of(seconds)), 0.01, seconds, 2)
    return norm(mix(body, sub * 0.8, crackle * 0.6), 0.85)


def death(seed):
    local = np.random.default_rng(seed)
    f = sweep(local.uniform(320, 380), 140, 0.25)
    voice = lowpass(tone(f, 0.25, 'saw'), 1200) * env(len(f), 0.01, 0.25, 3)
    fall = lowpass(noise(0.15), 500) * env(len(t_of(0.15)), 0.002, 0.15, 4)
    return norm(mix(voice * 0.6, at(fall, 0.12)), 0.5)


def mend():
    notes = ['C5', 'E5', 'G5', 'C6']
    x = mix(*[at(bell(note(n), 0.5) * 0.6, i * 0.07) for i, n in enumerate(notes)])
    return norm(x, 0.5)


def restore():
    t = 1.1
    chord = sum(tone(note(n), t, 'sine', 0.004) for n in ('D4', 'A4', 'D5', 'F#5', 'A5'))
    swell = np.sin(np.pi * np.clip(t_of(t) / t, 0, 1)) ** 1.5
    shimmer = highpass(noise(t), 4000) * 0.08 * swell
    return norm(mix(chord * swell, shimmer, at(bell(note('D6'), 0.6) * 0.4, 0.05)), 0.55)


def place():
    thud = tone(sweep(120, 55, 0.25), 0.25) * env(len(t_of(0.25)), 0.002, 0.25, 6)
    clunk = lowpass(noise(0.08), 1500) * env(len(t_of(0.08)), 0.001, 0.08, 6)
    return norm(mix(thud, clunk * 0.6, at(clunk * 0.4, 0.1)), 0.7)


def ready():
    return norm(mix(at(bell(note('G5'), 0.6), 0), at(bell(note('C6'), 0.7), 0.12)), 0.5)


def trained():
    horn = lambda f, s: lowpass(tone(f, s, 'saw'), 1600) * env(len(t_of(s)), 0.02, s, 2)
    return norm(mix(horn(note('G4'), 0.16), at(horn(note('D5'), 0.3), 0.15)), 0.5)


def low_power():
    beep = lambda f: lowpass(tone(f, 0.18, 'square'), 1800) * env(len(t_of(0.18)), 0.004, 0.18, 1.5)
    return norm(mix(beep(660), at(beep(440), 0.22), at(beep(330), 0.44)), 0.5)


def transform():
    f = sweep(90, 260, 0.45)
    whirr = lowpass(tone(f, 0.45, 'saw'), 900) * env(len(f), 0.03, 0.45, 1.2)
    clank = lowpass(noise(0.05), 2500) * env(len(t_of(0.05)), 0.001, 0.05, 6)
    return norm(mix(whirr * 0.6, at(clank, 0.0), at(clank, 0.42)), 0.5)


def repair():
    tap = lambda: highpass(noise(0.04), 1500) * env(len(t_of(0.04)), 0.0005, 0.04, 8) + \
        tone(2600, 0.04) * env(len(t_of(0.04)), 0.0005, 0.04, 9) * 0.5
    return norm(mix(tap(), at(tap(), 0.16), at(tap() * 0.8, 0.3)), 0.4)


def message():
    return norm(mix(bell(note('A5'), 0.45), at(bell(note('E5'), 0.5) * 0.7, 0.1)), 0.45)


def steal():
    return norm(mix(*[at(bell(note(n), 0.25) * 0.5, i * 0.05) for i, n in enumerate(('E6', 'C6', 'A5'))]), 0.4)


def victory():
    notes = [('C4', 0.0), ('G4', 0.18), ('C5', 0.36), ('E5', 0.54), ('G5', 0.72)]
    x = mix(*[at(lowpass(tone(note(n), 1.0, 'saw'), 2400) * env(len(t_of(1.0)), 0.02, 1.0, 2.5) * 0.4, s) for n, s in notes])
    x = mix(x, at(sum(tone(note(n), 1.4) for n in ('C4', 'E4', 'G4', 'C5')) * env(len(t_of(1.4)), 0.05, 1.4, 2) * 0.3, 0.9))
    return norm(x, 0.7)


def defeat():
    notes = [('A4', 0.0), ('F4', 0.3), ('D4', 0.6), ('A3', 0.9)]
    x = mix(*[at(lowpass(tone(note(n), 0.9, 'saw'), 1200) * env(len(t_of(0.9)), 0.03, 0.9, 2.5) * 0.45, s) for n, s in notes])
    return norm(x, 0.65)


# --- the music (two short loops) -----------------------------------------------------------------------
def loop_music(bpm, bars, chords, melody, drums, seconds_per_bar=None, pad_level=0.25, bass_oct=2):
    beat = 60.0 / bpm
    bar = seconds_per_bar or beat * 4
    total = bar * bars
    out = np.zeros(int(total * RATE) + RATE)
    for i in range(bars):
        root, third, fifth = chords[i % len(chords)]
        start = i * bar
        pad = sum(tone(note(n), bar * 1.05, 'tri', 0.003) for n in (root, third, fifth)) / 3
        pad = lowpass(pad, 1400) * np.sin(np.pi * np.clip(t_of(bar * 1.05) / (bar * 1.05), 0, 1)) ** 0.6
        out[int(start * RATE):int(start * RATE) + len(pad)] += pad * pad_level
        bass = pluck(note(root[:-1] + str(bass_oct)), bar * 0.95, 0.2)
        out[int(start * RATE):int(start * RATE) + len(bass)] += bass * 0.35
        # a harp-like arpeggio through the chord
        for k in range(8):
            n = (root, third, fifth, third)[k % 4]
            f = note(n[:-1] + str(int(n[-1]) + 1))
            p = pluck(f, beat * 1.2, 0.6) * 0.12
            s = int((start + k * beat / 2) * RATE)
            out[s:s + len(p)] += p[:len(out) - s]
    for start_beat, n, length in melody:
        p = pluck(note(n), beat * length * 1.3, 0.8) * 0.22
        s = int(start_beat * beat * RATE)
        if s < len(out):
            out[s:s + len(p)] += p[:len(out) - s]
    for start_beat, kind in drums:
        s = int(start_beat * beat * RATE)
        if kind == 'k':
            d = tone(sweep(110, 45, 0.22), 0.22) * env(len(t_of(0.22)), 0.001, 0.22, 6) * 0.5
        else:
            d = lowpass(noise(0.12), 3000) * env(len(t_of(0.12)), 0.001, 0.12, 7) * 0.18
        if s < len(out):
            out[s:s + len(d)] += d[:len(out) - s]
    # wrap the tail that rings past the end back onto the start, so the loop joins smoothly
    end = int(total * RATE)
    tail = out[end:]
    out = out[:end]
    out[:len(tail)] += tail
    return norm(out, 0.6)


def menu_music():
    chords = [('D4', 'F4', 'A4'), ('C4', 'E4', 'G4'), ('A#3', 'D4', 'F4'), ('A3', 'C#4', 'E4')]
    melody = []
    phrase = [('A4', 2), ('G4', 1), ('F4', 1), ('E4', 2), ('D4', 2), ('F4', 2), ('E4', 1), ('C4', 1), ('D4', 4)]
    beat = 0
    for rep in range(2):
        for n, length in phrase:
            melody.append((beat + 32 * rep, n, length))
            beat += length
        beat = 0
    return loop_music(66, 16, chords, melody, [], pad_level=0.3)


def mission_music():
    chords = [('E4', 'G4', 'B4'), ('E4', 'G4', 'B4'), ('C4', 'E4', 'G4'), ('D4', 'F#4', 'A4')]
    melody = []
    phrase = [('B4', 1), ('B4', 0.5), ('A4', 0.5), ('G4', 1), ('E4', 1), ('D4', 2), ('E4', 2),
              ('G4', 1), ('A4', 1), ('B4', 1), ('D5', 1), ('B4', 4)]
    beat = 16
    for n, length in phrase:
        melody.append((beat, n, length))
        beat += length
    drums = []
    for b in range(64):
        drums.append((b, 'k' if b % 4 in (0, 2) else 'h'))
        if b % 8 == 7:
            drums.append((b + 0.5, 'h'))
    return loop_music(96, 16, chords, melody, drums, pad_level=0.2)


# --- the bank ---------------------------------------------------------------------------------------------
# event -> (files, volume in dB, pitch variation (0.1 = up to 10% up or down), bus, shortest gap in seconds)
EVENTS = {
    'click': ([click()], -6.0, 0.0, 'Effects', 0.03),
    'select': ([select(1.0), select(1.12)], -6.0, 0.03, 'Effects', 0.08),
    'order': ([order(1.0), order(1.15)], -6.0, 0.03, 'Effects', 0.08),
    'order_attack': ([order_attack(1.0)], -5.0, 0.03, 'Effects', 0.08),
    'denied': ([denied()], -6.0, 0.0, 'Effects', 0.3),
    'hit': ([hit(1), hit(2), hit(3)], -10.0, 0.08, 'Effects', 0.05),
    'shot': ([shot()], -6.0, 0.08, 'Effects', 0.06),
    'death': ([death(1), death(2)], -8.0, 0.08, 'Effects', 0.08),
    'explosion': ([explosion(0.9)], -3.0, 0.08, 'Effects', 0.1),
    'wreck': ([explosion(1.6)], 0.0, 0.05, 'Effects', 0.2),
    'mend': ([mend()], -5.0, 0.0, 'Effects', 0.1),
    'restore': ([restore()], -4.0, 0.0, 'Effects', 0.2),
    'place': ([place()], -4.0, 0.03, 'Effects', 0.1),
    'ready': ([ready()], -4.0, 0.0, 'Effects', 0.3),
    'trained': ([trained()], -6.0, 0.0, 'Effects', 0.2),
    'low_power': ([low_power()], -5.0, 0.0, 'Effects', 3.0),
    'transform': ([transform()], -9.0, 0.05, 'Effects', 0.15),
    'repair': ([repair()], -10.0, 0.05, 'Effects', 0.5),
    'steal': ([steal()], -6.0, 0.0, 'Effects', 0.3),
    'message': ([message()], -5.0, 0.0, 'Effects', 0.3),
    'victory': ([victory()], -3.0, 0.0, 'Effects', 1.0),
    'defeat': ([defeat()], -3.0, 0.0, 'Effects', 1.0),
    'music_menu': ([menu_music()], -6.0, 0.0, 'Music', 0.0),
    'music_mission': ([mission_music()], -8.0, 0.0, 'Music', 0.0),
}


def write_bank(files):
    lines = ['[gd_resource type="Resource" script_class="SoundBank" load_steps=%d format=3]' % (2 + len(files) + 1 + len(EVENTS)), '']
    lines.append('[ext_resource type="Script" path="res://scripts/ui/sound_bank.gd" id="1"]')
    lines.append('[ext_resource type="Script" path="res://scripts/ui/sound_event.gd" id="2"]')
    ids = {}
    for i, name in enumerate(files):
        ids[name] = 'a%d' % i
        lines.append('[ext_resource type="AudioStream" path="res://assets/audio/%s.wav" id="%s"]' % (name, ids[name]))
    lines.append('')
    for event, (sounds, volume, pitch, bus, gap) in EVENTS.items():
        names = [event if len(sounds) == 1 else '%s_%d' % (event, i + 1) for i in range(len(sounds))]
        lines += ['[sub_resource type="Resource" id="e_%s"]' % event, 'script = ExtResource("2")', 'id = &"%s"' % event,
                  'streams = Array[AudioStream]([%s])' % ', '.join('ExtResource("%s")' % ids[n] for n in names),
                  'volume_db = %s' % volume, 'pitch_variation = %s' % pitch, 'bus = &"%s"' % bus,
                  'min_gap = %s' % gap, '']
    lines += ['[resource]', 'script = ExtResource("1")',
              'events = Array[ExtResource("2")]([%s])' % ', '.join('SubResource("e_%s")' % e for e in EVENTS), '']
    with open(BANK, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines))


def main():
    os.makedirs(AUDIO, exist_ok=True)
    os.makedirs(os.path.dirname(BANK), exist_ok=True)
    files = []
    for event, (sounds, *_rest) in EVENTS.items():
        for i, x in enumerate(sounds):
            name = event if len(sounds) == 1 else '%s_%d' % (event, i + 1)
            write(name, np.asarray(x, float))
            files.append(name)
    write_bank(files)
    print('wrote %d sounds and %s' % (len(files), BANK))


if __name__ == '__main__':
    main()
