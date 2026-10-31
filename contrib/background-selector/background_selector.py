#!/usr/bin/env python3
"""Local Ambient selector: use the stock image picker and owned source choices."""
import json, os, random, subprocess, sys
from pathlib import Path
H=Path.home()
DATA=H/'.local/share/omarchy-ambient'
CACHE=H/'.cache/omarchy/ambient-selector'
CATALOG=Path(__file__).resolve().with_name('catalog.json')
AMBIENT=H/'.local/bin/omarchy-ambient'
# The carousel picks for the background or for the screensaver: same scenes, same engine.
TARGET=CACHE/'target'

def run(*args):
    subprocess.run([str(x) for x in args],check=True)

def capture(*args):
    p=subprocess.run([str(x) for x in args],text=True,stdout=subprocess.PIPE)
    return p.stdout.strip() if p.returncode==0 else ''

def choices(category):
    if category=='screensaver':return json.loads(CATALOG.read_text())
    if category=='amiga':
        out=[]
        for p in sorted((DATA/'amiga/demos').glob('*/config.json')):
            try:title=json.loads(p.read_text()).get('title',p.parent.name)
            except (ValueError,OSError):continue
            out.append({'id':p.parent.name,'label':title,'source':'amiga','choice':p.parent.name})
        return out
    if category=='theme':
        theme_file=H/'.local/state/omarchy/current/theme.name'
        theme=theme_file.read_text().strip() if theme_file.exists() else ''
        roots=[H/'.local/state/omarchy/current/theme/backgrounds',H/'.config/omarchy/backgrounds'/theme]
        out=[];seen=set()
        for root in roots:
            if not root.is_dir():continue
            for p in sorted(root.iterdir()):
                if p.is_file() and p.suffix.lower() in ('.png','.jpg','.jpeg','.webp','.avif','.gif','.bmp','.mp4','.webm'):
                    key=str(p.resolve())
                    if key not in seen:out.append({'id':key,'label':p.stem,'path':key});seen.add(key)
        return out
    raise ValueError('unknown category')

def apply(category,item):
    if category=='theme':
        path=Path(item['path'])
        if not path.is_file():raise ValueError('background no longer available')
        run(AMBIENT,'stop');run('omarchy-theme-bg-set',path)
    else:run(AMBIENT,'start',item['source'],item.get('choice',''))

def active_category():
    source=capture(AMBIENT,'status').split(maxsplit=1)
    source=source[0] if source else 'none'
    if source=='amiga':return 'amiga'
    if source in ("screensaver","ttfx","matrix-reactive","eye-reactive","tunnel-reactive","neon-city","vector-highway","circuit-run","sunset-drive","live-terminal","data-globe","city-rain","jellyfish","cockpit","hourglass","sand-clock","sand-clock-chladni","sand-clock-dunes","sand-clock-galaxy"):return "screensaver"
    return 'theme'

def for_screensaver():
    return TARGET.exists()

def main(args):
    if args==['--preview-list']:
        for i in choices('screensaver'):
            print('\t'.join(['audio',i['id'],i['label'],str(CACHE/i.get('poster',i['id']+'.jpg')),'',i['id']]))
        return
    if args==['--current-choice']:
        if for_screensaver():
            print(capture(AMBIENT,'screensaver','--get'));return
        state=capture(AMBIENT,'status').split(maxsplit=1)
        source=state[0] if state else 'none'
        print(state[1][3:] if len(state)>1 and state[1].startswith('fx:') else source)
        return
    if len(args)==2 and args[0]=='--apply-ascii':
        item=next((i for i in choices('screensaver') if i['id']==args[1]),None)
        if item is None:raise ValueError('unknown ASCII effect')
        if for_screensaver():
            TARGET.unlink(missing_ok=True)
            run(AMBIENT,'screensaver','--set',item['source'],item.get('choice',''))
        else:apply('screensaver',item)
        return
    if args==['--current-category']:
        print(active_category());return
    if args==['current']:args=[active_category()]
    if len(args)==2 and args[0]=='--list':
        print(json.dumps(choices(args[1]),ensure_ascii=False,indent=2));return
    if len(args)!=1 or args[0] not in ('theme','screensaver','saver','amiga','random'):
        raise ValueError('usage: omarchy-ambient-background-select theme|screensaver|saver|amiga|random|current')
    category=args[0]
    if category=='random':
        available={k:choices(k) for k in ('theme','screensaver','amiga')}
        available={k:v for k,v in available.items() if v}
        if not available:raise ValueError('no backgrounds available')
        category=random.SystemRandom().choice(list(available))
        item=random.SystemRandom().choice(available[category]);apply(category,item)
        subprocess.run(['notify-send','-a','omarchy-ambient','Random background',category.title()+': '+item['label']],check=False)
    elif category=='theme':
        picked=capture('omarchy-theme-bg-switcher')
        if picked:apply(category,{'path':picked})
    elif category=='amiga':run(AMBIENT,'start','amiga')
    else:
        CACHE.mkdir(parents=True,exist_ok=True)
        if category=='saver':TARGET.write_text('screensaver')
        else:TARGET.unlink(missing_ok=True)
        run('omarchy-shell','-q','avillagran.ambient-selector','toggle')

if __name__=='__main__':
    try:main(sys.argv[1:])
    except (ValueError,OSError,subprocess.CalledProcessError) as e:
        print('Background selector: '+str(e),file=sys.stderr);sys.exit(1)
