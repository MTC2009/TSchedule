import Foundation
import XCTest
@testable import XiaobaoCore

@MainActor final class SchoolTaskMaterialTests: XCTestCase {
    private func list(id: String = "31", term: String = "autumn", released: Bool = true, read: Bool = true) -> SchoolPortalTasks {
        .init(termLabel:.init(id:term,name:term),term:term,rows:[.init(id:id,title:"Collate the prints",status:"submitted",
            due:nil,published:nil,course:nil,courseName:nil,kind:nil,grading:nil,score:nil,detailReadable:read,feedbackReleased:released)])
    }
    private var sample: SchoolTaskMaterial {
        .init(instructions:.init(state:.available,text:"Measure the panels",files:[]),
              answer:.init(state:.available,text:"Three panels",files:[.init(key:"id:9",name:"drawing.txt",downloadable:true)]),
              feedback:.init(state:.available,text:"Check the short edge",files:[]),submitted:nil)
    }

    func testProtectedCopyRestoresOnlyForItsLiveRegistrationTermAndRowRevision() async throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        let defaults=try XCTUnwrap(UserDefaults(suiteName:UUID().uuidString))
        defer { try? FileManager.default.removeItem(at:directory) }
        let store=SchoolAssignmentStore(directory:directory,defaults:defaults)
        XCTAssertTrue(store.accept(list(),owner:"student-a",current:true))
        let key=try XCTUnwrap(store.materialKey(term:"autumn",task:"31"))
        try store.saveMaterial(sample,for:key)
        let restored=SchoolAssignmentStore(directory:directory,defaults:defaults)
        XCTAssertEqual(restored.material(for:key)?.value,sample)
        XCTAssertTrue(restored.accept(list(term:"spring"),owner:"student-a",current:false))
        let historical=try XCTUnwrap(restored.materialKey(term:"spring",task:"31"))
        XCTAssertNotEqual(historical.revision,key.revision); XCTAssertNil(restored.material(for:historical))
        restored.reviewAccount(); XCTAssertNil(restored.material(for:key))
        restored.verified("student-a"); XCTAssertEqual(restored.material(for:key)?.value,sample)
        XCTAssertTrue(restored.accept(list(released:false),owner:"student-a",current:true))
        XCTAssertNil(restored.material(for:key)); XCTAssertThrowsError(try restored.saveMaterial(sample,for:key))
        let revised=try XCTUnwrap(restored.materialKey(term:"autumn",task:"31"))
        XCTAssertNotEqual(revised.revision,key.revision)
        XCTAssertThrowsError(try restored.saveMaterial(sample,for:revised), "A list withdrawal cannot be undone by stale feedback in a detail")
        XCTAssertTrue(restored.accept(list(read:false),owner:"student-a",current:true))
        XCTAssertNil(restored.materialKey(term:"autumn",task:"31"))
        restored.verified("student-b")
        XCTAssertTrue(restored.accept(list(),owner:"student-b",current:true))
        let other=try XCTUnwrap(restored.materialKey(term:"autumn",task:"31"))
        XCTAssertNotEqual(other.registration,key.registration); XCTAssertNil(restored.material(for:other))
        XCTAssertThrowsError(try restored.saveMaterial(sample,for:key))
        try restored.saveMaterial(sample,for:other)
        let empty=SchoolPortalTasks(termLabel:.init(id:"autumn",name:"Autumn"),term:"autumn",rows:[])
        XCTAssertTrue(restored.accept(empty,owner:"student-b",current:true))
        XCTAssertNil(restored.material(for:other))
        restored.forget()
        XCTAssertFalse((try FileManager.default.contentsOfDirectory(atPath:directory.path)).contains { $0.hasPrefix("material-") })
    }

    func testForeignIDOrLateResponseCannotCompleteAReadAfterSwitch() async throws {
        let owner=String(repeating:"b",count:64)
        var gate: CheckedContinuation<Data,Error>?, reads=0
        let store=SchoolPortalStore(selected:true) { op, _ in
            switch op {
            case .identity: return try JSONSerialization.data(withJSONObject:["owner":owner])
            case .tasks: return try JSONSerialization.data(withJSONObject:["owner":owner,"value":["term":"A","termLabel":["id":"A","name":"A"],
                "rows":[["id":"31","title":"Stitch lines","status":"pending","detailReadable":true]]]])
            case .taskMaterial:
                reads += 1; return try await withCheckedThrowingContinuation { gate=$0 }
            default: throw SchoolPortalIssue.unavailable
            }
        }
        await store.verify(); await store.loadTasks()
        do { _ = try await store.readTaskMaterial(term:"A",task:"32"); XCTFail() }
        catch { XCTAssertEqual(error as? SchoolPortalIssue,.unavailable) }
        XCTAssertEqual(reads,0)
        let late=Task { try await store.readTaskMaterial(term:"A",task:"31") }
        while gate == nil { await Task.yield() }
        store.beginManualReview()
        let object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(sample))
        gate?.resume(returning:try JSONSerialization.data(withJSONObject:["owner":owner,"value":object]))
        do { _ = try await late.value; XCTFail("Old session returned material") } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testFileTransportIsAnExactAuthorizedDocumentNotAnArbitraryURL() throws {
        func permitted(_ url: String) -> Bool {
            guard let u=URL(string:url) else { return false }
            return SchoolTaskFilePolicy.permits(u,task:"31",section:.answer,key:"id:9")
        }
        let base=SchoolPortalPage.origin.absoluteString+"/api/LearningTask/DownloadDocument?"
        XCTAssertTrue(permitted(base+"documentId=9&learningTaskId=31&documentType=2"))
        XCTAssertFalse(permitted(base+"documentId=9&learningTaskId=32&documentType=2"))
        XCTAssertFalse(permitted(base+"documentId=9&learningTaskId=31&documentType=1"))
        XCTAssertFalse(permitted(base+"documentId=9&documentId=10&learningTaskId=31&documentType=2"))
        for url in ["http://assets.schoolis.cn/files/9","https://assets.schoolis.cn.attacker.invalid/file",
                    "https://u:p@assets.schoolis.cn/file","https://127.0.0.1/file","file:///notes","https://assets.schoolis.cn:8080/file",
                    SchoolPortalPage.origin.absoluteString+"/api/LearningTask/Save"] {
            XCTAssertFalse(permitted(url))
        }
        XCTAssertTrue(permitted("https://assets.schoolis.cn/file"))
        let invalid=SchoolTaskMaterial(instructions:sample.instructions,answer:sample.answer,
            feedback:.init(state:.hidden,text:"Must not escape",files:[]),submitted:nil)
        XCTAssertThrowsError(try invalid.validate())
    }
}
