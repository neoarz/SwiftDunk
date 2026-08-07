package import Foundation

struct AccountMaterial: Sendable {
    let appleID: String
    let firstName: String
    let lastName: String
    let dsid: String
    let idmsToken: String
    let sessionKey: Data
    let context: Data
    let hasPersonalToken: Bool

    init(decryptedSPD: Data, fallbackAppleID: String) throws {
        let root = try AuthPropertyListDecoder.decode(
            decryptedSPD,
            key: "spd",
            expected: "a decrypted property-list dictionary"
        )
        guard let values = root.dictionary else {
            throw SwiftDunkError(
                code: .malformedResponse(key: "spd", expected: "a property-list dictionary")
            )
        }
        let plist = PlistValue.dictionary(values)
        appleID = values["appleId"]?.string ?? fallbackAppleID
        firstName = values["fn"]?.string ?? ""
        lastName = values["ln"]?.string ?? ""
        dsid = try plist.requireString("adsid")
        idmsToken = try plist.requireString("GsIdmsToken")
        self.sessionKey = try plist.requireData("sk")
        context = try plist.requireData("c")
        hasPersonalToken =
            values["t"]?.dictionary?[AuthConstants.personalTokenName]?.dictionary?["token"]?.string
            != nil
    }

    func account(
        anisette: any AnisetteProvider,
        transport: any HTTPTransport
    ) -> Account {
        Account(
            appleID: appleID,
            firstName: firstName,
            lastName: lastName,
            dsid: dsid,
            idmsToken: idmsToken,
            sessionKey: sessionKey,
            context: context,
            anisette: anisette,
            transport: transport
        )
    }

    var identityToken: String {
        Data("\(dsid):\(idmsToken)".utf8).base64EncodedString()
    }
}
