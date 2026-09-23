import AppKit
import SwiftUI

struct LicenseGateView: View {
    @ObservedObject var accessController: LicenseAccessController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your trial has ended")
                .font(.headline)

            Text("Enter your license key to keep using PasteQueue. Your queue is preserved.")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LicenseActivationForm(accessController: accessController, showsPurchaseButton: true)

            HStack {
                Spacer()
                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(width: 320)
    }
}

struct LicenseSettingsSection: View {
    @ObservedObject var accessController: LicenseAccessController
    @State private var showsActivation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch accessController.state {
            case .licensed:
                Label("License active", systemImage: "checkmark.seal.fill")
                    .font(.callout)
                    .foregroundColor(.secondary)
            case .trial(let daysRemaining, _):
                HStack {
                    Text("Trial: \(daysRemaining) days left")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(showsActivation ? "Cancel" : "Activate License") {
                        accessController.clearActivationError()
                        showsActivation.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.callout)
                }
                if showsActivation {
                    LicenseActivationForm(accessController: accessController, showsPurchaseButton: true)
                }
            case .expired:
                LicenseActivationForm(accessController: accessController, showsPurchaseButton: true)
            case .storageUnavailable:
                Text("Access available")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
        .onChange(of: accessController.state) { newState in
            if newState == .licensed {
                showsActivation = false
            }
        }
    }
}

private struct LicenseActivationForm: View {
    @ObservedObject var accessController: LicenseAccessController
    let showsPurchaseButton: Bool

    @State private var licenseKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField("License key", text: $licenseKey)
                .textFieldStyle(.roundedBorder)
                .onSubmit(activate)

            if let error = accessController.activationError {
                Text(message(for: error))
                    .font(.caption)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Button(accessController.isActivating ? "Activating…" : "Activate") {
                    activate()
                }
                .disabled(accessController.isActivating || normalizedKey.isEmpty)

                if showsPurchaseButton, let checkoutURL = accessController.checkoutURL {
                    Button("Buy License") {
                        NSWorkspace.shared.open(checkoutURL)
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.callout)
        }
    }

    private var normalizedKey: String {
        licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func activate() {
        guard !normalizedKey.isEmpty, !accessController.isActivating else { return }
        Task {
            await accessController.activate(licenseKey: normalizedKey)
            if accessController.state == .licensed {
                licenseKey = ""
            }
        }
    }

    private func message(for error: LicenseActivationError) -> LocalizedStringKey {
        switch error {
        case .invalidKey:
            return "This license key is invalid or inactive."
        case .activationLimitReached:
            return "This license is already active on three devices. Deactivate one device and try again."
        case .noNetwork:
            return "Connect to the internet and try again."
        case .wrongProduct:
            return "This key belongs to a different product."
        case .storageUnavailable:
            return "The license could not be saved securely on this Mac."
        case .configurationUnavailable:
            return "License activation is not configured in this build."
        case .serviceUnavailable:
            return "The license service is unavailable. Try again later."
        }
    }
}
