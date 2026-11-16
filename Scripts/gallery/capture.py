import json,os,pathlib,subprocess,time
root=pathlib.Path('.');out=root/'build/gallery';out.mkdir(parents=True,exist_ok=True)
routes=json.loads((root/'Scripts/gallery/routes.json').read_text());device=os.environ['SIM_DEVICE'];bundle='local.whoop.reconstruction';app='build/GalleryDerived/Build/Products/Release-iphonesimulator/WHOOP.app'
def call(*args,check=True):
 return subprocess.run(args,check=check,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,timeout=90).stdout.strip()
manifest={'source':os.environ['GITHUB_SHA'],'run':os.environ['GITHUB_RUN_ID'],'device':'iPhone 15 Pro','sample_data':True,'hardware_camera_test':False,'ai_provider_test':False,'screens':[],'failures':[]}
for language in ['en','ar']:
 call('xcrun','simctl','terminate',device,bundle,check=False)
 call('xcrun','simctl','uninstall',device,bundle,check=False)
 call('xcrun','simctl','install',device,app)
 container=pathlib.Path(call('xcrun','simctl','get_app_container',device,bundle,'data'))
 subprocess.run(['python3','Scripts/gallery/prepare.py',str(container)],check=True)
 command=container/'Documents/gallery-command.json'
 (container/'Documents/gallery-ready.json').unlink(missing_ok=True)
 call('xcrun','simctl','launch',device,bundle,'--gallery-screen',routes[0]['route'],'-whoop.language.v1',language,'-AppleLanguages','('+language+')')
 for index,item in enumerate(routes):
  route=item['route'];ready=container/'Documents/gallery-ready.json'
  if index:ready.unlink(missing_ok=True)
  try:
   command.write_text(json.dumps({'route':route}))
   deadline=time.monotonic()+30
   while time.monotonic()<deadline:
    try:
     if json.loads(ready.read_text()).get('route')==route:break
    except (OSError,ValueError):pass
    time.sleep(.2)
   else:raise RuntimeError('Screen did not signal readiness')
   time.sleep(.45)
   name=f'{index+1:02d}-{route}-{language}.png'
   call('xcrun','simctl','io',device,'screenshot',str(out/name))
   manifest['screens'].append({**item,'language':language,'png':name})
   print(f'Captured {language} {index+1}/{len(routes)}: {route}',flush=True)
  except Exception as error:
   manifest['failures'].append({'route':route,'language':language,'error':str(error)[:500]});print(f'Capture failed: {language} {route}',flush=True)
  finally:
   (out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(f"Captured {len(manifest['screens'])} screens; {len(manifest['failures'])} failures",flush=True)
