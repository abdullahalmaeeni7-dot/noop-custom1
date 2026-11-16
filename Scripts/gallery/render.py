import html,json,pathlib,zipfile
from PIL import Image,ImageDraw,ImageFont
root=pathlib.Path('build/gallery');manifest=json.loads((root/'manifest.json').read_text());photos=root/'photos';photos.mkdir(exist_ok=True)
try:font=ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc',14)
except OSError:font=ImageFont.load_default(size=14)
for item in manifest['screens']:
 image=Image.open(root/item['png']).convert('RGB');item['file']='photos/'+item['png'].replace('.png','.jpg');image.save(root/item['file'],quality=87,subsampling=0)
# Keep originals in CI's artifact, while the web gallery uses sharp JPEG images.
categories=list(dict.fromkeys(x['category'] for x in manifest['screens']));sheets=[]
for language in ['en','ar']:
 for category in categories:
  items=[x for x in manifest['screens'] if x['category']==category and x['language']==language]
  if not items:continue
  width=3*236+4*12;rows=(len(items)+2)//3;height=rows*548+12
  sheet=Image.new('RGB',(width,height),'#0B0D10');draw=ImageDraw.Draw(sheet)
  for index,item in enumerate(items):
   x=12+(index%3)*248;y=12+(index//3)*548
   title=item['title'];title=title if len(title)<34 else title[:31]+'…'
   draw.text((x,y),title,fill='white',font=font)
   image=Image.open(root/item['file']).resize((236,512),Image.Resampling.LANCZOS);sheet.paste(image,(x,y+24))
  name='sheet-'+str(categories.index(category)+1).zfill(2)+'-'+language+'.jpg';sheet.save(root/name,quality=90);sheets.append((category,language,name))
meta='Actual iPhone simulator captures. Synthetic sample data only. Camera/Bluetooth hardware, signed installation and production AI were not exercised. Live shows its simulator camera state; no camera feed is fabricated. The Coach conversation preview is explicitly illustrative. Features without implemented screens are not invented.'
readme=['# Every app screen — photo gallery','',meta,'',f"**{len(manifest['screens'])} captures · English + العربية.**",'','Download **WHOOP-all-screens.zip**, extract it, and open **index.html** for a searchable full-size gallery.','']
for category in categories:
 readme+=['## '+category,'']
 for c,language,name in sheets:
  if c==category:readme += [('### English' if language=='en' else '### العربية'),'',f'![{category} {language}]({name})','']
 readme+=['<details><summary>Open individual full-size images</summary>','']
 for item in manifest['screens']:
  if item['category']==category:readme += [f"- [{item['title']} · {item['language']}]({item['file']})"]
 readme+=['','</details>','']
if manifest['failures']:readme+=['## Captures needing attention','', '```json',json.dumps(manifest['failures'],indent=2),'```']
(root/'README.md').write_text('\n'.join(readme))
cards=[]
for item in manifest['screens']:
 caption=f"{item['title']} · {item['language']}";cards.append(f'<button class="card" data-lang="{item["language"]}" data-search="{html.escape(item["category"]+" "+item["title"],quote=True)}" data-src="{item["file"]}" data-title="{html.escape(caption,quote=True)}"><img loading="lazy" src="{item["file"]}" alt="{html.escape(caption,quote=True)}"><span>{html.escape(caption)}</span></button>')
page='''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>WHOOP · All screen photos</title><style>body{margin:0;background:#0b0d10;color:#f4f6f7;font:16px system-ui}header{padding:24px;position:sticky;top:0;background:#101517f5;z-index:2}h1{font-size:24px;margin:0 0 12px}p{color:#a4afb5;font-size:13px;max-width:1000px}input,select{font:inherit;padding:12px;border-radius:12px;background:#20272c;color:white;border:1px solid #45515a;margin:4px;min-height:44px}main{display:grid;grid-template-columns:repeat(auto-fill,minmax(210px,1fr));gap:18px;padding:20px}.card{background:#14181d;color:white;border:1px solid #2b3135;padding:10px;border-radius:16px;cursor:pointer;text-align:left}.card img{width:100%;border-radius:9px}.card span{display:block;padding:12px 4px}dialog{background:#0b0d10;color:white;border:1px solid #45515a;border-radius:16px;max-width:95vw;max-height:95vh;padding:12px}dialog::backdrop{background:#000d}dialog img{max-height:80vh;max-width:88vw;display:block;margin:auto}dialog button{padding:12px;background:#263239;color:white;border:0;border-radius:10px;min-width:44px;min-height:44px}#count{font-size:13px;color:#a4afb5}</style><header><h1>Every app screen · كل شاشات التطبيق</h1><p>__META__</p><input id="search" placeholder="Find a screen…" aria-label="Search screens"><select id="lang" aria-label="Language"><option value="all">English + العربية</option><option value="en">English</option><option value="ar">العربية</option></select><span id="count"></span></header><main>__CARDS__</main><dialog id="viewer"><button id="close" aria-label="Close">✕</button><span id="caption"></span><img id="large" alt=""></dialog><script>const cards=[...document.querySelectorAll('.card')],q=document.querySelector('#search'),lang=document.querySelector('#lang'),viewer=document.querySelector('#viewer');function filter(){let count=0;for(const c of cards){c.hidden=!(c.dataset.search.toLowerCase().includes(q.value.toLowerCase())&&(lang.value==='all'||c.dataset.lang===lang.value));if(!c.hidden)count++}document.querySelector('#count').textContent=count+' photos'}q.oninput=lang.onchange=filter;for(const c of cards)c.onclick=()=>{document.querySelector('#large').src=c.dataset.src;document.querySelector('#large').alt=c.dataset.title;document.querySelector('#caption').textContent=c.dataset.title;viewer.showModal()};document.querySelector('#close').onclick=()=>viewer.close();viewer.onclick=e=>{if(e.target===viewer)viewer.close()};filter();</script></html>'''.replace('__META__',html.escape(meta)).replace('__CARDS__',''.join(cards))
(root/'index.html').write_text(page);(root/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
with zipfile.ZipFile(root/'WHOOP-all-screens.zip','w',zipfile.ZIP_DEFLATED) as z:
 for p in [root/'index.html',root/'README.md',root/'manifest.json']+list(photos.glob('*.jpg'))+[root/name for _,_,name in sheets]:z.write(p,p.relative_to(root))
print('Gallery JPEG ZIP bytes:',(root/'WHOOP-all-screens.zip').stat().st_size)
