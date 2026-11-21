'use strict';
const test=require('node:test'), assert=require('node:assert/strict'), vm=require('node:vm');
const fs=require('node:fs'), path=require('node:path');
const js=fs.readFileSync(path.join(__dirname,'../../Sources/Native/SchoolPortalLogin/PortalLogin.js'),'utf8');
const official='https://tsinglanstudent.schoolis.cn';
function page() {
    let clicks=0, secretWrites=0;
    function element() { return {isConnected:true,getClientRects:()=>[{}],form:null,
        dispatchEvent(){},hasAttribute:()=>false,getAttribute:()=>null}; }
    const name=Object.assign(element(),{type:'text',placeholder:'请输入用户名'});
    const pass=Object.assign(element(),{type:'password',placeholder:'请输入密码'});
    Object.defineProperty(pass,'value',{get(){throw Error('must not read an existing password');},set(v){if(v)secretWrites++;}});
    const button=Object.assign(element(),{tagName:'BUTTON',type:'submit',innerText:'登录',click(){clicks++;}});
    const spec={fields:[name,pass],buttons:[button],challenge:false};
    const document={baseURI:official,readyState:'complete',body:{innerText:'普通学生入口'},
        querySelector:()=>spec.challenge?{}:null,querySelectorAll:selector=>selector.startsWith('input:')?spec.fields:
            selector.startsWith('button,')?spec.buttons:[]};
    const location=new URL(official), window={};window.top=window;
    const run=vm.runInNewContext('('+js+')',{document,location,window,URL,Event,getComputedStyle:()=>({visibility:'visible'})});
    return {run,location,window,document,name,pass,button,spec,counts:()=>[clicks,secretWrites]};
}
test('the recognized page uses its own button once and never reads a web password',async()=>{
    const p=page();
    assert.equal(await p.run('probe'),'ready');assert.deepEqual(p.counts(),[0,0]);
    assert.equal(await p.run('submit','fixture','synthetic'),'submitted');
    assert.equal(await p.run('submit','fixture','synthetic'),'blocked');assert.deepEqual(p.counts(),[1,1]);
    assert.equal(await p.run('clear'),'cleared');assert.equal(p.name.value,'');
});
test('no credential reaches alternate login pages, redirects, frames, challenges or changed forms',async()=>{
    for (const change of [
        p=>p.location.hostname='another.invalid',p=>p.location.protocol='http:',p=>p.location.port='444',
        p=>p.location.pathname='/Account/Reset',p=>p.location.search='?return=/elsewhere',p=>p.window.top={},
        p=>p.document.baseURI='https://unrelated.invalid/',p=>p.spec.challenge=true,
        p=>p.document.body.innerText='请完成安全验证',p=>p.pass.form={method:'GET'},
        p=>p.spec.fields.push(p.name),p=>p.spec.buttons.push(p.button),p=>p.pass.readOnly=true,
        p=>p.button.hasAttribute=()=>true,p=>p.name.placeholder='other',p=>p.pass.placeholder='new',
    ]) {
        const p=page();change(p);
        assert.equal(await p.run('submit','fixture','synthetic'),'blocked');assert.deepEqual(p.counts(),[0,0]);
    }
});
test('recheck the controls during handoff; never click through disabled UI or a newly appearing challenge',async()=>{
    const p=page();p.name.dispatchEvent=()=>{p.spec.challenge=true};
    assert.equal(await p.run('submit','fixture','synthetic'),'blocked');assert.deepEqual(p.counts(),[0,0]);
    const disabled=page();disabled.button.disabled=true;
    assert.equal(await disabled.run('submit','fixture','synthetic'),'blocked');assert.deepEqual(disabled.counts(),[0,0]);
});
