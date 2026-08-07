import Darwin
import Foundation
import SwiftDunk

enum Console {
    static func chooseCommand() throws -> CLICommand? {
        print(
            """
            SwiftDunk
            1. Inspect account
            2. Provision an App ID
            3. Log out
            """
        )
        guard let choice = requiredPrompt("Choice: ") else { return nil }
        switch choice {
        case "1": return .inspect
        case "2": return .provision
        case "3": return .logout
        default: throw CLIError("Choose 1, 2, or 3.")
        }
    }

    static func printUsage() {
        print(
            """
            Usage: swift run swiftdunk-cli <command>

              inspect      Show account and Developer Portal resources without changing them
              provision    Ensure an App ID and fetch its provisioning profile
              logout       Remove the saved SwiftDunk session
            """
        )
    }

    static func requiredPrompt(_ prompt: String) -> String? {
        print(prompt, terminator: "")
        guard let value = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        return value.isEmpty ? nil : value
    }

    static func confirm(_ prompt: String) -> Bool {
        requiredPrompt("\(prompt) [y/N]: ")?.lowercased() == "y"
    }

    static func readPassword() -> String? {
        guard let password = getpass("Password: ") else { return nil }
        return String(cString: password)
    }

    static func twoFactorResponse(_ challenge: TwoFactorChallenge) -> TwoFactorResponse {
        while true {
            if let error = challenge.previousDeliveryError {
                print("Delivery failed: \(SwiftDunkError(code: error).localizedDescription)")
                print("Choose another method or try again.")
            }
            let prompt: String
            switch challenge.method {
            case .trustedDevice:
                prompt = "Two-factor code (or \"sms\" / \"resend\"): "
            case .sms:
                if let phone = selectedPhone(in: challenge) {
                    let label =
                        challenge.previousDeliveryError == nil ? "Code sent to" : "SMS number:"
                    print("\(label) \(phone.numberWithDialCode).")
                }
                prompt = "Two-factor code (or \"sms\" / \"devices\" / \"resend\"): "
            }

            guard let response = requiredPrompt(prompt) else { return .code("") }
            switch response.lowercased() {
            case "resend", "r":
                return .resendCode
            case "devices", "d":
                return .sendToTrustedDevices
            case "sms", "s":
                guard let phone = choosePhoneNumber(from: challenge.trustedPhoneNumbers) else {
                    print("No trusted phone number is available for SMS.")
                    continue
                }
                print("Sending SMS to \(phone.numberWithDialCode).")
                return .sendSMS(phoneNumberID: phone.id)
            default:
                return .code(response)
            }
        }
    }

    private static func selectedPhone(
        in challenge: TwoFactorChallenge
    ) -> TrustedPhoneNumber? {
        challenge.trustedPhoneNumbers.first {
            $0.id == challenge.selectedPhoneNumberID
        }
    }

    private static func choosePhoneNumber(
        from phoneNumbers: [TrustedPhoneNumber]
    ) -> TrustedPhoneNumber? {
        guard phoneNumbers.count > 1 else { return phoneNumbers.first }
        print("Trusted phone numbers:")
        for (index, phone) in phoneNumbers.enumerated() {
            print("\(index + 1). \(phone.numberWithDialCode)")
        }
        guard let value = requiredPrompt("Phone: "), let index = Int(value).map({ $0 - 1 }) else {
            return nil
        }
        return phoneNumbers.indices.contains(index) ? phoneNumbers[index] : nil
    }

    static func chooseTeam(from teams: [Team], rememberedID: String?) -> Team? {
        if let rememberedID, let team = teams.first(where: { $0.id.rawValue == rememberedID }) {
            print("Using team: \(team.name)")
            return team
        }
        for (index, team) in teams.enumerated() {
            print("\(index + 1). \(team.name)")
        }
        guard let value = requiredPrompt("Team: ") else { return teams.first }
        let index = (Int(value) ?? 0) - 1
        return teams.indices.contains(index) ? teams[index] : nil
    }
}
