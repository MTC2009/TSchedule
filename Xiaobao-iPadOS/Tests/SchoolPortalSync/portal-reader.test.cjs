'use strict';
const test=require('node:test'), assert=require('node:assert/strict'), fs=require('node:fs'), path=require('node:path'), vm=require('node:vm');
const {webcrypto}=require('node:crypto');
const source=name=>fs.readFileSync(path.join(__dirname,'../../Sources/Native/SchoolPortalSync',name+'.js'),'utf8');
const here='https://tsinglanstudent.schoolis.cn';
const paths={owner:'/api/MemberShip/GetCurrentStudentInfo',terms:'/api/School/GetSchoolSemesters',
    week:'/api/Schedule/ListScheduleByParent', grades:'/api/DynamicScore/GetStuSemesterDynamicScore',
    gpa:'/api/DynamicScore/GetGpa',detail:'/api/DynamicScore/GetDynamicScoreDetail',tasks:'/api/LearningTask/GetList',
    summary:'/api/Attendance/GetAttendanceStatistic',subjects:'/api/Attendance/GetSubjectAttendanceStatistic',
    records:'/api/Attendance/GetAttendanceStatisticDetail',subjectRecords:'/api/Attendance/GetSubjectAttendanceDetail'};
const term={id:42,isNow:true,year:2024,semester:2,startDate:'2025-02-01',endDate:'2025-06-30'};
function harness(handlers={},origin=here) {
    const calls=[], location={origin,pathname:'/Home'}, window={}; window.top=window;
    const document={readyState:'complete'};
    const sandbox={window,location,document,URL,TextEncoder,crypto:webcrypto,AbortController,setTimeout,clearTimeout,
        fetch:async(raw,opts)=>{
            const u=new URL(raw); assert.equal(u.origin,here);assert.equal(opts.credentials,'same-origin');
            assert.equal(opts.redirect,'manual');assert.equal(opts.cache,'no-store');
            const k=Object.keys(paths).find(k=>paths[k]===u.pathname);assert.ok(k);
            calls.push(k); const fn=handlers[k];
            const data=fn ? await fn(u,opts) : k==='owner'?{loginName:'fixture-learner',orgId:10}:k==='terms'?[term]:undefined;
            if(data===undefined)throw Error('unexpected operation');
            if(data instanceof Response)return data;
            return Response.json({state:0,data});
        }};
    const context=vm.createContext(sandbox), p=vm.runInContext('('+source('PortalProjection')+')()',context),
        read=vm.runInContext('('+source('PortalRead')+')',context);
    const run=(op,args={},expected='')=>read(op,args,expected,'noncredential-fixture-namespace',p);
    return {run,calls,location,document,window,p,owner:async()=>(await run('identity')).owner};
}
const range={from:'2025-02-16',to:'2025-02-22'};
const countSample={totalCount:2,attendanceRate:50,sataeCountList:[{attendanceState:0,count:1},{attendanceState:2,count:1}]};
test('attendance uses the student page’s dates and published fields; no grades, student ID or roster request',async()=>{
    const h=harness({summary:(u,o)=>{
        assert.equal(o.method,'GET'); assert.deepEqual(Object.fromEntries(u.searchParams),{
            BeginTime:term.startDate+' 00:00:00',EndTime:term.endDate+' 23:59:59',AttendanceType:'7'});
        return countSample;
    }, subjects:()=>[{subjectId:16,subjectName:'Ceramics',normalCount:1,lateCount:0,earlyLeaveCount:1,absentCount:0,privateField:'not-forwarded'}]});
    const r=await h.run('attendance',{category:'classroom',page:1},await h.owner());
    assert.equal(r.value.rate,0.5);assert.equal(r.value.counts.early,1);assert.equal(r.value.courses[0].name,'Ceramics');
    assert.equal(r.value.courses[0].id,'16');assert.ok(!JSON.stringify(r).includes('not-forwarded'));
    assert.deepEqual(h.calls,['owner','owner','terms','summary','subjects','owner']);
});
test('native attendance distinguishes empty, invalid, denied and changed student',async()=>{
    const args={category:'classroom',page:1};
    for(const [data,error] of [[{totalCount:0,sataeCountList:[]},null],[{totalCount:5,sataeCountList:[]},'format'],
        [{totalCount:1,sataeCountList:[{attendanceState:21,count:1}]},'format'],[null,'format'],
        [Response.json({}, {status:403}),'denied']]) {
        const h=harness({summary:()=>data,subjects:()=>[]});const r=await h.run('attendance',args,await h.owner());
        if(error)assert.equal(r.error,error);else {assert.equal(r.value.counts.present,0);assert.equal(r.value.rate,null);}
    }
    let reads=0; const h=harness({owner:()=>({userId:++reads<3?10:11}),summary:()=>countSample,subjects:()=>[]});
    assert.equal((await h.run('attendance',args,await h.owner())).error,'changed');
});
test('daily, activity and selected-course details use bounded pages, official state codes and no private notes',async()=>{
    for(const [kind,code] of [['daily',1],['activity',2],['classroom',7]]) {
        const detail=kind==='classroom';
        const h=harness({summary:()=>countSample,[detail?'subjectRecords':'records']:(u)=>{
            assert.equal(u.searchParams.get('Page.PageIndex'),'1');assert.equal(u.searchParams.get('Page.PageSize'),'10');
            assert.equal(u.searchParams.get('BeginTime'),range.from+' 00:00:00');
            assert.equal(u.searchParams.get('AttendanceType'),detail?null:String(code));
            assert.equal(u.searchParams.get('SubjectId'),detail?'16':null);
            return {totalCount:1,list:[{attendanceId:99,subjectId:16,subjectName:'Ceramics',className:'Studio',
                activityTitle:'Field day',attendanceTime:'2025-02-18',beginTime:'2025-02-18 08:00:00',endTime:'2025-02-18 09:00:00',
                attendanceState:3,isExcused:true,reason:'never-export'}]};
        }});
        const r=await h.run(detail?'attendanceSubject':'attendance',{...range,category:kind,page:1,...(detail?{subject:'16'}:{})},await h.owner());
        assert.equal(r.value.records[0].status,'absent');assert.equal(r.value.recordTotal,1);
        assert.ok(!JSON.stringify(r).includes('never-export'));
    }
    for(const args of [{category:'other',page:1},{category:'daily',page:0},{category:'daily',page:1,from:'2025-02-30',to:range.to},
        {category:'classroom',page:2},{category:'classroom',page:1,status:'late'},{category:'daily',page:1,status:'unknown'}]) {
        const h=harness();assert.equal((await h.run('attendance',args,await h.owner())).error,'format');
        assert.ok(!h.calls.includes('summary'));
    }
});
test('daily status narrows just the detail page, not the published totals',async()=>{
    const h=harness({summary:u=>{assert.equal(u.searchParams.has('AttendanceState'),false);return countSample;},
        records:u=>{assert.equal(u.searchParams.get('AttendanceState'),'1');return {totalCount:0,list:[]};}});
    const r=await h.run('attendance',{category:'daily',page:1,status:'late'},await h.owner());
    assert.equal(r.value.counts.early,1);assert.equal(r.value.recordTotal,0);
});
test('week uses the real date range, converts Shanghai time, and exports neither profile nor extraneous fields',async()=>{
    const h=harness({week:(u,o)=>{
        assert.equal(o.method,'POST');assert.deepEqual(JSON.parse(o.body),{beginTime:range.from,endTime:range.to});
        return [{id:7,scheduleType:4,name:'Field drawing',beginTime:'2025-02-18T08:30:00',endTime:'2025-02-18T09:15:00',
            playgroundName:'Studio',classInfo:{id:9},unusedPrivateField:'must-not-leave'}];
    }});
    const out=await h.run('week',range,await h.owner());
    assert.equal(out.value[0].start,'2025-02-18T00:30:00.000Z');assert.equal(out.value[0].kind,'lesson');
    assert.equal(out.value[0].room,'Studio');assert.ok(!JSON.stringify(out).includes('fixture-learner'));
    assert.ok(!JSON.stringify(out).includes('must-not-leave'));assert.deepEqual(h.calls,['owner','owner','week','owner']);
});
test('a valid empty week and an unrecognized response have different results',async()=>{
    for(const [payload,ok] of [[[],true],[{},false],[[{scheduleType:3,name:'Incomplete'}],false],[[{scheduleType:17}],false]]) {
        const h=harness({week:()=>payload});const r=await h.run('week',range,await h.owner());
        assert.equal(ok?r.value.length:r.error,ok?0:'format');
    }
});
test('a non-Home frame cannot read or diagnose session expiry', async()=>{
    for(const h of [harness({},'https://different.invalid'),harness()]){
        if(h.location.origin===here) h.window.top={};
        assert.equal((await h.run('identity')).error,'unavailable');assert.equal(h.calls.length,0);
    }
    const login=harness();login.location.pathname='/Account/Login';
    assert.equal((await login.run('identity')).error,'unavailable');assert.equal(login.calls.length,0);
});
test('a loading Home makes no request and a completed document can subsequently read',async()=>{
    const h=harness();h.document.readyState='loading';
    assert.equal((await h.run('identity')).error,'notReady');assert.deepEqual(h.calls,[]);
    h.document.readyState='complete';assert.equal((await h.owner()).length,64);assert.deepEqual(h.calls,['owner']);
});
test('only an explicit authentication rejection is an expiry signal', async()=>{
    for(const [response,code] of [[Response.json({state:999901,data:null}),'expired'],[new Response(null,{status:401}),'expired'],
        [Response.json({state:999902,data:null}),'denied'],[new Response(null,{status:403}),'denied'],
        [Object.defineProperty(new Response(null),'type',{value:'opaqueredirect'}),'unavailable'],
        [new Response('<html>',{headers:{'Content-Type':'text/html'}}),'format'],
        [new Response('{broken',{headers:{'Content-Type':'application/json'}}),'format']]){
        const h=harness({week:()=>response});assert.equal((await h.run('week',range,await h.owner())).error,code);
    }
    for(const [response,code] of [[Response.json({state:17,data:null}),'unavailable'],[Response.json({state:0}),'format'],
        [Response.json(null),'format'],[new Response(null,{status:503}),'network']]){
        assert.equal((await harness({owner:()=>response}).run('identity')).error,code);
    }
});
test('switching accounts mid-read drops the whole result, not just its identity',async()=>{
    let account='synthetic-a';const h=harness({owner:()=>({userId:account}),week:()=>{account='synthetic-b';return [];}});
    const r=await h.run('week',range,await h.owner());assert.equal(r.error,'changed');assert.equal(r.value,undefined);
});
test('preserve real zero in grade summary; no calendar/task read triggers a grade request',async()=>{
    const h=harness({grades:()=>({studentSemesterDynamicScoreBasicDtos:[{classId:9,subjectId:3,subjectName:'Typography',scoreType:1,subjectScore:0,subjectTotalScore:80}]}),gpa:()=>0});
    const r=await h.run('grades',{},await h.owner());assert.equal(r.value.courses[0].score.earned,0);
    assert.equal(r.value.courses[0].score.possible,80);assert.equal(r.value.gpa,0);
    assert.deepEqual(h.calls,['owner','owner','terms','grades','gpa','owner']);
});
test('only positively published detail marks leave the isolated world; category weight is not task weight',async()=>{
    const h=harness({detail:()=>({evaluationProjectList:[{evaluationProjectName:'Paper',proportion:30,scoreIsNull:true,score:942,
        learningTaskAndExamList:[
            {type:1,name:'Exam A',isPublish:false,score:991},
            {type:2,name:'Exercise B',isSynchroToMobiled:false,score:992},
            {type:2,name:'Exercise C',isSynchroToMobiled:true,scoreType:1,score:0,totalScore:20},
            {type:1,name:'Exam D',isPublish:true,resultType:4,levelString:'Pass',score:993},
            {type:1,name:'Exam E',isPublish:true,disciplineState:3,score:994}]}]})});
    const r=await h.run('detail',{term:'42',subject:'3',cls:'9',type:1},await h.owner());
    const g=r.value[0];assert.equal(g.weight,.3);assert.equal(g.mark,null);
    assert.equal(g.items[0].score,null);assert.equal(g.items[1].score,null);
    assert.equal(g.items[2].score.earned,0);assert.equal(g.items[3].score.value,'Pass');assert.equal(g.items[4].score,null);
    assert.doesNotMatch(JSON.stringify(r),/942|991|992|993|994/);
});
test('task paging verifies completeness; fields unrelated to submissions never cross the bridge',async()=>{
    let count=0;
    const h=harness({tasks:url=>{
        assert.equal(Number(url.searchParams.get('PageIndex')),++count);assert.equal(url.searchParams.get('SemesterId'),'42');
        return {totalCount:2,list:[{id:count===1?91:20,name:'Workshop '+count,learningTaskState:count===1?2:3,
            subjectName:'Design',endTime:'2025-02-21 18:00:00',publishTime:count===1?null:'2025-02-19 09:30:00',
            score:997,studentAnswer:'private draft'}]};
    }});
    const r=await h.run('tasks',{},await h.owner());assert.equal(r.value.rows.length,2);
    assert.equal(r.value.rows[1].status,'submitted');assert.equal(r.value.rows[1].due,'2025-02-21T10:00:00.000Z');
    assert.deepEqual(Array.from(r.value.rows,x=>x.id),['91','20']);
    assert.equal(r.value.rows[0].published,null);assert.equal(r.value.rows[1].published,'2025-02-19T01:30:00.000Z');
    assert.doesNotMatch(JSON.stringify(r),/997|private draft/);assert.ok(!h.calls.includes('grades'));
    const repeated=harness({tasks:()=>({totalCount:2,list:[{id:5,name:'Repeat',learningTaskState:2}]})});
    assert.equal((await repeated.run('tasks',{},await repeated.owner())).error,'format');
});
test('task-list marks require consent and the student list release gate; a numeric zero is not missing',async()=>{
    const base={id:3,name:'Colour mixing',mode:0,learningTaskState:4,isSynchroToMobiled:1,scoreType:1,score:0,totalScore:16};
    const list=[base,{...base,id:4,mode:'0',learningTaskState:3,scoreType:2,levelString:'Pass',score:879},
        {...base,id:5,isSynchroToMobiled:0,score:878},{...base,id:6,mode:1,score:877},
        {...base,id:7,isExempt:true,score:876},{...base,id:8,score:null,totalScore:875}];
    const h=harness({tasks:()=>({totalCount:list.length,list})}), owner=await h.owner();
    for(const includeScores of [undefined,false,'true']) {
        const r=await h.run('tasks',{includeScores},owner);
        assert.ok(r.value.rows.every(x=>x.score==null));
    }
    const r=await h.run('tasks',{includeScores:true},owner), [zero,level,withheld,lite,excused,missing]=r.value.rows;
    assert.equal(zero.score?.earned,0);assert.equal(zero.score?.possible,16);
    assert.equal(level.score?.value,'Pass');assert.equal(level.grading,'graded');
    assert.equal(withheld.grading,'graded_unpublished');
    for(const row of [withheld,lite,excused,missing]) assert.equal(row.score,null);
    assert.doesNotMatch(JSON.stringify(r),/879|878|877|876|875/);
    assert.ok(h.calls.every(name=>['owner','terms','tasks'].includes(name)));
});
test('masked or unsupported task rows never even read the mark fields',()=>{
    const {p}=harness();
    const base={id:6,name:'Layer study',mode:0,learningTaskState:4,isSynchroToMobiled:1,scoreType:1,
        get score(){assert.fail('read withheld mark');},get levelString(){assert.fail('read withheld level');},
        get totalScore(){assert.fail('read withheld maximum');}};
    const change=overrides=>Object.assign(Object.create(base),overrides);
    for(const flag of [undefined,null,false,0,true,'1',2]) assert.equal(p.task(change({isSynchroToMobiled:flag}),true).score,null);
    for(const row of [change({mode:1}),change({mode:null}),change({scoreType:3}),change({isExempt:1})])
        assert.equal(p.task(row,true).score,null);
    assert.equal(p.task(base,false).score,null);assert.equal(p.task(change({learningTaskState:1}),true),null);
});
test('no current term does not substitute an old term; unknown reads cannot choose a network target',async()=>{
    const h=harness({terms:()=>[{...term,isNow:false}]});
    assert.equal((await h.run('grades',{},await h.owner())).error,'term');assert.ok(!h.calls.includes('grades'));
    const x=harness();assert.equal((await x.run('https://different.invalid',{},await x.owner())).error,'format');
});
test('a GPA-specific refusal does not erase available published course totals',async()=>{
    const h=harness({grades:()=>({studentSemesterDynamicScoreBasicDtos:[{classId:4,subjectId:2,subjectName:'Study',scoreType:2,levelString:'P'}]}),
        gpa:()=>new Response(null,{status:403})});
    const r=await h.run('grades',{},await h.owner());
    assert.equal(r.value.gpaUnavailable,true);assert.equal(r.value.gpa,null);
    assert.equal(r.value.courses[0].score.value,'P');
});
test('an impossible date cannot roll over onto another school day',async()=>{
    const h=harness({week:()=>[{id:5,scheduleType:3,name:'Workshop',beginTime:'2025-02-30T08:00:00',endTime:'2025-02-30T09:00:00'}]});
    assert.equal((await h.run('week',range,await h.owner())).error,'format');
});
test('expiry strictly inside optional GPA or at the final identity check discards all old marks',async()=>{
    for(const atEnd of [false,true]) {
        let reads=0;
        const expiry=()=>Response.json({state:999901,data:null});
        const h=harness({owner:()=> (++reads===3 && atEnd) ? expiry() : {userId:8},
            grades:()=>({studentSemesterDynamicScoreBasicDtos:[{classId:4,subjectId:2,subjectName:'Print',scoreType:2,levelString:'P'}]}),
            gpa:()=>atEnd?2.8:expiry()});
        const r=await h.run('grades',{},await h.owner());
        assert.equal(r.error,'expired');assert.equal(r.value,undefined);
    }
});
test('placeholder student identifiers never collapse distinct school accounts',async()=>{
    const onlyPlaceholder=harness({owner:()=>({studentId:0,userId:'0000'})});
    assert.equal((await onlyPlaceholder.run('identity')).error,'format');
    const a=harness({owner:()=>({studentId:0,loginName:'fixture-a'})});
    const b=harness({owner:()=>({studentId:0,loginName:'fixture-b'})});
    assert.notEqual(await a.owner(),await b.owner());
});
test('only explicit enrollment returns the current verified login name, never for a different account',async()=>{
    const h=harness({owner:()=>({orgId:4,userId:5,loginName:'fixture-press',ignored:'not-for-the-app'})});
    const first=await h.run('identity');
    assert.deepEqual(Object.keys(first),['owner']);
    const enrolled=await h.run('enrollmentName',{},first.owner);
    assert.equal(enrolled.value,'fixture-press');assert.equal(enrolled.owner,first.owner);
    assert.doesNotMatch(JSON.stringify(enrolled),/not-for-the-app/);
    assert.equal((await h.run('enrollmentName',{},'unbound')).error,'changed');
    const empty=harness({owner:()=>({userId:3})});
    assert.equal((await empty.run('enrollmentName',{},await empty.owner())).error,'unavailable');
});
