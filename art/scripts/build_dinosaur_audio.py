"""Build animal-sample-based dinosaur calls (CaveboyTup, CC0).
Decode the two original MP3s with afconvert to LEI16@44100 WAV in art/audio/sources.
Python dependencies: numpy. Never rebuild from the retired oscillator sounds.
"""
from pathlib import Path
import wave,json,hashlib
import numpy as np
ROOT=Path(__file__).resolve().parents[2]; SRC=ROOT/'art/audio/sources'; OUT=ROOT/'godot/assets/audio'; RATE=44100
rng=np.random.default_rng(65019)
def read(name):
 with wave.open(str(SRC/name)) as w:
  assert w.getframerate()==RATE and w.getsampwidth()==2
  return np.frombuffer(w.readframes(w.getnframes()),dtype='<i2').reshape(-1,w.getnchannels()).mean(1)/32768.
def crop(a,start,end):return a[int(start*RATE):int(end*RATE)].copy()
def speed(a,factor):return np.interp(np.arange(0,len(a)-1,factor),np.arange(len(a)),a)
def join(a,b,seconds=.14):
 n=min(int(seconds*RATE),len(a),len(b));f=np.linspace(0,1,n)
 return np.concatenate([a[:-n],a[-n:]*(1-f)+b[:n]*f,b[n:]])
def equalize(a):
 f=np.fft.rfftfreq(len(a),1/RATE)
 # Remove sub rumble; keep the animal's rasp and projecting midrange intact.
 response=(1-np.exp(-(f/110)**4))*(.78+.65*np.exp(-.5*((f-1250)/1000)**2))
 response*=np.exp(-(f/10500)**6)
 return np.fft.irfft(np.fft.rfft(a)*response,n=len(a))
def finish(a):
 a=equalize(a-a.mean())
 a=np.tanh(a*2.4)*.60
 # Match loudness as well as peak, so clarity isn't just a louder playback.
 a*=min(.22/max(.0001,np.sqrt(np.mean(a*a))),.88/max(.0001,abs(a).max()))
 n=min(int(.012*RATE),len(a)//10);a[:n]*=np.linspace(0,1,n)
 n=min(int(.13*RATE),len(a)//8);a[-n:]*=np.linspace(1,0,n)
 return a
rex=read('t-rex_calls.wav');small=read('small_dino_raspy_calls.wav')
# These are the actual projecting roars, not the low growls in the first 25 seconds.
roars=[join(crop(rex,36.50,39.70),crop(rex,43.35,45.95)),join(crop(rex,26.45,29.80),crop(rex,32.75,35.35))]
snorts=[crop(small,.015,.96),crop(small,1.06,1.73)]
manifest=[]
for family in ['trex','young_trex','raptor','small_raptor']:
 for i in range(2):
  if family=='trex': a=speed(roars[i],1.08)
  elif family=='young_trex':a=speed(roars[1-i],1.40)
  elif family=='raptor':
   # Raspy exhalation followed by a compact animal throat accent; no sine/sub layer.
   throat=speed(crop(rex,37.0+i*.3,38.05+i*.3),1.8)*.52
   a=join(speed(snorts[i],.87),throat,.11)
  else:a=speed(snorts[i],1.12)
  a=finish(a);name=f'{family}_call_{i+1}'
  with wave.open(str(OUT/(name+'.wav')),'wb') as w:
   w.setnchannels(1);w.setsampwidth(2);w.setframerate(RATE);w.writeframes((a*32767).astype('<i2').tobytes())
  freq=np.fft.rfftfreq(len(a),1/RATE);power=abs(np.fft.rfft(a))**2
  manifest.append({'file':name+'.wav','seconds':round(len(a)/RATE,3),'peak':float(abs(a).max()),'rms':float(np.sqrt(np.mean(a*a))),'energy_above_500hz':float(power[freq>500].sum()/power.sum()),'sha256':hashlib.sha256((OUT/(name+'.wav')).read_bytes()).hexdigest(),'sources':['t-rex_calls.mp3'] if family in ['trex','young_trex'] else (['small_dino_raspy_calls.mp3','t-rex_calls.mp3'] if family=='raptor' else ['small_dino_raspy_calls.mp3'])})
(ROOT/'art/audio/dinosaur-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps(manifest,indent=2))
