from pathlib import Path
import json, math
import numpy as np
from PIL import Image, ImageDraw, ImageFont
import argparse,re
parser=argparse.ArgumentParser(description='Render the actual baked R6 pack and fixed weapon from pack.luau output.')
parser.add_argument('pack',type=Path);parser.add_argument('--out',type=Path)
args=parser.parse_args();src=args.pack;out=args.out or src;out.mkdir(parents=True,exist_ok=True)
combo=json.loads((src/'clips.json').read_text())[0]
weapon=json.loads((src/'weapon.json').read_text());geo=weapon['geometry'] if weapon else []
fontpath=next((str(p) for p in [Path('/System/Library/Fonts/Supplemental/Arial.ttf'),Path('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')] if p.exists()),None)
font=ImageFont.truetype(fontpath,17) if fontpath else ImageFont.load_default(); small=ImageFont.truetype(fontpath,13) if fontpath else font; title=ImageFont.truetype(fontpath,25) if fontpath else font
sizes={'Torso':(2,2,1),'Head':(1.25,1.25,1.25),'Right Arm':(1,2,1),'Left Arm':(1,2,1),'Right Leg':(1,2,1),'Left Leg':(1,2,1)}
colors={'Torso':(52,107,178),'Head':(241,198,91),'Right Arm':(241,198,91),'Left Arm':(241,198,91),'Right Leg':(53,114,87),'Left Leg':(53,114,87)}
verts=np.array([(x,y,z) for x in [-.5,.5] for y in [-.5,.5] for z in [-.5,.5]])
faces=[(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)]
labels=[f'{i+1:02d} / '+re.sub(r'(?<=[a-z])(?=[A-Z])',' ',m['value'].split('_',1)[-1]).upper() for i,m in enumerate(combo['markers']) if m['name'].startswith('Move')]
labels=[f'{j+1:02d} / '+s.split(' / ',1)[-1] for j,s in enumerate(labels)]
starts=[m['frame'] for m in combo['markers'] if m['name'].startswith('Move')]
hits=[m['frame'] for m in combo['markers'] if m['name']=='Hit']
def cf(a):return np.array(a[:3]),np.array(a[3:]).reshape(3,3)
def world(a,pt):p,r=cf(a);return p+r@np.array(pt)
def render(f,yaw=2.25,w=880,h=600,header=True):
 frame=combo['frames'][f]
 im=Image.new('RGB',(w,h),(18,24,34));d=ImageDraw.Draw(im)
 eye=np.array([math.sin(yaw)*.97,.25,math.cos(yaw)*.97]);eye/=np.linalg.norm(eye)
 right=np.cross([0,1,0],eye);right/=np.linalg.norm(right);up=np.cross(eye,right)
 center=np.array([0,1,-1.5]);scale=min(w/17,h/15)
 def project(p):a=np.array(p)-center;return (w*.5+a@right*scale,h*.55-a@up*scale)
 for i in range(-10,11):
  d.line([project((i,-3,-10)),project((i,-3,6))],fill=(32,43,57),width=1)
  d.line([project((-8,-3,i)),project((8,-3,i))],fill=(32,43,57),width=1)
 d.line([project((0,-2.99,4)),project((0,-2.99,-9))],fill=(54,96,116),width=2)
 polygons=[]
 def polygon(q,color):
  normal=np.cross(q[1]-q[0],q[2]-q[0]);n=np.linalg.norm(normal)
  if n<1e-8:return
  normal/=n
  shade=.7+.27*abs(normal@np.array([.4,.8,.45]))
  polygons.append((np.mean(q,axis=0)@eye,[project(v) for v in q],tuple(min(255,int(c*shade)) for c in color)))
 def box(p,r,size,color):
  vv=(verts*size)@r.T+p
  for face in faces:polygon(vv[list(face)],color)
 def ellipsoid(p,r,size,color):
  for i in range(10):
   for j in range(16):
    q=[]
    for a,b in [(i,j),(i+1,j),(i+1,j+1),(i,j+1)]:
     t=math.pi*a/10;u=math.pi*2*b/16
     pt=np.array([math.sin(t)*math.cos(u),math.cos(t),math.sin(t)*math.sin(u)])*np.array(size)/2
     q.append(p+r@pt)
    polygon(np.array(q),color)
 for part,size in sizes.items():
  p,r=cf(frame[part]);box(p,r,np.array(size),colors[part])
 # Two small eyes make the attack direction legible without extra rig parts.
 p,r=cf(frame['Head'])
 for x in [-.23,.23]:box(p+r@np.array([x,.12,-.632]),r,np.array([.085,.12,.012]),(24,32,42))
 for g in geo:
  p,r=cf(frame[weapon['parent']]);gp,gr=cf(weapon['grip']);lp,lr=cf(g['cf'])
  p=p+r@(gp+gr@lp);r=r@gr@lr;col=[c*255 for c in g['color']]
  if g['shape']=='Ball':ellipsoid(p,r,g['size'],col)
  else:box(p,r,np.array(g['size']),col)
 for _,pts,col in sorted(polygons,key=lambda x:x[0]):d.polygon(pts,fill=col)
 # Point trace, rather than a broad slashing ribbon.
 for hit in hits:
  if weapon and hit-4<=f<=hit+5:
   trail=[project(world(combo['frames'][j][weapon['parent']],weapon['tip'])) for j in range(max(hit-6,f-4),f+1)]
   if len(trail)>1:d.line(trail,fill=(101,224,245),width=3)
   if hit<=f<=hit+4:
    x,y=project(world(frame[weapon['parent']],weapon['tip']));d.ellipse((x-5,y-5,x+5,y+5),outline=(255,212,128),width=2)
 index=max(i for i,s in enumerate(starts) if s<=f)
 if header:
  d.text((28,22),re.sub(r'(?<=[a-z])(?=[A-Z])',' ',combo['name']).upper()+' / R6',font=title,fill=(233,242,251))
  d.text((28,61),labels[index],font=font,fill=(112,211,232))
  d.text((28,h-36),f'{len(hits)} CONNECTED ATTACKS  /  60 FPS  /  FRAME {f:03d}',font=small,fill=(146,167,191))
  for i in range(len(hits)):d.rectangle((w-144+i*28,33,w-125+i*28,38),fill=(111,212,232) if i<=index else (53,65,80))
 return im
