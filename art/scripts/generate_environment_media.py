"""Original procedural audio and tileable ground micro-surfaces. No licensed samples.
Run with the bundled Python runtime (numpy + Pillow). Outputs are runtime assets.
"""
from pathlib import Path
import json,wave
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]; OUT=ROOT/'godot/assets/audio'; TEX=ROOT/'godot/assets/materials'; RATE=32000
rng=np.random.default_rng(190965)
def normalize(x,peak=.84):return x*peak/max(.000001,np.max(np.abs(x)))
def save(name,x,loop=False,overlap_seconds=1.0):
 x=np.asarray(x); x=np.clip(x,-.98,.98)
 if loop:
  overlap=min(int(RATE*overlap_seconds), x.shape[0]//3)
  if overlap > 0:
   blend=np.linspace(0.0,1.0,overlap,endpoint=False)
   if x.ndim == 1:
    x[:overlap]=x[-overlap:]*(1.0-blend)+x[:overlap]*blend
   else:
    x[:overlap]=x[-overlap:]*(1.0-blend[:,None])+x[:overlap]*blend[:,None]
   x=x[:-overlap]
 with wave.open(str(OUT/(name+'.wav')),'wb') as f:
  f.setnchannels(1 if x.ndim==1 else x.shape[1]); f.setsampwidth(2); f.setframerate(RATE);f.writeframes((x*32767).astype('<i2').tobytes())
def band_noise(n,lo,hi):
 f=np.fft.rfftfreq(n,1/RATE); spec=np.fft.rfft(rng.normal(size=n)); filt=(1-np.exp(-(f/max(lo,1))**4))*np.exp(-(f/hi)**4)
 x=np.fft.irfft(spec*filt,n=n);return x/max(.001,np.std(x))
# Dinosaur calls are built separately from CC0 animal samples by build_dinosaur_audio.py.
for name,lo,hi,level in [('wind_breeze',90,3200,.16),('wind_gale',35,4000,.30),('rain',750,11000,.23)]:
 n=RATE*12;t=np.arange(n)/RATE; channels=[]
 for channel in range(2):
  x=band_noise(n,lo,hi); slow=band_noise(n,1,3);slow=normalize(slow,1)
  x*=.65+.20*np.sin(t*2*np.pi/12+channel*.6)+.15*slow
  if name=='rain':
   # Sparse canopy droplets layered over a steady broad hiss.
   drops=np.zeros(n)
   for _ in range(180):
    start=int(rng.integers(0,n-1500));count=1200;tt=np.arange(count)/RATE
    drops[start:start+count]+=np.sin(tt*2*np.pi*rng.uniform(1400,3600))*np.exp(-tt*80)*rng.uniform(.05,.25)
   x=x*.4+drops
  channels.append(normalize(x,level))
 save(name,np.stack(channels,axis=1),loop=True)

# A second ambience layer gives the weather mix a location-specific bed. It
# remains sparse so dinosaur calls and interface feedback stay intelligible.
for name,night in [('jungle_day',False),('jungle_night',True)]:
 n=RATE*18;t=np.arange(n)/RATE;channels=[]
 for channel in range(2):
  floor=band_noise(n,55 if night else 85,1800 if night else 4200)
  drift=band_noise(n,.4,2.0)
  x=floor*(.08+.025*np.sin(t*2*np.pi/18+channel*.8)) + drift*.018
  if night:
   # Irregular insect pulses, offset in each channel for a wide stereo bed.
   for start in rng.integers(0,n-9000,size=16):
    width=int(rng.integers(2200,7000)); end=min(n,int(start)+width)
    tt=np.arange(end-int(start))/RATE
    pulse=np.maximum(0,np.sin(tt*2*np.pi*rng.uniform(7.5,12.0)))**14
    x[int(start):end]+=pulse*rng.uniform(.012,.028)
   for start in rng.integers(0,n-16000,size=5):
    width=int(rng.integers(5000,15000)); end=min(n,int(start)+width)
    tt=np.arange(end-int(start))/RATE
    x[int(start):end]+=np.sin(2*np.pi*rng.uniform(180,300)*tt)*np.exp(-tt*1.8)*rng.uniform(.012,.024)
  else:
   # Short bird/insect gestures are deliberately occasional, not a melody.
   for start in rng.integers(0,n-12000,size=13):
    width=int(rng.integers(1800,5500)); end=min(n,int(start)+width)
    tt=np.arange(end-int(start))/RATE
    glide=rng.uniform(1700,2800)+rng.uniform(-350,350)*tt
    gesture=np.sin(2*np.pi*glide*tt)*np.sin(np.pi*tt/max(tt[-1],.01))**1.3
    x[int(start):end]+=gesture*rng.uniform(.012,.026)
  channels.append(normalize(x,.14 if night else .16))
 save(name,np.stack(channels,axis=1),loop=True)
for k in range(2):
 n=RATE*(5+k);t=np.arange(n)/RATE
 low=band_noise(n,22,260); crack=band_noise(n,350,4500)
 envelope=(1-np.exp(-t*25))*np.exp(-t*.85)
 x=low*envelope*.5+crack*np.exp(-t*9)*.3
 for delay,gain in [(.6,.22),(1.3,.17),(2.2,.1)]:
  shift=int(delay*RATE);x[shift:]+=low[:-shift]*envelope[:-shift]*gain
 x*=np.minimum(1,(t[-1]-t)/.25)
 left=normalize(x,.76);right=np.roll(left,230)*.94
 right[:230]=0
 save('thunder_'+str(k+1),np.stack([left,right],axis=1))
# Four independent seamless grayscale surfaces in RGBA: soil, grass, rock, litter.
N=512; f=np.fft.fftfreq(N);freq=np.sqrt(f[:,None]**2+f[None,:]**2)
def noise(scale):
 x=np.fft.ifft2(np.fft.fft2(rng.normal(size=(N,N)))*np.exp(-(freq*scale)**2)).real
 return (x-x.mean())/max(.001,x.std())
a=noise(12);b=noise(4);c=noise(1.5);y,x=np.mgrid[:N,:N]
soil=np.clip(.5+a*.085+b*.07+c*.025,0,1)
grass=np.clip(.5+noise(7)*.055+b*.11+c*.05,0,1)
rock=np.clip(.5+noise(28)*.13+noise(6)*.09+np.sin(x*2*np.pi/64+noise(24)*.6)*.05,0,1)
litter=np.clip(.5+noise(18)*.08+np.maximum(0,b-.6)*.14,0,1)
TEX.mkdir(exist_ok=True,parents=True)
Image.fromarray((np.stack([soil,grass,rock,litter],axis=-1)*255).astype('uint8'),'RGBA').save(TEX/'ground_detail.png')
print('Generated 7 weather audio assets and seamless 512x512 material channels.')
