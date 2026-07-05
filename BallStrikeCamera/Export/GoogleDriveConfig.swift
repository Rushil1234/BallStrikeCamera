import Foundation

// MARK: - Google Drive Configuration
// OAuth client ID for the "dev mode" auto-upload-to-Drive feature (real-time shot frame export
// for comparing against a reference launch monitor). iOS OAuth client IDs are not secret — they're
// meant to ship inside the app binary — so this is a plain constant, unlike the API keys in
// Secrets.plist which must stay out of source control.

enum GoogleDriveConfig {
    static let clientId = "248606735030-99bs7nvuq9qcd7hh3oj9fau9fbd1v652.apps.googleusercontent.com"

    /// Reversed-client-ID URL scheme registered in Info.plist, used as the OAuth redirect target.
    static let redirectURI = "com.googleusercontent.apps.248606735030-99bs7nvuq9qcd7hh3oj9fau9fbd1v652:/oauth2redirect"

    /// `drive.file` only grants access to files this app creates — narrow enough to skip Google's
    /// sensitive-scope verification review entirely.
    static let scope = "https://www.googleapis.com/auth/drive.file"

    static let authorizationEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    static let tokenEndpoint = "https://oauth2.googleapis.com/token"
    static let driveFilesEndpoint = "https://www.googleapis.com/drive/v3/files"
    static let driveUploadEndpoint = "https://www.googleapis.com/upload/drive/v3/files"

    /// Name of the Drive folder shots are uploaded into (created on first upload if missing).
    static let uploadFolderName = "TrueCarry Frames"
}
