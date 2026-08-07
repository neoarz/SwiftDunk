import Foundation

enum AppTokenVectors {
    static let applicationName = "com.apple.gs.xcode.auth"
    static let dsid = "1234567890"
    static let tokenValue = "golden-xcode-token"
    static let sessionKey = Data(repeating: 0xA5, count: 32)
    static let context = Data([0xCA, 0xFE])
    static let checksum =
        "b7029bbb3a607e775ea230913aab74e2f25f1c4a17e439989bd0dc6d7ba61896"
    static let createdAtMilliseconds = 1_700_000_000_000
    static let expiryMilliseconds = 1_731_536_000_000
    static let encryptedToken =
        """
        58595a000102030405060708090a0b0c0d0e0f8a0b9131c5865bfa0d4815857e13cb57cb8a064b05ec\
        29774afc2e58fb77e0bfaffe5f2d59dfdda07941f900997a69129ddd267c4ee6a6d3ca3096a6f5d14e\
        9d01c4f3f0cd9051166da776ccb1e1cdb5e350403daa67f1b964d3a70dec9245eed1e14186a2f63d1b\
        6b976b8ce0d20e9a45d6f68a6a8592e1f02789b1777722e56556f0c6bb6b477c7e162bb5801f98c234\
        89aeecc30d52f36e514e49c6c1b1f39fa6d6cb9cd81daac272aa021ebc75da7833aee23ef767c30cda\
        12a6c0ff1c4451fd88093d7f3781f0cdd86cac77cc98f9f579242922ad9a2dd59e596e8aac63c39dca\
        568812c3f9bcc5609021a1dd7253672ecd4312eee7d165cc3358f9db197ef69bf58493e4c2f49c85238\
        07359ec5b3ee919b91cf021c0e1206c39970dd9cd518e69fbd35840bce6e306ecfddeb6062158abee8b\
        d73b0ff8c0184cdd01a64baab098f17e50fe6a1de2417a1a78c1ea024ee6171d7cf7030aa6459cd4d4\
        abdfede242e495cd512238e7ef3bb412b472dd6d2dee6109c5f88ef648fe0426208197e059df733df18\
        81c00e6a80b977aef0694c7ca51fe0ce666a9acb6359754b052c85ccd93ca3bc99021d7aa32418e7ac\
        86b7a055923703f5ea31eab23ecbf9dce5417c86ace416ebcbdec8cc7697e
        """
}
