import Foundation
import SwiftDunk

enum Output {
    static func printInspection(
        account: DeveloperInfo,
        team: Team,
        devices: [Device],
        inventory: AppIDInventory,
        certificates: [Certificate]
    ) {
        let name = [account.firstName, account.lastName].compactMap { $0 }.joined(separator: " ")
        print("\nAccount")
        print("    Name               \(name.isEmpty ? "Not supplied" : name)")
        print("    Apple ID           \(account.email ?? "Not supplied")")
        print("    Status             \(account.status ?? "Not supplied")")
        print("\nTeam")
        print("    Name               \(team.name)")
        print("    Type               \(team.type ?? "Not supplied")")
        print("    Free provisioning  \(yesOrNo(team.isXcodeFreeOnly))")
        printDevices(devices)
        printAppIDs(inventory)
        printCertificates(certificates)
    }

    static func printDevices(_ devices: [Device]) {
        print("\nDevices (\(devices.count)):")
        printItems(devices.map { "\($0.name) (\($0.udid))" })
    }

    static func printAppIDs(_ inventory: AppIDInventory) {
        var summary = ["\(inventory.appIDs.count) registered"]
        if let maximum = inventory.maximumQuantity {
            summary[0] = "\(inventory.appIDs.count) of \(maximum) registered"
        }
        if let available = inventory.availableQuantity {
            summary.append("\(available) available")
        }
        print("\nApp IDs (\(summary.joined(separator: ", "))):")
        if inventory.appIDs.isEmpty {
            print("- None")
        }
        for appID in inventory.appIDs {
            print("- \(appID.identifier)")
            print("  Expires: \(formatted(appID.expirationDate))")
        }
    }

    static func printCertificates(_ certificates: [Certificate]) {
        print("\nCertificates (\(certificates.count)):")
        printItems(
            certificates.map {
                let name = $0.name ?? $0.machineName ?? "Unnamed certificate"
                return "\(name) — expires \(formatted($0.expirationDate))"
            }
        )
    }

    static func printProfile(_ profile: ProvisioningProfile) {
        print("\nProvisioning profile")
        print("    Type               \(profile.type ?? "Not supplied")")
        print("    Distribution       \(profile.distributionMethod ?? "Not supplied")")
        print("    Platform           \(profile.platform ?? "Not supplied")")
        print("    Managed by         \(profile.managingApp ?? "Not supplied")")
        print("    Template profile   \(yesOrNo(profile.isTemplateProfile))")
        print("    Team profile       \(yesOrNo(profile.isTeamProfile))")
        print("    Expires            \(formatted(profile.expirationDate))")
    }

    private static func printItems(_ items: [String]) {
        if items.isEmpty {
            print("- None")
        } else {
            for item in items {
                print("- \(item)")
            }
        }
    }

    private static func formatted(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .shortened) ?? "Not supplied"
    }

    private static func yesOrNo(_ value: Bool?) -> String {
        value.map { $0 ? "Yes" : "No" } ?? "Not supplied"
    }

    private static func yesOrNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }
}
