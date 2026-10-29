import test from 'node:test';
import assert from 'node:assert/strict';
import { createHandler } from './handler.ts';

const env = { get: (key: string) => ({ SUPABASE_URL: 'https://test.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'service-test', GEMINI_API_KEY: 'secret-test', GEMINI_MODEL: 'test-model' }[key]) };
const body = () => ({ token: 'admin-token', forecast: { current: 10, capacity: 20, target_time: Date.now()/1000+1800, predicted: 15, probability: .7 } });
const req = (data: unknown) => new Request('http://local', { method: 'POST', body: JSON.stringify(data) });

test('rejects missing auth and invalid probabilities without calling providers', async () => {
  const handler = createHandler(env, async () => { throw new Error('must not call'); });
  assert.equal((await handler(req({}))).status, 401);
  const bad = body(); bad.forecast.probability=9;
  assert.equal((await handler(req(bad))).status, 400);
});
test('auth failure never calls Gemini', async () => {
  let calls=0;
  const handler=createHandler(env,async()=>{calls++;return Response.json({message:'unauthorized'},{status:403});});
  assert.equal((await handler(req(body()))).status,403); assert.equal(calls,1);
});
test('sends only numeric facts, no token or identifiers to Gemini', async () => {
  let calls=0;
  const handler=createHandler(env,async(url,options)=>{
    calls++;
    if(calls===1) return Response.json({capacity:20});
    assert.match(String(url),/generativelanguage.googleapis.com/);
    assert.equal((options!.headers as Record<string,string>)['x-goog-api-key'],'secret-test');
    assert.ok(!String(options!.body).includes('admin-token'));
    assert.ok(!String(options!.body).includes('inject me'));
    return Response.json({candidates:[{content:{parts:[{text:'Perkiraan ini bukan kepastian.'}]}}]});
  });
  const response=await handler(req({...body(),prompt:'inject me'}));
  assert.equal(response.status,200);
  assert.equal((await response.json()).explanation,'Perkiraan ini bukan kepastian.');
});
test('provider quota and missing configuration return actionable errors',async()=>{
  let calls=0;
  const handler=createHandler(env,async()=>++calls===1?Response.json({capacity:20}):Response.json({}, {status:429}));
  assert.equal((await handler(req(body()))).status,502);
  const missing=createHandler({get:(k)=>k==='GEMINI_API_KEY'?undefined:env.get(k)},async()=>Response.json({capacity:20}));
  assert.equal((await missing(req(body()))).status,503);
});
test('rate limit and changed capacity stop provider calls',async()=>{
  const limited=createHandler(env,async()=>Response.json({message:JSON.stringify({status:429})},{status:400}));
  assert.equal((await limited(req(body()))).status,429);
  const changed=createHandler(env,async()=>Response.json({capacity:30}));
  assert.equal((await changed(req(body()))).status,409);
});
