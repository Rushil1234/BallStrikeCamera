import Foundation

enum BackendFactory {
    static func make() -> AppBackend {
        if let config = SupabaseConfig.load() {
            return SupabaseBackendService(config: config)
        }
        print("[TrueCarry] BackendFactory — selected LocalBackendService")
        return LocalBackendService()
    }
}
