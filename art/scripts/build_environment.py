"""Blender: independent tree silhouettes with paired LODs, reusing the expedition atlas."""
import sys, math, random
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
import build_assets as A
from math import sin,cos,pi

def make(family,low):
 A.reset(); bark=A.Mesh('Trunk'); leaves=A.Mesh('Foliage',True); rng=random.Random(811+['canopy_tree','split_tree','palm_tree','wind_pine'].index(family))
 def cluster(c,r,n):
  for i in range(n):
   a=rng.random()*2*pi; radius=rng.random()**.5*r
   p=(c[0]+cos(a)*radius,c[1]+rng.uniform(-.24,.24),c[2]+sin(a)*radius)
   if not low or i%3==0: leaves.leafshape(p,rng.uniform(.40,.68)*(1.4 if low else 1),rng.uniform(.13,.23)*(1.4 if low else 1),a,rng.uniform(-.1,.25),9 if i%4==0 else 8)
 if family=='canopy_tree':
  bark.tube([(0,0,0),(.06,.7,0),(-.08,1.8,.02),(.12,3.0,0),(.05,4.1,.08)],[.32,.24,.20,.14,.05],4,9)
  for i in range(5):
   a=i*2*pi/5+.3; bark.tube([(0,.75,0),(cos(a)*.37,.24,sin(a)*.37),(cos(a)*.75,.015,sin(a)*.75)],[.15,.11,.009],4,6)
  for i in range(7):
   a=i*2.4; r=1.10+(i%3)*.31; h=3.35+(i%3)*.25; tip=(cos(a)*r,h,sin(a)*r)
   bark.tube([(0,2.1,0),(tip[0]*.48,h-.22,tip[2]*.48),tip],[.13,.07,.012],4,6)
   cluster(tip,.58,23)
 elif family=='split_tree':
  bark.tube([(0,0,0),(-.04,.55,0),(.05,1.2,0)],[.23,.17,.12],4,8)
  for branch in [-1,1]:
   bark.tube([(.05,.85,0),(branch*.32,1.8,.08),(branch*.44,2.8,branch*.12)],[.14,.095,.024],4,8)
   for j in range(4):
    a=j*2.35+branch; tip=(branch*.35+cos(a)*.87,2.4+(j%2)*.62,sin(a)*.9)
    bark.tube([(branch*.26,1.6,0),(tip[0]*.8,tip[1]-.15,tip[2]*.8),tip],[.07,.035,.006],4,5)
    cluster(tip,.40,14)
 elif family=='palm_tree':
  bark.tube([(0,0,0),(.05,.6,0),(.18,1.6,.08),(.34,2.65,.12),(.42,3.45,.08)],[.22,.18,.145,.10,.075],4,10)
  for h in [i*.18+.3 for i in range(16)]:
   if not low: bark.tube([(.10*h-.06,h,0),(.10*h-.055,h+.045,0)],[.185-h*.022,.18-h*.022],4,8)
  for j in range(10):
   a=j*2*pi/10; tip=(.42+cos(a)*1.8,3.02+(.2 if j%2 else 0),.08+sin(a)*1.8)
   points=[(.42,3.42,.08),(.42+cos(a)*.8,3.78,.08+sin(a)*.8),tip]
   bark.tube(points,[.035,.022,.003],4,5)
   for k in range(2,10):
    f=k/10; c=(.42+cos(a)*1.8*f,3.42+.55*sin(f*pi)-.4*f,.08+sin(a)*1.8*f)
    for side in [-1,1]:
     if not low or k%2==0: leaves.leafshape(c,.55*sin(f*pi)+.14,.08*(1.45 if low else 1),a+side*.95,-.28,9 if j%4==0 else 8)
 else:
  bark.tube([(0,0,0),(.03,1,0),(.16,2,.08),(.35,3.1,.10),(.72,4.25,.13)],[.25,.19,.13,.085,.008],4,9)
  for tier in range(6):
   h=1.2+tier*.49; radius=1.26-tier*.15
   for j in range(5):
    a=j*2*pi/5+tier*.35; tip=(.12+cos(a)*radius+.28,h+.08,sin(a)*radius)
    bark.tube([(.12,h+.22,0),tip],[.045,.004],4,5)
    for k in range(3):
     f=.32+k*.28;c=(.12+(tip[0]-.12)*f,h+.18-f*.15,tip[2]*f)
     if not low or k!=1: leaves.leafshape(c,.58,.22*(1.25 if low else 1),a,.08,9 if tier%2 else 8)
 bark.object(); leaves.object(); A.export(family+('_lod' if low else ''))
for family in ['canopy_tree','split_tree','palm_tree','wind_pine']:
 for low in [False,True]:make(family,low)
