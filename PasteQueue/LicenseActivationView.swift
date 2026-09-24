import AppKit
import SwiftUI

struct TrialWarningView: View {
    let daysRemaining: Int
    let checkoutURL: URL?
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundColor(.orange)
            Text("Trial: \(daysRemaining) days left")
                .font(.caption)
            Spacer(minLength: 4)
            if let checkoutURL {
                Button("Buy License") {
                    NSWorkspace.shared.open(checkoutURL)
                }
                .buttonStyle(.plain)
                .font(.caption)
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
    }
}

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
    @State private var showsDeactivationConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch accessController.state {
            case .licensed:
                HStack {
                    Label("License active", systemImage: "checkmark.seal.fill")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(accessController.isDeactivating ? "Deactivating…" : "Deactivate This Mac") {
                        accessController.clearDeactivationError()
                        showsDeactivationConfirmation = true
                    }
                    .buttonStyle(.plain)
                    .disabled(accessController.isDeactivating)
                }
                .font(.callout)

                if let error = accessController.deactivationError {
                    Text(deactivationMessage(for: error))
                        .font(.caption)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
        .confirmationDialog(
            "Deactivate This Mac?",
            isPresented: $showsDeactivationConfirmation,
            titleVisibility: .visible
        ) {
            Button("Deactivate", role: .destructive) {
                Task {
                    await accessController.deactivateCurrentDevice()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("PasteQueue will stop working on this Mac when the trial has ended. This frees one of your three device slots.")
        }
    }

    private func deactivationMessage(for error: LicenseDeactivationError) -> LocalizedStringKey {
        switch error {
        case .noNetwork:
            return "Connect to the internet to deactivate this Mac."
        case .storageUnavailable:
            return "The device slot was released, but the local license could not be removed. Try again."
        case .configurationUnavailable:
            return "License deactivation is not configured in this build."
        case .serviceUnavailable:
            return "The license service is unavailable. Try again later."
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
