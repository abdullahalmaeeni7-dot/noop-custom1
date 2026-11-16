import datetime as dt,json,math,pathlib,sys,uuid
root=pathlib.Path(sys.argv[1]); documents=root/'Documents';documents.mkdir(exist_ok=True)
uid=lambda:str(uuid.uuid4()).upper()
iso=lambda d:d.isoformat().replace('+00:00','Z')
base=dt.datetime(2026,11,9,tzinfo=dt.timezone.utc); days=[];foods=[];weights=[];activities=[];completed=[]
for i in range(30):
 d=base-dt.timedelta(days=29-i);key=d.date().isoformat();recovery=[43,29,44,29,54,50,38][i%7];strain=[9.5,10.7,14.5,5.6,9.6,5.3,15.8][i%7]
 if i==29:recovery=38;strain=15.8
 heart=[dict(timestamp=iso(d+dt.timedelta(hours=8,minutes=j*3)),bpm=round(69+9*math.sin(j*.23)+(35 if 30<j<45 else 0),1)) for j in range(130)]
 days.append(dict(date=iso(d),recovery=recovery,strain=strain,sleepPerformance=33 if i==29 else 70+i%24,sleepMinutes=224 if i==29 else 405+i%60,sleepNeededMinutes=680 if i==29 else 510,restingHeartRate=58+i%4,hrv=122-i%13,respiratoryRate=19.7,steps=26783 if i==29 else 8500+i*200,energyKcal=2886 if i==29 else 2400+i*10,heartRates=heart,source='imported'))
 menu=[('breakfast','Greek yogurt and oats',380,29,43,11,280),('lunch','Chicken rice bowl',620,48,73,15,440),('dinner','Salmon and sweet potato',650,46,62,24,420),('snack','Apple and almonds',210,7,23,13,150)]
 for meal,name,kcal,protein,carbs,fat,grams in menu:
  foods.append(dict(id=uid(),day=key,meal=meal,createdAt=iso(d+dt.timedelta(hours=12)),food=dict(name=name,grams=grams,kcal=kcal+(i%5)*12,protein=protein,carbs=carbs,fat=fat)))
 weights.append(dict(id=uid(),day=key,value=round(78.7-i*.045+.12*math.sin(i),2),unit='kg'));completed.append(key)
 if i>22:
  activities.append(dict(id=uid(),start=iso(d+dt.timedelta(hours=18)),durationMinutes=42,name='Walking',strain=5.4,strainIsEstimate=False))
activities += [dict(id=uid(),start=iso(base+dt.timedelta(hours=9)),durationMinutes=29,name='Soccer',strain=11.9,strainIsEstimate=False),dict(id=uid(),start=iso(base+dt.timedelta(hours=19,minutes=37)),durationMinutes=24,name='Soccer',strain=8.8,strainIsEstimate=False)]
nutrition=dict(foods=foods,exercises=[dict(id=uid(),day=base.date().isoformat(),name='Evening walk',kcal=210,minutes=42,estimated=True)],weights=weights,favorites=[dict(id=uid(),food=foods[-1]['food']),dict(id=uid(),food=foods[-4]['food'])],completedDays=completed,settings=dict(age=28,sex='male',height=180,weight=78,units='metric',activity='moderate',goal='lose',proteinOverride=155))
state=dict(version=1,days=days,activities=activities,journal=[dict(date=iso(base),caffeine=True,alcohol=False,lateMeal=False,note='Morning coffee, an evening walk, and dinner before 8 PM.')],selectedDate=iso(base),profile=dict(displayName='Alex Taylor',username='alex.t',age='28',whoopAge='25.4',dayStreakOverride=41),nutrition=nutrition)
(documents/'whoop-local-data.json').write_text(json.dumps(state))