frames=[render(0)]*8+[render(f) for f in range(0,len(combo['frames']),2)]+[render(len(combo['frames'])-1)]*12
frames[0].save(out/(combo['name']+'.gif'),save_all=True,append_images=frames[1:],duration=33,loop=0,optimize=True)
sheet=Image.new('RGB',(400*len(hits),850),(18,24,34))
for row,yaw in enumerate([math.pi,math.pi/2]):
 for col,hit in enumerate(hits):
  tile=render(hit,yaw,400,425,False);td=ImageDraw.Draw(tile)
  td.text((12,16),labels[col],font=small,fill=(112,211,232))
  td.text((12,399),('FRONT' if row==0 else 'SIDE')+f' / HIT F{hit}',font=small,fill=(157,178,201))
  sheet.paste(tile,(col*400,row*425))
sheet.save(out/'contact-sheet.png')
print('Rendered',len(frames),'frames; contact frames',hits)

# Weight is judged from the complete action, not four similar contact poses.
audit_file=src/'audit.json'
if audit_file.exists():
 audit=json.loads(audit_file.read_text())
 phases=[]
 for i,m in enumerate([m for m in combo['markers'] if m['name'].startswith('Move')]):
  a=audit.get(m['value'],{});h=a.get('heavy')
  if h:
   phases.append((i,m['frame'],[('LOAD',h['loadFrames']),('HIT',a['hit']),('OVERSWING',h['followThrough']),('RECOVERY',h['recoverEnd'])]))
 if phases:
  sheet=Image.new('RGB',(1600,350*len(phases)),(18,24,34))
  for row,offset,keys in phases:
   for col,(label,frame) in enumerate(keys):
    tile=render(offset+frame,2.25,400,350,False);d=ImageDraw.Draw(tile)
    d.text((12,12),f'{row+1:02d} / {label} F{frame}',font=small,fill=(112,211,232))
    sheet.paste(tile,(col*400,row*350))
  sheet.save(out/'phase-sheet.png')
