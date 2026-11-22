import XCTest

@MainActor final class SeasonalTouchUITests:XCTestCase {
    var app:XCUIApplication!
    var state:XCUIElement {app.staticTexts["seasonal-state"]}
    func launch(_ theme:String,_ extra:[String]=[]) throws -> XCUICoordinate {
        continueAfterFailure=false
        app=XCUIApplication();app.launchArguments=[theme]+extra;app.launch()
        XCTAssertTrue(state.waitForExistence(timeout:12))
        XCTAssertTrue(wait { self.fields().count == 8 }, "No exposed Metal target")
        let xy=fields()[0].split(separator:",").compactMap {Double($0)}
        XCTAssertEqual(xy.count,2)
        return app.coordinate(withNormalizedOffset:.init(dx:xy[0],dy:xy[1]))
    }
    func fields()->[String] { (state.value as? String ?? "").components(separatedBy:";") }
    func wait(_ f:@escaping ()->Bool)->Bool {
        let e=XCTNSPredicateExpectation(predicate:NSPredicate{_,_ in f()},object:nil)
        return XCTWaiter.wait(for:[e],timeout:8) == .completed
    }
    func testShippingEnvironmentPickerSelectsTerm() throws {
        continueAfterFailure=false
        app=XCUIApplication()
        // This assertion reads the Chinese term label. Keep it independent of the QA iPad language.
        app.launchArguments=["-AppleLanguages","(zh-Hans)","-AppleLocale","zh_CN","--environment","christmas"]
        app.launch()
        let picker=app.buttons["sky-season-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout:10))
        if !picker.isHittable { app.swipeUp() }
        picker.tap()
        let term=app.buttons["立春"].firstMatch
        if !term.isHittable { app.swipeUp() }
        XCTAssertTrue(term.waitForExistence(timeout:4))
        term.tap()
        XCTAssertTrue(wait { (picker.value as? String)?.contains("立春")==true || picker.label.contains("立春") })
    }
    func testActualWaterTapAndVerticalScrollPriority() throws {
        let p=try launch("springRain",["--water"])
        p.press(forDuration:0.12,thenDragTo:p.withOffset(.init(dx:0,dy:-190)))
        XCTAssertTrue(wait{self.fields().last=="true"})
        XCTAssertEqual(fields()[3],"0")
        p.tap()
        XCTAssertTrue(wait{self.fields()[3]=="2"})
    }
    func testActualBrushAndForegroundButtonPriority() throws {
        var p=try launch("grainRain",["--cover"])
        p.tap()
        XCTAssertTrue(wait{self.fields()[6]=="1"})
        XCTAssertEqual(fields()[3],"0","A foreground button also bent the hidden branch")
        p=try launch("grainRain")
        p.press(forDuration:0.15,thenDragTo:p.withOffset(.init(dx:73,dy:1)))
        XCTAssertTrue(wait{self.fields()[3]=="1" && (Double(self.fields()[4]) ?? 0)>0.25 && self.fields()[5]=="false"})
    }
    func testActualRabbitAndGiftContact() throws {
        var p=try launch("midautumn")
        p.tap();XCTAssertTrue(wait{self.fields()[1]=="true"})
        p=try launch("christmas")
        // Rejection is an ordinary outcome. Frame is held until an accepted drop.
        for _ in 0..<12 {
            if fields()[2]=="true" {break}
            p.tap()
        }
        XCTAssertTrue(wait{self.fields()[2]=="true"})
        XCTAssertEqual(fields()[1],"false")
    }
    func testVisibleInsectVersusEmptySky() throws {
        let insect=try launch("awakening")
        app.coordinate(withNormalizedOffset:.init(dx:0.18,dy:0.27)).tap()
        XCTAssertEqual(fields()[3],"0")
        insect.tap()
        XCTAssertTrue(wait{self.fields()[3]=="1"})
        XCTAssertEqual(fields()[1],"false")
    }
    func testPerchedBirdReceivesTapWithMotionPaused() throws {
        let bird=try launch("lesserCold")
        bird.tap()
        XCTAssertTrue(wait {self.fields()[3]=="1"})
        XCTAssertEqual(fields()[1],"false")
        XCTAssertEqual(fields()[2],"false")
    }
    func testFineSilkAndCorollaReceiveAPausedTap() throws {
        for plate in ["coldDew","greaterHeat"] {
            let surface=try launch(plate)
            app.coordinate(withNormalizedOffset:.init(dx:0.17,dy:0.25)).tap()
            XCTAssertEqual(fields()[3],"0",plate+" reacted to empty sky")
            surface.tap()
            XCTAssertTrue(wait {self.fields()[3]=="1"},plate+" missed its visible subject")
        }
    }
    func testOnlyHangingLanternCanIgnite() throws {
        let lantern=try launch("halloween")
        app.coordinate(withNormalizedOffset:.init(dx:0.20,dy:0.41)).tap()
        XCTAssertEqual(fields()[3],"0")
        lantern.tap()
        XCTAssertTrue(wait {self.fields()[3]=="1"})
        XCTAssertEqual(fields()[1],"false")
    }
}
