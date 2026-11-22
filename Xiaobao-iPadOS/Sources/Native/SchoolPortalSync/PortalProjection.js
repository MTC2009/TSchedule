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
            const name=str(x.name) ?? str(x.eName), start=instant(x.beginTime), end=instant(x.endTime);
            const lesson=x.scheduleType===3 || x.scheduleType===4;
            if (!start || (lesson && (!end || end<=start)) || (end && end<start)) return bad();
            const cls=code(x.classId ?? x.classInfo?.id,false), subject=code(x.subjectId,false);
            if (!name) {
                // A blank named field in a timed, unassigned teaching row is different
                // from a failed response, a nameless assigned subject, or an all-day notice.
                if (!lesson || subject || x.isAllDay===true || !("name" in x || "eName" in x) ||
                    [x.name,x.eName].some(v=>v!=null && typeof v!=="string")) return bad();
                return {id:key("vacant",start,end),kind:"vacant",name:"",start,end,course:"",room:null,allDay:false};
            }
            // No shared class identifier: preserve both records rather than merge by title.
            const course=cls ? key(cls,subject,name) : key(null,subject,name,start,end);
            // Only the labeled display fields of this already-authorized occurrence.
            // Do not retain class lists, teacher IDs, student records or HTML.
            const teachers=Array.isArray(x.teacherNames) ? x.teacherNames.map(str).filter(Boolean).join(" / ") : str(x.teacherNames);
            const metadata=lesson ? {
                grade:str(x.gradeName) ?? str(x.classInfo?.gradeName),
                className:str(x.className) ?? str(x.classInfo?.name),
                teacher:str(x.teacherName) ?? str(teachers) ?? str(x.classInfo?.teacherName),
                note:str(x.remark) ?? str(x.remarks)
            } : null;
            if (metadata) for (const field of Object.keys(metadata)) {
                if (!metadata[field] || metadata[field].length > 1024) delete metadata[field];
            }
            return {id:key(x.scheduleType, code(x.id ?? x.ID,false), course, start, end),
                kind:lesson?"lesson":x.scheduleType===1?"activity":"calendar", name, start, end,
                ...(metadata && Object.keys(metadata).length ? {metadata} : {}),
                course, room:str(x.playgroundName) ?? str(x.playgroundEName), allDay:x.isAllDay===true};
        });
    }
    function courses(data) {
        return array(data?.studentSemesterDynamicScoreBasicDtos).map(x => {
            const subject=code(x.subjectId), cls=code(x.classId,false), type=x.scoreType;
            if (type!==1 && type!==2) return bad();
            const evaluationName=str(x.subjectEName);
            return {id:key(cls,subject), subject, cls, type, name:title(x.subjectName,x.subjectEName),
                className:str(x.className) ?? str(x.classEName),
                ...(evaluationName ? {evaluationName} : {}),
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
                    status:result?"graded":!published?"unpublished":absent?"absent":"no_mark",score:result};
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
        if (num(x.learningTaskState)===1) return null; // not published
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
            detailReadable:!!id(x.id) && !/^(?:0+|-\d+)$/.test(id(x.id)) && num(x.sourceType)!==2 && !x.isFirstSubmissionClosed,
            feedbackReleased:sync==null ? null : sync===1 || sync===true,
            deadlineEligible:state===2 && !x.stuCommitTime && (x.isExempt==null || x.isExempt===false || x.isExempt===0) &&
                /^\d{4}-\d\d-\d\d[T ]\d\d:\d\d/.test(str(x.endTime)??""),
            kind:str(x.learningTaskTypeName) ?? str(x.typeName),
            status:state===3 || instant(x.stuCommitTime) ? "submitted" : state===2 && !x.isExempt?"pending":"unavailable",
            grading:exempt?"excused":score?"graded":state===4 ? (sync===0 || sync===false?"graded_unpublished":"graded") :
                state===5?"in_progress":null,score};
    }
    // Match the student detail page, not the similarly named gradebook. Only a
    // second, explicit file selection may lift a single current link out of WebKit.
    function taskMaterial(x, scope, pick) {
        if (!x || typeof x!=="object" || !["content","learningTaskDocuments","remark","learningTaskStudentDocuments","comment","teacherCommentDocuments"].some(k=>Object.hasOwn(x,k))) bad();
        const flag=v=>v===1 || v===true, status=num(x.learningTaskState), mode=num(x.mode);
        if (status===1 || x.isFirstSubmissionClosed || num(x.sourceType)===2) throw Error("denied");
        const release=scope.release===false ? false : x.isSynchroToMobiled==null ? null : flag(x.isSynchroToMobiled);
        const committed=mode==null || (mode===0 && status==null && !str(x.stuCommitTime)) ? null :
            mode===0 && (status===3 || status===4 || status===5 || !!str(x.stuCommitTime));
        let match=null;
        function part(section, textKey, fileKey, visible) {
            if (visible!==true) return {state:visible==null?"unknown":"hidden",text:null,files:[]};
            if (!Object.hasOwn(x,textKey) && !Object.hasOwn(x,fileKey)) return {state:"unknown",text:null,files:[]};
            if (x[textKey]!=null && typeof x[textKey]!=="string") bad();
            const text=str(x[textKey]), docs=array(x[fileKey]??[]);
            if ((text?.length??0)>128000 || docs.length>128) bad();
            const files=docs.map(doc=>{
                const name=str(doc?.name); if (!name || name.length>255) bad();
                const fileID=id(doc.id), hasID=fileID && fileID!=="0" && /^[A-Za-z0-9_-]{1,128}$/.test(fileID), fileKey=hasID?"id:"+fileID:"name:"+name;
                let url=null;
                if (str(doc.url)) {
                    try { const u=new URL(doc.url,scope.origin); if(u.protocol==="https:" && !u.username && !u.password && (!u.port || u.port==="443")) url=u.href; } catch {}
                } else if (hasID && section==="answer") {
                    const u=new URL("/api/LearningTask/DownloadDocument",scope.origin);
                    u.searchParams.set("documentId",fileID);u.searchParams.set("learningTaskId",scope.task);u.searchParams.set("documentType","2");url=u.href;
                }
                if (pick && pick.section===section && pick.key===fileKey && pick.name===name && url) match={url,name};
                return {key:fileKey,name,downloadable:url!==null};
            });
            if (new Set(files.map(f=>f.key)).size!==files.length) bad(); // ambiguous identity cannot be downloaded
            return {state:"available",text,files};
        }
        const body=part("instructions","content","learningTaskDocuments",true);
        const answer=part("answer","remark","learningTaskStudentDocuments",committed);
        const feedback=part("feedback","comment","teacherCommentDocuments",mode===1 || release===false ? false : mode===0 ? release : null);
        if (pick && !match) throw Error("unavailable");
        return pick ? match : {instructions:body,answer,feedback,submitted:committed?instant(x.stuCommitTime):null};
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
    return {array, str, id, num, term, termDirectory, schedule, courses, groups, task, taskMaterial, attendanceSummary, attendanceCourses, attendanceRecords};
}
