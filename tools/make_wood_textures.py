"""Generate the original, tileable timber textures used by the half-pipe."""
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter
ROOT = Path(__file__).resolve().parents[1] / 'art/wooden_halfpipe/textures'
ROOT.mkdir(parents=True, exist_ok=True)
N = 1024
rng = np.random.default_rng(2506)
y, x = np.mgrid[0:N, 0:N].astype(float) / N

def noise(w,h):
    a = rng.uniform(0,255,(h,w)).astype('uint8')
    return np.asarray(Image.fromarray(a).resize((N,N),Image.Resampling.BICUBIC),dtype=float)/255-.5

# Periodic, gently wandering grain along the board. Image UVs are authored into meshes.
phase = x * 96 + .85*np.sin(y*2*np.pi) + .35*np.sin(y*6*np.pi+x*8*np.pi)
grain = np.sin(phase*2*np.pi)*.32 + np.sin(phase*4*np.pi+.5)*.12
broad = noise(35,6)*.7 + noise(160,12)*.23
fine = noise(500,200)*.07
field = grain*.075 + broad*.15 + fine
# Small, subtle oval grain around a pair of knots.
for kx,ky in [(.27,.39),(.76,.83)]:
    dx=(x-kx)*1.8; dy=(y-ky)*.32
    r=np.sqrt(dx*dx+dy*dy)
    field += np.sin(r*520)*np.exp(-r*48)*.055
    field -= np.exp(-(dx*dx*19000+dy*dy*38000))*.2
for name,base in [('plywood',(190,142,87)),('deck',(164,112,62)),('framing',(133,91,52)),('edge',(168,121,73))]:
    rgb=np.clip(np.array(base)[None,None,:]*(1+field[:,:,None]),0,255).astype('uint8')
    Image.fromarray(rgb).save(ROOT/f'{name}.png')
    rough=np.clip(185+field*65,120,230).astype('uint8')
    Image.fromarray(rough).save(ROOT/f'{name}_roughness.png')
print('Original timber textures written:',ROOT)
