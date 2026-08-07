import Foundation
import SwiftDunk
@testable import SwiftDunkCore
import Testing

@Suite("SwiftDunk errors")
struct SwiftDunkErrorTests {
    @Test("Security failures preserve their OS status and underlying NSError")
    func securityFrameworkFailure() throws {
        let status = -25_308
        let error = SwiftDunkError.securityFrameworkError(status: status)

        #expect(error.code == .securityFramework(status: status))
        let underlying = try #require(error.underlyingError as? NSError)
        #expect(underlying.domain == NSOSStatusErrorDomain)
        #expect(underlying.code == status)
    }

    @Test("Operation-in-progress errors name the protected operation")
    func operationInProgressDescription() {
        let error = SwiftDunkError(
            code: .operationInProgress("authentication")
        )

        #expect(
            error.errorDescription == "Another authentication operation is already in progress.")
    }

    @Test("Two-factor delivery descriptions use the available service fields")
    func twoFactorDeliveryDescriptions() {
        let cases: [(TwoFactorDeliveryFailure, String)] = [
            (
                TwoFactorDeliveryFailure(
                    serviceCode: -28_248,
                    title: "Verification Failed",
                    message: "Choose another method."
                ),
                "Apple could not deliver the two-factor code (-28248): Verification Failed: Choose another method."
            ),
            (
                TwoFactorDeliveryFailure(serviceCode: -22_979, title: "Too Many Codes"),
                "Apple could not deliver the two-factor code (-22979): Too Many Codes"
            ),
            (
                TwoFactorDeliveryFailure(serviceCode: -22_981, message: "Try again later."),
                "Apple could not deliver the two-factor code (-22981): Try again later."
            ),
            (
                TwoFactorDeliveryFailure(serviceCode: -21_669),
                "Apple could not deliver the two-factor code (-21669)."
            ),
        ]

        for (failure, expectedDescription) in cases {
            let error = SwiftDunkError(code: .twoFactorDeliveryFailed(failure))
            #expect(error.errorDescription == expectedDescription)
        }
    }
}
