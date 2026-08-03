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

final class CloudAccountServiceTests: XCTestCase {
    func testProductionAddressReplacesMissingAndLocalDevelopmentValues() {
        let production = "https://touge-dash-engine.letscode.it"

        XCTAssertEqual(CloudAccountService.resolvedAddress(nil, productionAddress: production), production)
        XCTAssertEqual(
            CloudAccountService.resolvedAddress("http://localhost:8181", productionAddress: production),
            production
        )
        XCTAssertEqual(
            CloudAccountService.resolvedAddress("http://127.0.0.1:8181", productionAddress: production),
            production
        )
    }

    func testCustomRemoteAddressIsPreserved() {
        let custom = "https://staging-touge-dash.example.com"

        XCTAssertEqual(
            CloudAccountService.resolvedAddress(custom, productionAddress: "https://touge-dash-engine.letscode.it"),
            custom
        )
    }
}
