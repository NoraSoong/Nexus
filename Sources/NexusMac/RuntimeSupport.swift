import Foundation
import NexusCore

let assistantExposureDefaultsKey = "assistantExposureEnabled"
let contextModelProviderDefaultsKey = "contextModelProvider"
let contextModelDefaultsPrefix = "contextModel."

func storedAssistantExposureEnabled() -> Bool {
    guard UserDefaults.standard.object(forKey: assistantExposureDefaultsKey) != nil else {
        return true
    }
    return UserDefaults.standard.bool(forKey: assistantExposureDefaultsKey)
}

func storedContextModelProvider() -> ContextModelProvider {
    guard let rawValue = UserDefaults.standard.string(forKey: contextModelProviderDefaultsKey),
        let provider = ContextModelProvider(rawValue: rawValue)
    else {
        return .deepSeek
    }
    return provider
}

func contextModelDefaultsKey(for provider: ContextModelProvider) -> String {
    contextModelDefaultsPrefix + provider.rawValue
}

func storedContextModel(for provider: ContextModelProvider) -> String {
    let stored = UserDefaults.standard.string(forKey: contextModelDefaultsKey(for: provider))
    switch provider {
    case .deepSeek:
        if let stored,
            [DeepSeekContextModelClient.flashModel, DeepSeekContextModelClient.proModel].contains(stored)
        {
            return stored
        }
        return provider.defaultModel
    case .openAI:
        return provider.defaultModel
    }
}

func publishRuntimeHeartbeatFromDefaults() {
    try? NexusRuntime.markAppRunning(exposureEnabled: storedAssistantExposureEnabled())
}
