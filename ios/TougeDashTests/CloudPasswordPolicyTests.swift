import XCTest
@testable import TougeDash

final class CloudPasswordPolicyTests: XCTestCase {
    func testRegistrationPasswordNeedsLetterNumberAndReasonableLength() {
        XCTAssertFalse(CloudPasswordPolicy.isValid("same-litery"))
        XCTAssertFalse(CloudPasswordPolicy.isValid("1234567890"))
        XCTAssertTrue(CloudPasswordPolicy.isValid("telemetria42"))
    }

    func testStrengthRewardsVarietyWithoutRequiringBankStylePassword() {
        XCTAssertEqual(CloudPasswordPolicy.strength("telemetria42").label, "W porządku")
        XCTAssertEqual(CloudPasswordPolicy.strength("DlugieHaslo").label, "Uzupełnij wymagania")
        XCTAssertEqual(CloudPasswordPolicy.strength("Touge-Dash-42").label, "Mocne")
    }
}
