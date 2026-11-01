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
# What the arrows changed while the carousel is open, so Escape can put it back.
RESOLUTION_UNDO=CACHE/'resolution-undo.json'
CONFIG=Path(os.environ.get('XDG_CONFIG_HOME') or H/'.config')/'omarchy/ambient'
MAX_RESOLUTION_STEPS=4
MIN_FPS,MAX_FPS=20,240
# Running scenes watch this file and draw their frame rate while it exists.
FPS_COUNTER=Path(os.environ.get('XDG_CACHE_HOME') or H/'.cache')/'omarchy-ttfx-layer/show-fps'

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

def resolution_conf(source):
    return CONFIG/(source+'.conf')

def conf_value(source,key):
    path=resolution_conf(source)
    lines=path.read_text().splitlines() if path.exists() else []
    values=[l.split('=',1)[1].strip() for l in lines if l.strip().startswith(key) and '=' in l]
    return values[-1] if values else ''

def set_conf_value(source,key,value):
    path=resolution_conf(source)
    lines=path.read_text().splitlines() if path.exists() else []
    lines=[l for l in lines if not l.strip().startswith(key)]
    if value:lines.append(f'{key}={value}')
    if lines:
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_text('\n'.join(lines)+'\n')
    else:path.unlink(missing_ok=True)

def resolution_steps(source):
    value=conf_value(source,'resolution')
    try:return int(value.removeprefix('auto')) if value.startswith('auto') else 0
    except ValueError:return 0

def set_resolution_steps(source,steps):
    set_conf_value(source,'resolution',f'auto{steps:+d}' if steps else '')

def fps_limit(source):
    value=conf_value(source,'fps')
    return int(value) if value.isdigit() and MIN_FPS<=int(value)<=MAX_FPS else MIN_FPS

def set_fps_limit(source,fps):
    set_conf_value(source,'fps',str(fps) if fps!=MIN_FPS else '')

def catalog_item(item_id):
    item=next((i for i in choices('screensaver') if i['id']==item_id),None)
    if item is None:raise ValueError('unknown ASCII effect')
    return item

def remember_for_undo(source):
    undo=json.loads(RESOLUTION_UNDO.read_text()) if RESOLUTION_UNDO.exists() else {'status':capture(AMBIENT,'status'),'confs':{}}
    if source not in undo['confs']:
        path=resolution_conf(source)
        undo['confs'][source]=path.read_text() if path.exists() else None
    CACHE.mkdir(parents=True,exist_ok=True)
    RESOLUTION_UNDO.write_text(json.dumps(undo))

def store_tuning(item,steps,fps):
    set_resolution_steps(item['source'],max(-MAX_RESOLUTION_STEPS,min(MAX_RESOLUTION_STEPS,steps)))
    set_fps_limit(item['source'],max(MIN_FPS,min(MAX_FPS,fps)))

def tune(item,steps,fps):
    remember_for_undo(item['source'])
    store_tuning(item,steps,fps)
    if not for_screensaver():apply('screensaver',item)

def revert_tuning():
    if not RESOLUTION_UNDO.exists():return
    undo=json.loads(RESOLUTION_UNDO.read_text())
    RESOLUTION_UNDO.unlink()
    for source,text in undo['confs'].items():
        path=resolution_conf(source)
        if text is None:path.unlink(missing_ok=True)
        else:path.write_text(text)
    if for_screensaver():return
    state=undo['status'].split(maxsplit=1)
    if not state or state[0]=='none':run(AMBIENT,'stop')
    else:run(AMBIENT,'start',state[0],state[1] if len(state)>1 else '')

def toggle_fps_counter():
    if FPS_COUNTER.exists():FPS_COUNTER.unlink()
    else:
        FPS_COUNTER.parent.mkdir(parents=True,exist_ok=True)
        FPS_COUNTER.touch()

def active_category():
    source=capture(AMBIENT,'status').split(maxsplit=1)
    source=source[0] if source else 'none'
    if source=='amiga':return 'amiga'
    if source in ("screensaver","ttfx","matrix-reactive","eye-reactive","tunnel-reactive","neon-city","vector-highway","circuit-run","sunset-drive","live-terminal","data-globe","aquarium","jellyfish","cockpit","sand-clock","sand-clock-chladni","sand-clock-dunes","sand-clock-galaxy"):return "background"
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
    if len(args)==2 and args[0]=='--tune-get':
        source=catalog_item(args[1])['source']
        print(resolution_steps(source),fps_limit(source));return
    if len(args)==4 and args[0]=='--tune':
        tune(catalog_item(args[1]),int(args[2]),int(args[3]));return
    if args==['--fps-counter']:
        toggle_fps_counter();return
    if args==['--fps-counter-get']:
        print('1' if FPS_COUNTER.exists() else '0');return
    if args==['--tune-revert']:
        revert_tuning();return
    if len(args) in (2,4) and args[0]=='--apply-ascii':
        item=catalog_item(args[1])
        RESOLUTION_UNDO.unlink(missing_ok=True)
        if len(args)==4:store_tuning(item,int(args[2]),int(args[3]))
        if for_screensaver():
            TARGET.unlink(missing_ok=True)
            run(AMBIENT,'screensaver','--set',item['source'],item.get('choice',''))
        else:apply('screensaver',item)
        return
    if args==['--picking-for']:
        print('screensaver' if for_screensaver() else 'background');return
    if args==['--current-category']:
        print(active_category());return
    if args==['current']:args=[active_category()]
    if len(args)==2 and args[0]=='--list':
        print(json.dumps(choices(args[1]),ensure_ascii=False,indent=2));return
    if len(args)!=1 or args[0] not in ('background','screensaver','saver','theme','amiga','random'):
        raise ValueError('usage: omarchy-ambient-select background|screensaver|theme|amiga|random|current')
    category={'saver':'screensaver'}.get(args[0],args[0])
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
        RESOLUTION_UNDO.unlink(missing_ok=True)
        if category=='screensaver':TARGET.write_text('screensaver')
        else:TARGET.unlink(missing_ok=True)
        run('omarchy-shell','-q','avillagran.ambient-selector','toggle')

if __name__=='__main__':
    try:main(sys.argv[1:])
    except (ValueError,OSError,subprocess.CalledProcessError) as e:
        print('Background selector: '+str(e),file=sys.stderr);sys.exit(1)
