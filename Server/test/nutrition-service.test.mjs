import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createNutritionService } from '../nutrition-server.mjs';
const accessToken='synthetic-personal-service-access-code';
async function fixture(t, options={}) {
 const calls=[];let clock=0;
 const handler=createNutritionService({accessToken,config:{provider:'gemini',apiKey:'synthetic-provider-key'},now:()=>clock,transport:async(url,init)=>{
  calls.push({url,init});return Response.json({candidates:[{content:{parts:[{text:JSON.stringify({items:[{name:'بيض',grams:100,kcal:144,protein:12,carbs:1,fat:10,confidence:.7}]})}]}}]});
 },...options});
 const server=createServer(handler);await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));t.after(()=>new Promise(resolve=>{server.close(resolve);server.closeAllConnections();}));
 const base='http://127.0.0.1:'+server.address().port;
 const request=(path,body,token=accessToken)=>fetch(base+path,{method:body===undefined?'GET':'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},...(body===undefined?{}:{body:JSON.stringify(body)})});
 return {request,calls,advance:()=>{clock+=60001;}};
}
test('private service health reveals no credentials and AI needs no WHOOP OAuth',async t=>{
 const {request,calls}=await fixture(t);
 assert.deepEqual(await (await request('/health',undefined,'wrong')).json(),{service:'nutrition-ai',version:1,configured:true});
 assert.equal((await request('/session',undefined,'wrong')).status,401);
 assert.deepEqual(await (await request('/session')).json(),{connected:true,configured:true});
 assert.equal((await request('/api/nutrition/parse-food',{text:'eggs'},'wrong')).status,401);assert.equal(calls.length,0);
 const result=await request('/api/nutrition/parse-food',{text:'بيضتان',language:'ar'});assert.equal(result.status,200);assert.equal((await result.json()).items[0].name,'بيض');assert.equal(calls.length,1);
});
test('service rejects malformed input, limits requests and recovers after its time window',async t=>{
 const {request,calls,advance}=await fixture(t);
 assert.equal((await request('/api/nutrition/parse-food',{text:'x'.repeat(40000)})).status,413);
 assert.equal((await request('/api/nutrition/parse-food',{text:''})).status,400);assert.equal(calls.length,0);
 for(let i=0;i<6;i++)assert.equal((await request('/api/nutrition/parse-food',{text:'eggs'})).status,200);
 assert.equal((await request('/api/nutrition/parse-food',{text:'eggs'})).status,429);
 advance();assert.equal((await request('/api/nutrition/parse-food',{text:'eggs'})).status,200);
});
test('missing Gemini config fails kindly without upstream calls and access codes must be strong',async t=>{
 const {request,calls}=await fixture(t,{config:{provider:'gemini'}});
 assert.equal((await (await request('/health')).json()).configured,false);
 const response=await request('/api/nutrition/parse-food',{text:'eggs'});assert.equal(response.status,503);assert.equal((await response.json()).error,'ai_not_configured');assert.equal(calls.length,0);
 assert.throws(()=>createNutritionService({accessToken:'short',config:{}}));
});
