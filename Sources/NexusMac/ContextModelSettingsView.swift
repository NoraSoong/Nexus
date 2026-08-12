import NexusCore
import SwiftUI

struct ContextModelSettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var l10n: L10n { model.l10n }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(l10n.contextModelSettingsTitle)
                        .font(.title2.weight(.semibold))
                    Text(l10n.contextAPIKeyDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help(l10n.cancel)
            }

            Divider()
                .padding(.top, 18)

            VStack(alignment: .leading, spacing: 14) {
                Picker("", selection: providerBinding) {
                    ForEach(ContextModelProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if model.contextModelProvider == .deepSeek {
                    modelChoice
                }

                if model.hasContextAPIKey && !model.isReplacingContextModelKey {
                    connectedContent
                } else {
                    credentialForm
                }

                if !model.contextAPIKeyStatus.isEmpty {
                    Text(model.contextAPIKeyStatus)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 20)

            Spacer()

            HStack {
                Spacer()
                Button(l10n.done) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .onDisappear {
            model.cancelContextModelKeyReplacement()
        }
    }

    private var connectedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        l10n.contextModelConnection(
                            ContextModelConfiguration(
                                provider: model.contextModelProvider,
                                model: model.contextModelSelection
                            )
                        )
                    )
                        .font(.callout.weight(.semibold))
                    Text(l10n.connectionVerified)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Button(l10n.verifyConnection) {
                    model.verifyContextAPIKey()
                }
                Button(l10n.changeContextModel) {
                    model.beginContextModelKeyReplacement()
                }
                Button(l10n.removeAPIKey, role: .destructive) {
                    model.removeContextAPIKey()
                }
            }
            .controlSize(.small)
        }
    }

    private var modelChoice: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(l10n.contextModelChoiceTitle)
                .font(.headline)
            Picker("", selection: modelBinding) {
                Text(l10n.contextModelChoiceFlash)
                    .tag(DeepSeekContextModelClient.flashModel)
                Text(l10n.contextModelChoicePro)
                    .tag(DeepSeekContextModelClient.proModel)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(l10n.contextModelChoiceHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var credentialForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.contextAPIKeyTitle)
                .font(.headline)
            HStack(spacing: 8) {
                SecureField(
                    l10n.contextAPIKeyPlaceholder(model.contextModelProvider),
                    text: $model.contextAPIKeyInput
                )
                .textFieldStyle(.roundedBorder)
                Button(l10n.connectContextModel) {
                    model.connectContextModel()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    model.contextAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || model.contextAPIKeyStatus == l10n.verifying
                )
            }
        }
    }

    private var providerBinding: Binding<ContextModelProvider> {
        Binding(
            get: { model.contextModelProvider },
            set: { model.selectContextModelProvider($0) }
        )
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { model.contextModelSelection },
            set: { model.selectContextModel($0) }
        )
    }

    private var statusColor: Color {
        model.hasContextAPIKey || model.contextAPIKeyStatus == l10n.verifying
            ? .secondary
            : .red
    }
}
