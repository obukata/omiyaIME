# Temporary 8-bit style sounds for Omiya's walk, made from scratch (no source material).
import sys, wave, numpy as np
RATE=22050; out=sys.argv[1]
def save(name, x):
    x=np.clip(x,-1,1); d=(x*32767).astype('<i2')
    with wave.open(f'{out}/{name}.wav','wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE); w.writeframes(d.tobytes())
rng=np.random.default_rng(7)
# Dig: a short scrape of earth. Noise, smoothed to sound low, quick fade.
n=int(RATE*0.13); t=np.arange(n)/RATE
noise=rng.uniform(-1,1,n); k=np.ones(6)/6; low=np.convolve(noise,k,'same')
env=np.minimum(t/0.008,1)*np.exp(-t/0.04)
save('dig', 0.55*low*env)
# Find: a little rising square-wave jingle.
def square(f, dur, vol):
    m=int(RATE*dur); tt=np.arange(m)/RATE
    s=np.sign(np.sin(2*np.pi*f*tt))
    return vol*s*np.minimum(tt/0.004,1)*np.exp(-tt/(dur*0.9))
notes=[(784,0.07),(1047,0.07),(1319,0.07),(1568,0.07),(2093,0.28)]
save('find', np.concatenate([square(f,d,0.18) for f,d in notes]))
