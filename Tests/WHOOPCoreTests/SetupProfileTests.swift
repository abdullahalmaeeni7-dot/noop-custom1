import XCTest
@testable import WHOOPCore

final class SetupProfileTests: XCTestCase {
    func testRequiredDetailsAndBirthdayAge() throws {
        var profile = ProfilePersonalization(displayName: "Alex")
        XCTAssertThrowsError(try profile.validatedForSetup())
        profile.birthDate = DayCalendar.utc.date(from: DateComponents(year: 2010, month: 6, day: 15))!
        profile.gender = .man
        XCTAssertThrowsError(try profile.validatedForSetup())
        profile.wearWrist = .right
        let saved = try profile.validatedForSetup()
        let years = DayCalendar.utc.dateComponents([.year], from: profile.birthDate!, to: DashboardDatePolicy.today()).year!
        XCTAssertEqual(saved.age, String(years))
        XCTAssertEqual(saved.wearWrist, .right)
    }

    func testLegacyProfileRemainsReadableAndCanBeCompleted() throws {
        let old = Data(#"{"displayName":"Alex","username":"alex","age":"24","whoopAge":"22.6"}"#.utf8)
        let profile = try JSONDecoder().decode(ProfilePersonalization.self, from: old)
        XCTAssertEqual(try profile.validated().age, "24")
        XCTAssertFalse(profile.hasRequiredDetails)
        XCTAssertThrowsError(try profile.validatedForSetup())
    }

    func testDetailsRoundTripAndFutureBirthdayRejected() throws {
        var profile = ProfilePersonalization()
        profile.birthDate = DayCalendar.utc.date(from: DateComponents(year: 2000, month: 2, day: 29))!
        profile.gender = .woman
        profile.wearWrist = .left
        profile = try profile.validatedForSetup()
        let encoded = try ImportReader.jsonEncoder().encode(profile)
        XCTAssertEqual(try ImportReader.jsonDecoder().decode(ProfilePersonalization.self, from: encoded), profile)
        profile.birthDate = Date().addingTimeInterval(3 * 86_400)
        XCTAssertThrowsError(try profile.validatedForSetup())
    }
}
