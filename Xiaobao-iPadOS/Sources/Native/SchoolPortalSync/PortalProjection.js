// A function expression loaded into a private WebKit world. Only return the fields
// the student screens present; never return a portal response, login form or profile.
() => {
    const bad = () => { throw Error("format"); };
    const array = x => Array.isArray(x) ? x : bad();
    const str = x => typeof x === "string" && x.trim() ? x.trim() : null;
    const id = x => (typeof x === "number" && Number.isSafeInteger(x) || str(x)) ? String(x) : null;
    const num = x => (typeof x === "number" || (typeof x === "string" && /^-?\d+(\.\d+)?$/.test(x))) &&
        Number.isFinite(Number(x)) ? Number(x) : null;
    const key = (...parts) => JSON.stringify(parts);
    const code = (value, required = true) => id(value) ?? (required ? bad() : null);
    const title = (...values) => values.map(str).find(Boolean) ?? bad();

    // Schoolis supplies either offset timestamps or Shanghai wall time. Do not
    // interpret a timezone-less lesson using the iPad's travel timezone.
    function instant(x) {
        const s = str(x);
        if (!s) return null;
        const m = s.match(/^(\d{4}-\d\d-\d\d)(?:[T ](\d\d:\d\d)(?::(\d\d)(\.\d+)?)?(Z|[+-]\d\d:\d\d)?)?$/i);
        if (!m) return bad();
        const midnight=Date.parse(m[1]+"T00:00:00Z");
        if (!Number.isFinite(midnight) || new Date(midnight).toISOString().slice(0,10)!==m[1] ||
            (m[2] && (Number(m[2].slice(0,2))>23 || Number(m[2].slice(3))>59)) ||
            (m[3] && Number(m[3])>59)) return bad();
        const milliseconds = Date.parse(m[1]+"T"+(m[2] || "00:00")+":"+(m[3] || "00")+
            (m[4] ? m[4].slice(0,4) : "")+(m[5] || "+08:00"));
        return Number.isFinite(milliseconds) ? new Date(milliseconds).toISOString() : bad();
    }
    function mark(value, maximum, letter) {
        if (num(value) !== null) return {type:"numeric", earned:num(value), possible:num(maximum)>0 ? num(maximum) : null};
        if (str(letter) && !["-", "--"].includes(str(letter))) return {type:"letter", value:str(letter)};
        return null;
    }
    function termDirectory(rows) {
        const list=array(rows), active=list.filter(x=>x.isNow===true);
        if(active.length!==1 || list.length>128) throw Error("term");
        const terms=list.map(t=>{
            const year=num(t.year), sem=num(t.semester), supplied=str(t.name);
            // A portal-provided label stays verbatim. Only synthesized names have formatting metadata.
            const generated=!supplied && Number.isSafeInteger(year) && year>=1 && year<10000 &&
                Number.isSafeInteger(sem) && sem>0 && sem<=32;
            return {id:code(t.id), name:supplied ?? (generated ? year+"–"+(year+1)+" / "+sem : title(t.name)),
                ...(generated ? {year,semester:sem} : {}),
                start:str(t.startDate)?.slice(0,10), end:str(t.endDate)?.slice(0,10)};
        });
        if(new Set(terms.map(t=>t.id)).size!==terms.length) throw Error("term");
        return {current:code(active[0].id),terms};
    }
    function term(rows, selected) {
        const directory=termDirectory(rows);
        const result=directory.terms.find(t=>t.id===(selected??directory.current));
        if(!result) throw Error("term");
        return result;
    }
    function schedule(rows) {
        return array(rows).map(x => {
            if (![1,2,3,4].includes(x.scheduleType)) return bad();
            const name=title(x.name,x.eName), start=instant(x.beginTime), end=instant(x.endTime);
            const lesson=x.scheduleType===3 || x.scheduleType===4;
            if (!start || (lesson && (!end || end<=start)) || (end && end<start)) return bad();
            const course=key(code(x.classId ?? x.classInfo?.id,false), code(x.subjectId,false), name);
            return {id:key(x.scheduleType, code(x.id ?? x.ID,false), course, start, end),
                kind:lesson?"lesson":x.scheduleType===1?"activity":"calendar", name, start, end,
                course, room:str(x.playgroundName) ?? str(x.playgroundEName), allDay:x.isAllDay===true};
        });
    }
    function courses(data) {
        return array(data?.studentSemesterDynamicScoreBasicDtos).map(x => {
            const subject=code(x.subjectId), cls=code(x.classId,false), type=x.scoreType;
            if (type!==1 && type!==2) return bad();
            return {id:key(cls,subject), subject, cls, type, name:title(x.subjectName,x.subjectEName),
                className:str(x.className) ?? str(x.classEName),
                score:type===1 ? mark(x.subjectScore,x.subjectTotalScore,null) : mark(null,null,x.levelString)};
        });
    }
    function groups(data, type) {
        const out=[];
        function add(g, path, nesting, pos) {
            if (nesting>6 || out.length>=500) return bad();
            const name=title(g.evaluationProjectName,g.evaluationProjectEName), lineage=[...path,name];
            const proportion=num(g.proportion);
            const groupScore=g.scoreIsNull===false
                ? (type===1 ? mark(g.score,null,null) : mark(null,null,g.levelString)) : null;
            const items=array(g.learningTaskAndExamList ?? []).map((x,i) => {
                // These are distinct release flags. Never read a numeric value for
                // an unreleased item, even when one was included by the server.
                const published=x.type===1 ? x.isPublish===true : x.type===2 && x.isSynchroToMobiled===true;
                const absent=x.type===1 && x.disciplineState===3;
                const useLevel=x.type===1 ? [2,4].includes(x.resultType) : x.scoreType===2;
                const result=published && !absent && x.scoreIsNull!==true ?
                    (useLevel ? mark(null,null,x.levelString) : mark(x.score,x.totalScore,null)) : null;
                return {id:key(pos,i,code(x.id,false)),title:title(x.name),date:instant(x.date),
                    status:result?"graded":!published?"未发布":absent?"缺考":"未提供成绩",score:result};
            });
            out.push({id:pos,title:lineage.join(" / "),nested:nesting>0,
                weight:proportion!==null && proportion>=0 && proportion<=100 ? proportion/100 : null,
                mark:groupScore,items});
            array(g.evaluationProjectList ?? []).forEach((child,i)=>add(child,lineage,nesting+1,pos+"."+i));
        }
        array(data?.evaluationProjectList).forEach((g,i)=>add(g,[],0,String(i)));
        return out;
    }
    function task(x, includeScores = false) {
        if (x.learningTaskState===1) return null; // not published
        const subject=code(x.subjectId,false), courseName=str(x.subjectName) ?? str(x.subjectEName);
        const course=courseName ? key("subject",subject,courseName) : null;
        const state=x.learningTaskState, sync=x.isSynchroToMobiled, exempt=x.isExempt===true || x.isExempt===1;
        // Match the student TASK LIST, not a course-detail schema: only standard
        // cards have a score section, and its release check is exactly numeric 1.
        // Gate *before* accessing a mark: a corrected row can contain a withheld value.
        let score=null;
        if (includeScores===true && (x.mode===0 || x.mode==="0") && sync===1 &&
            (x.isExempt==null || x.isExempt===false || x.isExempt===0)) {
            const type=num(x.scoreType);
            if (type===1) score=mark(x.score,x.totalScore,null);
            else if (type===2) score=mark(null,null,x.levelString);
        }
        // A marked offline task does not prove an online student submission.
        return {id:code(x.id ?? x.learningTaskId), title:title(x.name,x.learningTaskName),
            due:instant(x.endTime), published:instant(x.publishTime), course, courseName,
            deadlineEligible:state===2 && !x.stuCommitTime && (x.isExempt==null || x.isExempt===false || x.isExempt===0) &&
                /^\d{4}-\d\d-\d\d[T ]\d\d:\d\d/.test(str(x.endTime)??""),
            kind:str(x.learningTaskTypeName) ?? str(x.typeName),
            status:state===3 || instant(x.stuCommitTime) ? "submitted" : state===2 && !x.isExempt?"pending":"unavailable",
            grading:exempt?"excused":score?"graded":state===4 ? (sync===0 || sync===false?"graded_unpublished":"graded") :
                state===5?"in_progress":null,score};
    }
    const states = ["present","late","early","absent"];
    const count = x => Number.isSafeInteger(x) && x>=0 && x<=10000000 ? x : bad();
    function attendanceSummary(data) {
        const counts={present:0,late:0,early:0,absent:0}, seen=new Set();
        // The student UI's published field is "sataeCountList"; missing is not the same as empty.
        for(const item of array(data?.sataeCountList)) {
            const state=states[count(item.attendanceState)];
            if(!state || seen.has(state)) return bad();
            counts[state]=count(item.count); seen.add(state);
        }
        if(Object.values(counts).reduce((a,b)=>a+b,0)!==count(data.totalCount)) return bad();
        const percent=num(data.attendanceRate);
        if(data.attendanceRate!=null && (percent===null || percent<0 || percent>100)) return bad();
        return {counts,rate:percent===null || data.totalCount===0 ? null : percent/100};
    }
    function attendanceCourses(data) {
        const seen=new Set();
        return array(data).map(x=>{
            const subject=code(x.subjectId);
            if(seen.has(subject)) return bad(); seen.add(subject);
            return {id:subject,name:title(x.subjectName,x.subjectEName),counts:{present:count(x.normalCount),
                late:count(x.lateCount),early:count(x.earlyLeaveCount),absent:count(x.absentCount)}};
        });
    }
    function attendanceRecords(data,category,page,subject) {
        const list=array(data?.list),recordTotal=count(data.totalCount);
        if(list.length!==Math.min(10,Math.max(0,recordTotal-(page-1)*10))) return bad();
        const records=list.map((x,i)=>{
            const status=states[count(x.attendanceState)];
            const start=instant(category==="daily"?x.attendanceTime:x.beginTime);
            const end=category==="daily"?null:instant(x.endTime);
            if(!status || !start || (end && end<start) || (subject && x.subjectId!=null && id(x.subjectId)!==subject)) return bad();
            const name=category==="daily"?title(x.className,x.classEName):category==="activity"?
                title(x.activityTitle,x.activityETitle):title(x.subjectName,x.subjectEName);
            return {id:(page-1)*10+i,name,start,end,status,allDay:x.isAllDay===true,
                excused:category!=="activity" && status==="absent" && typeof x.isExcused==="boolean"?x.isExcused:null};
        });
        return {records,recordTotal};
    }
    return {array, str, id, num, term, termDirectory, schedule, courses, groups, task, attendanceSummary, attendanceCourses, attendanceRecords};
}
