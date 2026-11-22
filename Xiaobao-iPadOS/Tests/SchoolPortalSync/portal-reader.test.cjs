'use strict';
const test=require('node:test'), assert=require('node:assert/strict'), fs=require('node:fs'), path=require('node:path'), vm=require('node:vm');
const {webcrypto}=require('node:crypto');
const source=name=>fs.readFileSync(path.join(__dirname,'../../Sources/Native/SchoolPortalSync',name+'.js'),'utf8');
const here='https://tsinglanstudent.schoolis.cn';
const paths={exams:'/api/Exam/GetList',evaluations:'/v2/basic/CareerAssessment/MyAssessments',resources:'/v2/clouddisk/StudentShare/SharedToMePagedList',owner:'/api/MemberShip/GetCurrentStudentInfo',terms:'/api/School/GetSchoolSemesters',
    week:'/api/Schedule/ListScheduleByParent', grades:'/api/DynamicScore/GetStuSemesterDynamicScore',
    material:'/api/LearningTask/GetDetail',gpa:'/api/DynamicScore/GetGpa',detail:'/api/DynamicScore/GetDynamicScoreDetail',tasks:'/api/LearningTask/GetList',
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
            playgroundName:'Studio',classInfo:{id:9,name:'Studio division',gradeName:'Advanced',students:['hidden-roster']},
            teacherNames:['Instructor A',null,'Instructor B'],remark:'Equipment check',unusedPrivateField:'must-not-leave'}];
    }});
    const out=await h.run('week',range,await h.owner());
    assert.equal(out.value[0].start,'2025-02-18T00:30:00.000Z');assert.equal(out.value[0].kind,'lesson');
    assert.equal(out.value[0].room,'Studio');assert.ok(!JSON.stringify(out).includes('fixture-learner'));
    assert.deepEqual(JSON.parse(JSON.stringify(out.value[0].metadata)),
        {grade:'Advanced',className:'Studio division',teacher:'Instructor A / Instructor B',note:'Equipment check'});
    assert.ok(!JSON.stringify(out).includes('hidden-roster'));
    assert.ok(!JSON.stringify(out).includes('must-not-leave'));assert.deepEqual(h.calls,['owner','owner','week','owner']);
});
test('a valid empty week and an unrecognized response have different results',async()=>{
    for(const [payload,ok] of [[[],true],[{},false],[[{scheduleType:3,name:'Incomplete'}],false],[[{scheduleType:17}],false]]) {
        const h=harness({week:()=>payload});const r=await h.run('week',range,await h.owner());
        assert.equal(ok?r.value.length:r.error,ok?0:'format');
    }
});
test('an explicit unnamed school period is not an enrollment or a malformed week',async()=>{
    const times={scheduleType:3,beginTime:'2025-02-18T11:00:00',endTime:'2025-02-18T11:40:00'};
    const h=harness({week:()=>[{...times,name:' '},{...times,name:'Workshop',classId:17}]});
    const r=await h.run('week',range,await h.owner());
    assert.deepEqual(Array.from(r.value ?? [],x=>x.kind),['vacant','lesson']);
    assert.equal(r.value[0].course,'');
    for(const broken of [times,{...times,name:'',subjectId:12},{...times,name:'',isAllDay:true}]) {
        const invalid=harness({week:()=>[broken]});
        assert.equal((await invalid.run('week',range,await invalid.owner())).error,'format');
    }
});
test('two rows without a class identity do not share an enrollment key just because their titles match',async()=>{
    const row={scheduleType:4,name:'Lab',subjectId:11,beginTime:'2025-02-18T08:00:00',endTime:'2025-02-18T08:40:00'};
    const h=harness({week:()=>[row,{...row,beginTime:'2025-02-18T08:40:00',endTime:'2025-02-18T09:20:00'}]});
    const r=await h.run('week',range,await h.owner());
    assert.notEqual(r.value[0].course,r.value[1].course);
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

test('semester directory is a list, not a read of every semester; selected tasks and GPA use that exact ID',async()=>{
    const past={id:17,isNow:false,year:2023,semester:1,startDate:'2023-09-01',endDate:'2024-01-20'};
    const h=harness({terms:()=>[term,past],tasks:u=>{
        assert.equal(u.searchParams.get('SemesterId'),'17');assert.equal(u.searchParams.get('BeginTime'),past.startDate);
        return {list:[],totalCount:0};
    },grades:u=>{assert.equal(u.searchParams.get('semesterId'),'17');return {studentSemesterDynamicScoreBasicDtos:[]};}});
    const owner=await h.owner(), dir=await h.run('terms',{},owner);
    assert.equal(dir.value.current,'42');assert.equal(dir.value.terms.length,2);assert.ok(!h.calls.includes('grades'));
    assert.equal((await h.run('tasks',{term:'17'},owner)).value.rows.length,0);
    assert.equal((await h.run('grades',{term:'17'},owner)).value.termID,'17');
    assert.equal((await h.run('tasks',{term:'missing'},owner)).error,'term');
    assert.equal(h.calls.filter(k=>k==='tasks').length,1);
});

test('overview lists project visible metadata, use the verified student, and never return file links or assessment answers',async()=>{
    const h=harness({owner:()=>({userId:42,studentInfoId:28}),resources:(_,request)=>{
        const body=JSON.parse(request.body);assert.equal(String(body.stuInfoId),'28');assert.equal(body.page.pageIndex,1);
        return {totalCount:1,list:[{id:6,name:'Reading pack',format:'pdf',path:'excluded-link'}]};
    },evaluations:(_,request)=>{assert.equal(request.method,'POST');return [{id:2,name:'Studio skills',hasSubmitted:false,answers:'excluded'}];},
    exams:u=>{assert.equal(u.searchParams.get('SemesterId'),String(term.id));return {totalCount:0,list:[]};}});
    const owner=await h.owner();
    for(const op of ['resources','exams','evaluations']) {
        const result=await h.run(op,{studentId:999},owner);assert.ok(Array.isArray(result.value),op);
        assert.doesNotMatch(JSON.stringify(result),/excluded|answers|path/);
    }
    assert.ok(!h.calls.includes('gpa'));assert.ok(!h.calls.includes('grades'));
    const unavailable=harness({owner:()=>({userId:10})});
    assert.equal((await unavailable.run('resources',{},await unavailable.owner())).error,'unavailable');
    assert.ok(!unavailable.calls.includes('resources'));
});

test('only unnamed semesters carry display components; official labels never become interface keys',async()=>{
    const h=harness({terms:()=>[{...term,name:'檐下的声音 / Échos'},
        {id:54,isNow:false,year:2027,semester:3}]});
    const owner=await h.owner(), value=(await h.run('terms',{},owner)).value;
    assert.equal(value.terms[0].name,'檐下的声音 / Échos');
    assert.equal(value.terms[0].semester,undefined);
    assert.equal(value.terms[1].year,2027); assert.equal(value.terms[1].semester,3);
    const labels=h.p.task({id:7,name:'取消',learningTaskState:2,subjectName:'Settings',
                           learningTaskTypeName:'reading'});
    assert.equal(labels.title,'取消'); assert.equal(labels.courseName,'Settings'); assert.equal(labels.kind,'reading');
});

test('only explicit complete pages can replace a saved list, including a genuine zero', async()=>{
    for(const result of [{list:[]},{list:[],totalCount:"pending"},{list:[],totalCount:1},{list:[],totalCount:0,recordCount:2},
        {list:[{id:1,name:"Batik"}],totalCount:0}]) {
        const h=harness({tasks:()=>result}); assert.equal((await h.run('tasks',{},await h.owner())).error,'format');
    }
    const empty=harness({tasks:()=>({list:[],totalCount:0})});
    assert.equal((await empty.run('tasks',{},await empty.owner())).value.rows.length,0);
    const varying=harness({tasks:u=>({totalCount:u.searchParams.get('PageIndex')==='1'?3:2,
        list:[{id:u.searchParams.get('PageIndex'),name:"Mask design",learningTaskState:2}]})});
    assert.equal((await varying.run('tasks',{},await varying.owner())).error,'format');
});

test('deadline alerts require a precise time and positive outstanding state, never a guess',()=>{
    const {p}=harness(), item={id:15,name:'Binding sketch',learningTaskState:2,endTime:'2030-03-10 18:00:00'};
    assert.equal(p.task(item).deadlineEligible,true);
    for(const fields of [{endTime:'2030-03-10'},{endTime:null},{isExempt:true},{isExempt:1},{isExempt:'unknown'},
        {learningTaskState:4},{learningTaskState:3},{learningTaskState:11},{stuCommitTime:'2030-03-07 18:00:00'}]) {
        assert.equal(p.task({...item,...fields}).deadlineEligible,false,JSON.stringify(fields));
    }
});

test('task details require membership in the verified term, never a caller-supplied standalone identifier',async()=>{
    const rows=[{id:71,name:'Bound journal',learningTaskState:3},{id:72,name:'External studio',sourceType:2},
        {id:73,name:'Closed sheet',isFirstSubmissionClosed:true},{id:74,name:'Draft',learningTaskState:1}];
    const h=harness({tasks:()=>({list:rows,totalCount:4}),material:(u,o)=>{
        assert.equal(o.method,'GET');assert.deepEqual(Object.fromEntries(u.searchParams),{learningTaskId:'71'});
        return {content:'Weave the sample',remark:'linen',mode:0,learningTaskState:3,isSynchroToMobiled:0,comment:'not released',
            teacherCommentDocuments:[{id:6,name:'private draft'}],score:96,studentName:'not needed'};
    }}), owner=await h.owner(), args={term:'42',task:'71'};
    assert.equal((await h.run('taskMaterial',args,owner)).error,'unavailable');
    await h.run('tasks',{},owner);
    for (const other of [{...args,term:'43'},...['72','73','74','99'].map(task=>({...args,task}))]) {
        assert.equal((await h.run('taskMaterial',other,owner)).error,'unavailable');
    }
    assert.equal(h.calls.includes('material'),false);
    const v=(await h.run('taskMaterial',args,owner)).value;
    assert.equal(v.instructions.text,'Weave the sample');assert.equal(v.answer.text,'linen');assert.equal(v.feedback.state,'hidden');
    for (const blocked of ['private draft','not released','not needed','score','96']) assert.ok(!JSON.stringify(v).includes(blocked));
    assert.ok(!h.calls.some(x=>['gpa','grades','detail'].includes(x)));
});
test('material separates checked emptiness, missing fields, own submitted files and only released feedback',async()=>{
    const base={origin:here,task:'37',release:true};
    const h=harness(), project=(data,select)=>h.p.taskMaterial(data,base,select);
    assert.throws(()=>project({name:'summary'}),/format/);
    const detail={mode:0,learningTaskState:4,isSynchroToMobiled:true,content:'',remark:'Checked texture',
        stuCommitTime:'2025-04-08 18:15:00',comment:'Dry before binding',
        teacherCommentDocuments:[{id:4,name:'notes.txt',url:'https://school-fixture.schoolis.cn/files/notes?signature=ephemeral'}],
        learningTaskStudentDocuments:[{id:23,name:'answer.txt'}]};
    const v=project(detail);assert.equal(v.instructions.state,'available');assert.equal(v.instructions.text,null);
    assert.equal(v.feedback.text,'Dry before binding');assert.equal(v.submitted,'2025-04-08T10:15:00.000Z');
    assert.ok(!JSON.stringify(v).includes('ephemeral'));assert.ok(!JSON.stringify(v).includes('https:'));
    assert.equal(project(detail,{section:'feedback',key:'id:4',name:'notes.txt'}).url,'https://school-fixture.schoolis.cn/files/notes?signature=ephemeral');
    assert.ok(project(detail,{section:'answer',key:'id:23',name:'answer.txt'}).url.endsWith('documentType=2'));
    assert.throws(()=>project(detail,{section:'answer',key:'id:4',name:'notes.txt'}),/unavailable/);
    assert.equal(project({mode:0,learningTaskState:2,content:'Binder',remark:'draft',comment:'hidden'}).answer.state,'hidden');
    assert.equal(project({mode:0,learningTaskState:4,isSynchroToMobiled:1,content:'Binder'}).feedback.state,'unknown');
    assert.equal(h.p.taskMaterial(detail,{...base,release:false}).feedback.state,'hidden');
    assert.throws(()=>project({...detail,learningTaskDocuments:'invalid'}),/format/);
    assert.throws(()=>project({...detail,learningTaskState:1}),/denied/);
});
test('a refusal or changed identity during an item read cannot return partial or cross-account material',async()=>{
    let member=7;
    const h=harness({owner:()=>({userId:member}),tasks:()=>({list:[{id:2,name:'Texture'}],totalCount:1}),
        material:()=>{ member=8;return {mode:1,content:'withheld on account switch'}; }});
    const owner=await h.owner();await h.run('tasks',{},owner);
    const out=await h.run('taskMaterial',{term:'42',task:'2'},owner);
    assert.equal(out.error,'changed');assert.equal(out.value,undefined);
    for(const extra of [{learningTaskId:3},{semesterId:5},{studentInfoId:87}]) {
        const bad=harness({owner:()=>({userId:8,studentInfoId:72}),tasks:()=>({list:[{id:2,name:'Texture'}],totalCount:1}),
            material:()=>({mode:0,content:'not this task',...extra})});
        const valid=await bad.owner();await bad.run('tasks',{},valid);
        assert.equal((await bad.run('taskMaterial',{term:'42',task:'2'},valid)).error,'denied');
    }
    const g=harness({tasks:()=>({list:[{id:2,name:'Texture'}],totalCount:1}),material:()=>Response.json({}, {status:403})});
    const other=await g.owner();await g.run('tasks',{},other);assert.equal((await g.run('taskMaterial',{term:'42',task:'2'},other)).error,'denied');
});
