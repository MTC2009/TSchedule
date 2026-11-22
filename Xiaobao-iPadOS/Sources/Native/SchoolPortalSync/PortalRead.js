// Invoked only in the official /Home main frame, in WKContentWorld.defaultClient.
// The caller supplies an operation, not a URL, header, script or student identifier.
async (op, args, expected, salt, p, generation) => {
    const origin="https://tsinglanstudent.schoolis.cn";
    const home=()=>location.origin===origin && /^\/Home(?:\/Index)?\/?$/i.test(location.pathname) && window===window.top;
    const fail=reason=>{throw Error(reason);};
    function ready() {
        if (!home()) fail("unavailable");
        if (document.readyState==="loading") fail("notReady");
    }
    const identityPath="/api/MemberShip/GetCurrentStudentInfo";
    let timer;
    const abort=new AbortController();
    let active;
    try {
        ready();
        // Private-world cancellation registry holds controllers, never reply data.
        // Native passes the old generation when navigating away or entering background.
        const readers=globalThis.tScheduleReads ??= new Map();
        if (!readers.has(generation)) readers.set(generation,new Set());
        active=readers.get(generation); active.add(abort);
        timer=setTimeout(()=>abort.abort(),op==="identity"?7000:op==="week"?15000:45000);
        async function read(path, qs, data, method=data?"POST":"GET") {
            ready();
            const url=new URL(path,origin);
            if (qs) for (const [k,v] of Object.entries(qs)) url.searchParams.set(k,String(v));
            const res=await fetch(url.href,{method, credentials:"same-origin", mode:"same-origin",
                redirect:"manual",cache:"no-store",signal:abort.signal,
                headers:method==="POST"?{"Content-Type":"application/json",Accept:"application/json"}:{Accept:"application/json"},
                ...(data?{body:JSON.stringify(data)}:{})});
            // An unreadable redirect or maintenance HTML does not identify its destination.
            if (res.type==="opaqueredirect") fail("unavailable");
            if (res.status===401) fail("expired");
            if (res.status===403) fail("denied");
            if (!res.ok) fail("network");
            const ct=res.headers.get("content-type") || "";
            if (ct.includes("text/html")) fail("format");
            let envelope;
            try { envelope=JSON.parse(await res.text()); }
            catch (error) { if (error instanceof SyntaxError) fail("format"); throw error; }
            if (!envelope || typeof envelope!=="object" || !Object.hasOwn(envelope,"state")) fail("format");
            if (envelope.state===999901) fail("expired");
            if (envelope.state===999902) fail("denied");
            if (envelope.state!==0) fail("unavailable");
            if (!Object.hasOwn(envelope,"data")) fail("format");
            return envelope.data;
        }
        async function account() {
            const user=await read(identityPath);
            const stableID=value=>{
                const id=p.id(value);
                return id && !/^(?:0+|-\d+|0{8}-0{4}-0{4}-0{4}-0{12})$/.test(id) ? id : null;
            };
            const student=stableID(user?.studentId), member=stableID(user?.userId), handle=p.str(user?.loginName);
            if (!student && !member && !handle) fail("format");
            // Normal reads expose only the fingerprint. Explicit enrollment alone
            // needs the verified account's own login name, never the wider profile.
            const bytes=new TextEncoder().encode(JSON.stringify([salt,origin,p.id(user.orgId),student,member,handle]));
            const hash=await crypto.subtle.digest("SHA-256",bytes);
            return {owner:Array.from(new Uint8Array(hash),x=>x.toString(16).padStart(2,"0")).join(""),handle, studentInfo:stableID(user?.studentInfoId)?user.studentInfoId:null};
        }
        const first=await account(), owner=first.owner;
        if (op==="identity") return {owner};
        if (owner!==expected) fail("changed");
        let value;
        if (op==="enrollmentName") {
            if (!first.handle || first.handle.length>512) fail("unavailable");
            value=first.handle;
        } else if (op==="evaluations") {
            const list=p.array(await read("/v2/basic/CareerAssessment/MyAssessments",null,null,"POST"));
            if(list.length>3200) fail("format");
            value=list.map(x=>({id:p.id(x.id),title:p.str(x.name),detail:
                x.hasSubmitted===true?"已完成":x.hasSubmitted===false?"未完成":null}));
        } else if (op==="resources" || op==="exams") {
            // List metadata only. The resource scope comes from this document's verified student,
            // never from a client-supplied account, a guessed ID, or a different profile.
            const resource=op==="resources";
            if(resource && !first.studentInfo) fail("unavailable");
            const term=resource?null:p.term(await read("/api/School/GetSchoolSemesters"));
            if(term && (!term.start || !term.end)) fail("term");
            const rows=[], seen=new Set(); let total;
            for(let page=1;page<=64;++page) {
                const data=resource
                    ? await read("/v2/clouddisk/StudentShare/SharedToMePagedList",null,{
                        stuInfoId:first.studentInfo,formats:[],sortModel:{key:0,orderBy:0},page:{pageIndex:page,pageSize:50}})
                    : await read("/api/Exam/GetList",{SemesterId:term.id,SubjectId:"null",TypeId:"null",Key:"",
                        BeginTime:term.start,EndTime:term.end,PageSize:50,PageIndex:page,Mode:"null"});
                const list=p.array(data?.list),count=p.num(data.totalCount??data.total??data.recordCount);
                if(!Number.isSafeInteger(count)||count<0||count>3200||(total!=null&&total!==count)) fail("format");
                total=count;
                for(const x of list){
                    const id=p.id(x.id??x.examId),title=p.str(x.name)??p.str(x.eName)??p.str(x.title);
                    if(!id||!title||seen.has(id)) fail("format");seen.add(id);
                    rows.push({id,title,detail:resource?p.str(x.format):p.str(x.beginTime)?.slice(0,10)});
                }
                if(seen.size===total) break;
                if(!list.length||seen.size>total||page===64) fail("format");
            }
            value=rows;
        } else if (op==="terms") {
            const {current,terms}=p.termDirectory(await read("/api/School/GetSchoolSemesters"));
            value={current,terms:terms.map(({id,name,year,semester})=>({id,name,year,semester}))};
        } else if (op==="week") {
            if (![args.from,args.to].every(x=>/^\d{4}-\d\d-\d\d$/.test(x)) ||
                Date.parse(args.to)-Date.parse(args.from)!==6*86400000) fail("format");
            value=p.schedule(await read("/api/Schedule/ListScheduleByParent",null,{beginTime:args.from,endTime:args.to}));
        } else {
            const selectable=["tasks","grades","detail"].includes(op);
            const term=p.term(await read("/api/School/GetSchoolSemesters"),selectable?args.term:null);
            const semesterId=term.id;
            if (op==="grades") {
                const courses=p.courses(await read("/api/DynamicScore/GetStuSemesterDynamicScore",{semesterId}));
                // The school overview has no GPA card without any published course rows.
                let gpa=null, gpaUnavailable=false;
                if (courses.length) {
                    try { gpa=await read("/api/DynamicScore/GetGpa",{semesterId}); }
                    catch (error) {
                        if (error?.message==="expired" || error?.message==="changed") throw error;
                        gpaUnavailable=true;
                    }
                }
                value={term:term.name,termLabel:{id:term.id,name:term.name,year:term.year,semester:term.semester},termID:semesterId,gpa:p.num(gpa),gpaUnavailable,courses};
            } else if (op==="attendance" || op==="attendanceSubject") {
                const types={classroom:7,daily:1,activity:2}, page=args.page;
                if(!Object.hasOwn(types,args.category) || !Number.isSafeInteger(page) || page<1 || page>1000000) fail("format");
                const date=v=>typeof v==="string" && /^\d{4}-\d\d-\d\d$/.test(v) &&
                    Number.isFinite(Date.parse(v)) && new Date(v).toISOString().slice(0,10)===v;
                if(!date(term.start) || !date(term.end) || term.end<term.start) fail("term");
                if((args.from==null)!==(args.to==null)) fail("format");
                const from=args.from??term.start,to=args.to??term.end;
                if(!date(from) || !date(to) || to<from) fail("format");
                // The student screen scopes all reads by the current session, never by a supplied student ID.
                const dates={BeginTime:from+" 00:00:00",EndTime:to+" 23:59:59"};
                const paging={"Page.PageIndex":page,"Page.PageSize":10};
                const classView=args.category==="classroom";
                const selected=["present","late","early","absent"].indexOf(args.status);
                // Classroom status is a local filter over the school's per-subject totals.
                if(args.status!=null && (classView || selected<0)) fail("format");
                if(op==="attendanceSubject") {
                    if(!classView || !p.id(args.subject)) fail("format");
                    const result=await read("/api/Attendance/GetSubjectAttendanceDetail",{...dates,SubjectId:args.subject,...paging});
                    value=p.attendanceRecords(result,"classroom",page,args.subject);
                } else {
                    if(classView && page!==1) fail("format");
                    const filter={...dates,AttendanceType:types[args.category]};
                    const summary=p.attendanceSummary(await read("/api/Attendance/GetAttendanceStatistic",filter));
                    const courses=classView?p.attendanceCourses(await read("/api/Attendance/GetSubjectAttendanceStatistic",dates)):[];
                    const records=classView?{records:[],recordTotal:0}:p.attendanceRecords(
                        await read("/api/Attendance/GetAttendanceStatisticDetail",{...filter,...paging,
                            ...(selected>=0?{AttendanceState:selected}:{})}),args.category,page,null);
                    value={from,to,termStart:term.start,termEnd:term.end,...summary,courses,...records};
                }
            } else if (op==="detail") {
                if (args.term!==semesterId || !args.subject || !args.cls) fail("unavailable");
                // Only the selected class/subject pair from the current account's grade list is supplied by Swift.
                value=p.groups(await read("/api/DynamicScore/GetDynamicScoreDetail",
                    {semesterId,classId:args.cls,subjectId:args.subject}),Number(args.type));
            } else if (op==="tasks") {
                if (![term.start,term.end].every(x=>/^\d{4}-\d\d-\d\d$/.test(x))) fail("term");
                const rows=[],seen=new Set(); let complete=false, expectedTotal;
                for (let page=1;page<=64;++page) {
                    const data=await read("/api/LearningTask/GetList",{SemesterId:semesterId,SubjectId:"null",TypeId:"null",
                        Key:"",BeginTime:term.start,EndTime:term.end,PageSize:50,PageIndex:page,Mode:"null"});
                    const list=p.array(data?.list);
                    const counts=["totalCount","total","recordCount"].filter(k=>Object.hasOwn(data,k)).map(k=>p.num(data[k]));
                    const total=counts[0];
                    // An empty page without a credible total is not proof of zero tasks.
                    if (!Number.isSafeInteger(total) || total<0 || total>3200 || counts.some(n=>n!==total) ||
                        (expectedTotal!==undefined && total!==expectedTotal)) fail("format");
                    expectedTotal=total;
                    for (const item of list) {
                        const id=p.id(item.id ?? item.learningTaskId);
                        if (!id || seen.has(id)) fail("format");
                        seen.add(id); const row=p.task(item,args.includeScores===true); if (row) rows.push(row);
                    }
                    if (seen.size>expectedTotal) fail("format");
                    if (seen.size===expectedTotal) {complete=true;break;}
                    if (!list.length) fail("format");
                }
                if (!complete) fail("format");
                value={term:term.name,termLabel:{id:term.id,name:term.name,year:term.year,semester:term.semester},rows};
            } else fail("format");
        }
        ready();
        const last=await account();
        if (owner!==last.owner || (op==="resources" && first.studentInfo!==last.studentInfo)) fail("changed");
        return {owner,value};
    } catch(e) {
        const code=["notReady","expired","changed","denied","term","format","unavailable"].includes(e?.message)?e.message:"network";
        return {error:code};
    } finally {
        clearTimeout(timer); active?.delete(abort);
        if (active?.size===0) globalThis.tScheduleReads.delete(generation);
    }
}
