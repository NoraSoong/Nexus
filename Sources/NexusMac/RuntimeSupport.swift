import Foundation
import NexusCore

let assistantExposureDefaultsKey = "assistantExposureEnabled"
let contextModelProviderDefaultsKey = "contextModelProvider"

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

func publishRuntimeHeartbeatFromDefaults() {
    try? NexusRuntime.markAppRunning(exposureEnabled: storedAssistantExposureEnabled())
}
