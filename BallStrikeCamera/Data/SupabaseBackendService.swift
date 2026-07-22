import Foundation
import CoreLocation

// MARK: - Supabase REST backend
// URLSession + Supabase REST / Auth APIs (no Swift package required).
// Activated by BackendFactory when Secrets.plist contains valid SupabaseURL + SupabaseAnonKey.
// Only the anon (publishable) key is used here. Service-role key must NEVER be in the app.

final class SupabaseBackendService: AppBackend {

    private let config: SupabaseConfig
    private var accessToken: String?
    private var refreshToken: String?
    private let session: URLSession = .shared

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    init(config: SupabaseConfig) {
        self.config = config
        self.accessToken  = UserDefaults.standard.string(forKey: "sb_access_token")
        self.refreshToken = UserDefaults.standard.string(forKey: "sb_refresh_token")
        print("[TrueCarry][Supabase] Initialized — base: \(config.baseURL.absoluteString)")
    }

    // MARK: - Auth

    func currentUser() async throws -> AppUser? {
        if accessToken == nil, refreshToken != nil {
            try? await refreshSession()
        }
        // A locally-expired token is a guaranteed 403 — the exp claim already says so,
        // so refresh BEFORE the request instead of burning a round-trip (and an ERROR
        // log line on every cold launch) to be told by the server.
        if let token = accessToken, refreshToken != nil,
           let expiry = Self.tokenExpiry(token), expiry <= Date().addingTimeInterval(60) {
            try? await refreshSession()
        }
        guard let token = accessToken else { return nil }

        if let user = try await fetchCurrentUser(accessToken: token) {
            return user
        }
        guard refreshToken != nil else { return nil }

        try? await refreshSession()
        guard let refreshedToken = accessToken, refreshedToken != token else { return nil }
        return try await fetchCurrentUser(accessToken: refreshedToken)
    }

    private func fetchCurrentUser(accessToken token: String) async throws -> AppUser? {
        let url = config.authBaseURL.appendingPathComponent("user")
        var req = baseRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: req)

        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            logError("currentUser", data: data, response: response)
            return nil
        }
        let su = try decoder.decode(SupabaseUser.self, from: data)
        print("[TrueCarry][Supabase] currentUser — \(su.email ?? "no-email")")
        return appUser(from: su)
    }

    func signIn(email: String, password: String) async throws -> AppUser {
        let url = config.authBaseURL
            .appendingPathComponent("token")
            .appending(queryItems: [URLQueryItem(name: "grant_type", value: "password")])
        var req = baseRequest(url: url, method: "POST")
        req.httpBody = try encoder.encode(SupabaseSignInRequest(email: email, password: password))
        let (data, response) = try await session.data(for: req)

        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            logError("signIn", data: data, response: response)
            throw BackendError.wrongPassword
        }
        let auth = try decoder.decode(SupabaseAuthResponse.self, from: data)
        persistSession(auth)
        print("[TrueCarry][Supabase] signIn — \(auth.user.email ?? "?")")
        return appUser(from: auth.user)
    }

    /// Native Sign in with Apple: exchanges the Apple identity token (+ raw nonce)
    /// for a Supabase session via the id_token grant. No web redirect.
    func signInWithApple(idToken: String, nonce: String) async throws -> AppUser {
        let url = config.authBaseURL
            .appendingPathComponent("token")
            .appending(queryItems: [URLQueryItem(name: "grant_type", value: "id_token")])
        var req = baseRequest(url: url, method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "provider": "apple",
            "id_token": idToken,
            "nonce": nonce,
        ])
        let (data, response) = try await session.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            logError("signInWithApple", data: data, response: response)
            throw BackendError.notAuthenticated
        }
        let auth = try decoder.decode(SupabaseAuthResponse.self, from: data)
        persistSession(auth)
        print("[TrueCarry][Supabase] signInWithApple — \(auth.user.email ?? "?")")
        return appUser(from: auth.user)
    }

    func createAccount(name: String, email: String, password: String) async throws -> AppUser {
        let url = config.authBaseURL.appendingPathComponent("signup")
        var req = baseRequest(url: url, method: "POST")
        let body = SupabaseSignUpRequest(email: email, password: password, data: ["display_name": name])
        req.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: req)

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 201 else {
            logError("createAccount", data: data, response: response)
            throw BackendError.emailAlreadyExists
        }
        let auth = try decoder.decode(SupabaseSignUpResponse.self, from: data)
        if let accessToken = auth.accessToken, let refreshToken = auth.refreshToken {
            persistSession(accessToken: accessToken, refreshToken: refreshToken)
            print("[TrueCarry][Supabase] createAccount — \(auth.user.email ?? "?")")
            return appUser(from: auth.user)
        }
        print("[TrueCarry][Supabase] createAccount confirmation required — \(auth.user.email ?? email)")
        throw BackendError.emailConfirmationRequired(auth.user.email ?? email)
    }

    func sendPasswordReset(email: String) async throws {
        var components = URLComponents(url: config.authBaseURL.appendingPathComponent("recover"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "redirect_to", value: AppConfig.websiteURL.appendingPathComponent("reset-password").absoluteString)
        ]
        var req = baseRequest(url: components.url!, method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["email": email])
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 204 else {
            logError("sendPasswordReset", data: data, response: response)
            throw BackendError.networkError("Could not send password reset email.")
        }
    }

    func resendConfirmationEmail(email: String) async throws {
        var req = baseRequest(url: config.authBaseURL.appendingPathComponent("resend"), method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "type": "signup",
            "email": email,
            "options": [
                "email_redirect_to": AppConfig.websiteURL.appendingPathComponent("auth/callback").absoluteString
            ]
        ])
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 204 else {
            logError("resendConfirmationEmail", data: data, response: response)
            throw BackendError.networkError("Could not resend confirmation email.")
        }
    }

    func continueAsGuest() async throws -> AppUser {
        // Supabase anonymous sign-in (requires anon sign-ins enabled in Auth settings)
        let url = config.authBaseURL.appendingPathComponent("signup")
        var req = baseRequest(url: url, method: "POST")
        // Empty body triggers anonymous sign-in in newer Supabase versions
        req.httpBody = try? JSONSerialization.data(withJSONObject: [:])
        let (data, response) = try await session.data(for: req)

        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            logError("continueAsGuest", data: data, response: response)
            // Fall back to a local guest account if Supabase anonymous auth fails
            throw BackendError.networkError("Anonymous sign-in unavailable; check Supabase Auth settings.")
        }
        let auth = try decoder.decode(SupabaseAuthResponse.self, from: data)
        persistSession(auth)
        var user = appUser(from: auth.user)
        user.isGuest = true
        user.name = "Guest"
        return user
    }

    // MARK: - OAuth (Google, etc.)

    /// Builds the Supabase `/auth/v1/authorize` URL for a given provider.
    /// AuthSessionStore opens this in ASWebAuthenticationSession.
    func oauthAuthorizeURL(provider: String, redirectTo: String) -> URL? {
        var comps = URLComponents(url: config.authBaseURL.appendingPathComponent("authorize"),
                                  resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            URLQueryItem(name: "provider",    value: provider),
            URLQueryItem(name: "redirect_to", value: redirectTo),
        ]
        return comps?.url
    }

    /// Completes an OAuth web flow by persisting the tokens returned in the
    /// callback URL fragment and fetching the resulting user.
    func completeOAuthSession(accessToken: String, refreshToken: String) async throws -> AppUser {
        persistSession(accessToken: accessToken, refreshToken: refreshToken)
        guard let user = try await currentUser() else {
            throw BackendError.notAuthenticated
        }
        print("[TrueCarry][Supabase] completeOAuthSession — \(user.email ?? "?")")
        return user
    }

    func signOut() async throws {
        if let token = accessToken {
            let url = config.authBaseURL.appendingPathComponent("logout")
            var req = baseRequest(url: url, method: "POST")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await session.data(for: req)
        }
        clearSession()
        print("[TrueCarry][Supabase] signOut")
    }

    // MARK: - Profile

    func saveUserProfile(_ profile: UserProfile) async throws {
        let body = profileToDict(profile)
        // on_conflict=user_id so merge-duplicates resolves on the unique user_id column
        try await upsert(table: "profiles", body: body, onConflict: "user_id")
    }

    func loadUserProfile(userId: UUID) async throws -> UserProfile? {
        let rows: [SupabaseProfileRow] = try await selectWhere(
            table: "profiles", column: "user_id", value: userId.uuidString)
        return rows.first?.toUserProfile()
    }

    // MARK: - Clubs

    func saveClub(_ club: UserClub) async throws {
        var body = try toDict(club)
        // Strip columns not yet in the DB schema (apply migration 016 to enable them).
        body.removeValue(forKey: "loft_degrees")
        body.removeValue(forKey: "brand")
        try await upsert(table: "clubs", body: body)
    }

    func deleteClub(clubId: UUID, userId: UUID) async throws {
        try await deleteRow(table: "clubs", id: clubId)
    }

    func loadClubs(userId: UUID) async throws -> [UserClub] {
        let rows: [UserClub] = try await selectWhere(
            table: "clubs", column: "user_id", value: userId.uuidString)
        return rows.sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - Shots

    func saveShot(_ shot: SavedShot) async throws {
        try await upsert(
            table: "shots",
            body: try payloadRowBody(id: shot.id, userId: shot.userId, payload: shot, dateColumn: "timestamp", date: shot.timestamp)
        )
        // Product telemetry (fire-and-forget) — powers most-used-club / usage dashboards.
        await logAnalyticsEvent("shot_saved", properties: [
            "club": shot.clubName ?? "",
            "source": shot.source.rawValue,
            "carry": shot.metrics.carryYards,
        ], sessionId: shot.sessionId)
    }

    func loadShots(userId: UUID) async throws -> [SavedShot] {
        let rows: [SupabasePayloadRow<SavedShot>] = try await selectWhere(
            table: "shots", column: "user_id", value: userId.uuidString)
        return rows
            .map { row in
                var shot = row.payload
                if let id = UUID(uuidString: row.id) { shot.id = id }
                if let uid = UUID(uuidString: row.userId) { shot.userId = uid }
                if let timestamp = row.parsedTimestamp { shot.timestamp = timestamp }
                return shot
            }
            .sorted { $0.timestamp > $1.timestamp }
    }

    func deleteShot(shotId: UUID, userId: UUID) async throws {
        try await deleteRow(table: "shots", id: shotId)
    }

    // MARK: - Replay frames (Supabase Storage)
    // Requires a private bucket "shot-frames" with RLS allowing a user to
    // read/write objects under a path that starts with their own user id.

    private static let framesBucket = "shot-frames"

    private func frameObjectURL(userId: UUID, shotId: UUID, index: Int) -> URL {
        // Lowercase the UUIDs: the shot-frames RLS policy compares the path's first folder against
        // auth.uid() as TEXT (case-sensitive), and auth.uid() is lowercase — but Swift's
        // UUID.uuidString is uppercase, which would make every upload fail RLS.
        config.storageBaseURL
            .appendingPathComponent("object")
            .appendingPathComponent(Self.framesBucket)
            .appendingPathComponent(userId.uuidString.lowercased())
            .appendingPathComponent(shotId.uuidString.lowercased())
            .appendingPathComponent("frame_\(String(format: "%03d", index)).png")
    }

    func uploadShotFrames(userId: UUID, shotId: UUID, frames: [Data]) async throws {
        for (idx, data) in frames.enumerated() {
            var req = authorizedRequest(url: frameObjectURL(userId: userId, shotId: shotId, index: idx), method: "POST")
            req.setValue("image/png", forHTTPHeaderField: "Content-Type")
            req.setValue("true", forHTTPHeaderField: "x-upsert")   // overwrite if it exists
            req.httpBody = data
            let (respData, response) = try await performAuthorizedRequest(req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 || status == 201 else {
                logError("uploadFrame", data: respData, response: response)
                throw BackendError.saveFailed("shot-frames")
            }
        }
    }

    func downloadShotFrames(userId: UUID, shotId: UUID, count: Int) async throws -> [Data] {
        var out: [Data] = []
        for idx in 0..<max(0, count) {
            let req = authorizedRequest(url: frameObjectURL(userId: userId, shotId: shotId, index: idx))
            let (data, response) = try await performAuthorizedRequest(req)
            guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { break }
            out.append(data)
        }
        return out
    }

    // Per-shot composite (single JPEG) — stored in the same bucket alongside (former) frames.
    private func compositeObjectURL(userId: UUID, shotId: UUID) -> URL {
        config.storageBaseURL
            .appendingPathComponent("object")
            .appendingPathComponent(Self.framesBucket)
            .appendingPathComponent(userId.uuidString.lowercased())
            .appendingPathComponent(shotId.uuidString.lowercased())
            .appendingPathComponent("composite.jpg")
    }

    func uploadShotComposite(userId: UUID, shotId: UUID, jpeg: Data) async throws {
        var req = authorizedRequest(url: compositeObjectURL(userId: userId, shotId: shotId), method: "POST")
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        req.setValue("true", forHTTPHeaderField: "x-upsert")
        req.httpBody = jpeg
        let (respData, response) = try await performAuthorizedRequest(req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 201 else {
            logError("uploadComposite", data: respData, response: response)
            throw BackendError.saveFailed("shot-frames")
        }
    }

    func downloadShotComposite(userId: UUID, shotId: UUID) async throws -> Data? {
        let req = authorizedRequest(url: compositeObjectURL(userId: userId, shotId: shotId))
        let (data, response) = try await performAuthorizedRequest(req)
        guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return nil }
        return data
    }

    // MARK: - Range Sessions

    func saveRangeSession(_ session: PracticeSession) async throws {
        try await upsert(
            table: "range_sessions",
            body: try payloadRowBody(id: session.id, userId: session.userId, payload: session, dateColumn: "started_at", date: session.startedAt)
        )
    }

    func deleteRangeSession(sessionId: UUID, userId: UUID) async throws {
        try await deleteRow(table: "range_sessions", id: sessionId)
        await Self.postDataChanged()
    }

    func loadRangeSessions(userId: UUID) async throws -> [PracticeSession] {
        let rows: [SupabasePayloadRow<PracticeSession>] = try await selectWhere(
            table: "range_sessions", column: "user_id", value: userId.uuidString)
        return rows
            .map { row in
                var rangeSession = row.payload
                if let id = UUID(uuidString: row.id) { rangeSession.id = id }
                if let uid = UUID(uuidString: row.userId) { rangeSession.userId = uid }
                if let startedAt = row.parsedStartedAt { rangeSession.startedAt = startedAt }
                return rangeSession
            }
            .filter { !$0.shotIds.isEmpty }
            .sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: - Sim Sessions

    func saveSimSession(_ session: SimSession) async throws {
        try await upsert(
            table: "sim_sessions",
            body: try payloadRowBody(id: session.id, userId: session.userId, payload: session, dateColumn: "started_at", date: session.startedAt)
        )
    }

    func deleteSimSession(sessionId: UUID, userId: UUID) async throws {
        try await deleteRow(table: "sim_sessions", id: sessionId)
        await Self.postDataChanged()
    }

    func loadSimSessions(userId: UUID) async throws -> [SimSession] {
        let rows: [SupabasePayloadRow<SimSession>] = try await selectWhere(
            table: "sim_sessions", column: "user_id", value: userId.uuidString)
        return rows
            .map { row in
                var simSession = row.payload
                if let id = UUID(uuidString: row.id) { simSession.id = id }
                if let uid = UUID(uuidString: row.userId) { simSession.userId = uid }
                if let startedAt = row.parsedStartedAt { simSession.startedAt = startedAt }
                return simSession
            }
            .sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: - Course Rounds

    func saveRound(_ round: CourseRound) async throws {
        try await upsert(
            table: "course_rounds",
            body: try payloadRowBody(id: round.id, userId: round.userId, payload: round, dateColumn: "started_at", date: round.startedAt)
        )
        // Telemetry (fire-and-forget) — course usage / rounds-played dashboards.
        await logAnalyticsEvent("round_completed", properties: [
            "course": round.courseName,
            "score": round.scoreSummary.totalScore,
            "to_par": round.scoreSummary.totalScore - round.scoreSummary.totalPar,
        ], sessionId: nil)
    }

    func deleteCourseRound(roundId: UUID, userId: UUID) async throws {
        try await deleteRow(table: "course_rounds", id: roundId)
        await Self.postDataChanged()
    }

    /// Deletions invalidate every derived aggregate (feed "Your Week", insights, history).
    @MainActor private static func postDataChanged() {
        NotificationCenter.default.post(name: .tcDataChanged, object: nil)
    }

    func loadCourseRounds(userId: UUID) async throws -> [CourseRound] {
        let rows: [SupabasePayloadRow<CourseRound>] = try await selectWhere(
            table: "course_rounds", column: "user_id", value: userId.uuidString)
        return rows
            .map { row in
                var round = row.payload
                if let id = UUID(uuidString: row.id) { round.id = id }
                if let uid = UUID(uuidString: row.userId) { round.userId = uid }
                if let startedAt = row.parsedStartedAt { round.startedAt = startedAt }
                return round
            }
            .filter { round in
                // Only show finished rounds, or rounds that have at least one shot or score recorded.
                round.endedAt != nil
                    || !round.shotIds.isEmpty
                    || round.holes.contains(where: { $0.score != nil })
            }
            .sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: - Shared Course Geometry

    func saveCourseGeometry(_ course: GolfCourse) async throws {
        guard course.hasTrustedGeometry else { return }
        let metadata = course.geometryMetadata ?? CourseGeometryMetadata(
            state: .accepted,
            confidence: 1.0,
            source: course.source.rawValue,
            schemaVersion: 1,
            generatedBy: "ios",
            validationErrors: [],
            imagerySource: nil,
            updatedAt: Date()
        )
        var body: [String: Any] = [
            "course_id": course.id,
            "course_name": course.name,
            "city": course.city,
            "state": course.state,
            "source": metadata.source,
            "geometry_state": metadata.state.rawValue,
            "schema_version": metadata.schemaVersion,
            "validation_errors": metadata.validationErrors,
            "payload": try toDict(course),
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
        // Only ever set the flag forward. Omitting the key on unverified saves means an upsert
        // can't downgrade a row that a previous (scorecard-merged) play already verified.
        if course.scorecardVerified == true { body["scorecard_verified"] = true }
        if let confidence = metadata.confidence { body["confidence"] = confidence }
        if let generatedBy = metadata.generatedBy { body["generated_by"] = generatedBy }
        if let imagerySource = metadata.imagerySource { body["imagery_source"] = imagerySource }
        if let lat = course.latitude { body["latitude"] = lat }
        if let lon = course.longitude { body["longitude"] = lon }
        if let user = try? await currentUser() {
            body["submitted_by"] = user.id.uuidString
        }
        try await upsert(table: "course_geometries", body: body)
    }

    func loadCourseGeometry(courseId: String) async throws -> GolfCourse? {
        let rows: [SupabaseCourseGeometryRow] = try await selectWhere(
            table: "course_geometries", column: "course_id", value: courseId)
        return rows.map { $0.toGolfCourse() }.first(where: { $0.hasTrustedGeometry })
    }

    /// Fuzzy fallback: bounding-box query on accepted geometry, then best name + distance match.
    /// Absorbs id drift between Apple Maps and the bulk OSM pre-bake (which can't always reproduce
    /// the exact MapKit synthetic id).
    func findCourseGeometryNear(name: String, coordinate: CLLocationCoordinate2D?) async throws -> GolfCourse? {
        guard let coordinate else { return nil }
        // ~0.12° ≈ 13 km at mid-latitudes — generous enough to absorb coordinate rounding drift.
        let delta = 0.12
        var components = URLComponents(url: restURL("course_geometries"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "geometry_state", value: "eq.accepted"),
            URLQueryItem(name: "latitude",  value: "gte.\(coordinate.latitude - delta)"),
            URLQueryItem(name: "latitude",  value: "lte.\(coordinate.latitude + delta)"),
            URLQueryItem(name: "longitude", value: "gte.\(coordinate.longitude - delta)"),
            URLQueryItem(name: "longitude", value: "lte.\(coordinate.longitude + delta)"),
            URLQueryItem(name: "limit", value: "40")
        ]
        let req = authorizedRequest(url: components.url!)
        let (data, response) = try await performAuthorizedRequest(req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            logError("select:course_geometries(near)", data: data, response: response)
            throw BackendError.loadFailed("course_geometries")
        }
        let rows = try decoder.decode([SupabaseCourseGeometryRow].self, from: data)
        let candidates = rows.map { $0.toGolfCourse() }.filter { $0.hasTrustedGeometry }
        if let match = Self.bestGeometryMatch(candidates, name: name, coordinate: coordinate) {
            return match
        }

        // Fallback: courses saved before lat/lon columns were backfilled have NULL coords and won't
        // appear in the bounding-box query above. Search by name instead so they're still found.
        return try await findCourseGeometryByName(name, coordinate: coordinate)
    }

    private func findCourseGeometryByName(_ name: String, coordinate: CLLocationCoordinate2D) async throws -> GolfCourse? {
        // Extract the most distinctive token (longest word, ignoring common golf terms).
        let ignored: Set<String> = ["the", "golf", "club", "course", "country", "links"]
        let token = name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !ignored.contains($0) }
            .max(by: { $0.count < $1.count }) ?? name
        var components = URLComponents(url: restURL("course_geometries"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "geometry_state", value: "eq.accepted"),
            URLQueryItem(name: "course_name", value: "ilike.*\(token)*"),
            URLQueryItem(name: "limit", value: "20")
        ]
        let req = authorizedRequest(url: components.url!)
        let (data, response) = try await performAuthorizedRequest(req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let rows = try decoder.decode([SupabaseCourseGeometryRow].self, from: data)
        let candidates = rows.map { $0.toGolfCourse() }.filter { $0.hasTrustedGeometry }
        return Self.bestGeometryMatch(candidates, name: name, coordinate: coordinate)
    }

    /// Picks the closest trusted candidate whose name overlaps the query, falling back to the
    /// nearest by distance. Mirrors CourseDataAggregator.bestMatch so client + shared agree.
    static func bestGeometryMatch(_ candidates: [GolfCourse],
                                  name: String,
                                  coordinate: CLLocationCoordinate2D) -> GolfCourse? {
        guard !candidates.isEmpty else { return nil }
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let scored = candidates.map { c -> (GolfCourse, Double) in
            var penalty = 0.0
            if !namesOverlap(c.name, name) { penalty += 3_000 }
            let dist: Double = {
                guard let lat = c.latitude, let lon = c.longitude else { return 10_000 }
                return origin.distance(from: CLLocation(latitude: lat, longitude: lon))
            }()
            return (c, dist + penalty)
        }
        return scored.min(by: { $0.1 < $1.1 })?.0
    }

    private static func namesOverlap(_ a: String, _ b: String) -> Bool {
        let ignored: Set<String> = ["the", "golf", "club", "course", "country", "links"]
        func tokens(_ s: String) -> Set<String> {
            Set(s.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 && !ignored.contains($0) })
        }
        return !tokens(a).isDisjoint(with: tokens(b))
    }

    func requestCourseGeometryBackfill(_ course: GolfCourse, reason: String = "missing_geometry") async throws {
        var body: [String: Any] = [
            "course_id": course.id,
            "course_name": course.name,
            "city": course.city,
            "state": course.state,
            "country": course.country,
            "reason": reason,
            "status": "queued",
            "last_requested_at": ISO8601DateFormatter().string(from: Date()),
            "scorecard_payload": try toDict(course)
        ]
        if let lat = course.latitude { body["latitude"] = lat }
        if let lon = course.longitude { body["longitude"] = lon }
        if let tee = course.teeBoxes.first {
            body["selected_tee_name"] = tee.name
            body["selected_tee_yards"] = tee.totalYards
        }

        var components = URLComponents(url: restURL("geometry_backfill_requests"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "on_conflict", value: "course_id")]
        var req = authorizedRequest(url: components.url!, method: "POST")
        req.setValue("return=minimal,resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await performAuthorizedRequest(req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 201 || status == 204 else {
            logError("upsert:geometry_backfill_requests", data: data, response: response)
            throw BackendError.saveFailed("geometry_backfill_requests")
        }
    }

    /// In-app "Report course issue" — files a user report into course_data_requests
    /// (RLS: insert-only for the signed-in user; the course tools drain the queue
    /// with the service role).
    func reportCourseIssue(courseId: String,
                           courseName: String,
                           issue: String,
                           holeNumber: Int?,
                           userId: UUID) async throws {
        var payload: [String: Any] = [
            "issue": issue,
            "reported_at": ISO8601DateFormatter().string(from: Date())
        ]
        if let holeNumber { payload["hole"] = holeNumber }
        var body: [String: Any] = [
            "course_name": courseName,
            "request_type": "user_report",
            "status": "queued",
            "submitted_by": userId.uuidString,
            "notes": issue,
            "raw_payload": payload
        ]
        // course_id is a uuid column; catalog ids are UUIDs, everything else
        // (MapKit stubs, GolfCourseAPI ids) travels in external_course_id.
        if courseId.count == 36, courseId.filter({ $0 == "-" }).count == 4 {
            body["course_id"] = courseId
        } else {
            body["external_course_id"] = courseId
        }
        var req = authorizedRequest(url: restURL("course_data_requests"), method: "POST")
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await performAuthorizedRequest(req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 201 || status == 204 else {
            logError("insert:course_data_requests", data: data, response: response)
            throw BackendError.saveFailed("course_data_requests")
        }
    }

    // MARK: - Feed

    func saveFeedPost(_ post: FeedPost) async throws {
        // feed_posts stores the post body in a `payload` JSONB column.
        let body: [String: Any] = [
            "id": post.id.uuidString,
            "user_id": post.userId.uuidString,
            "visibility": "friends",
            "timestamp": ISO8601DateFormatter().string(from: post.timestamp),
            "payload": try toDict(post)
        ]
        try await upsert(table: "feed_posts", body: body)
    }

    func deleteFeedPost(postId: UUID, userId: UUID) async throws {
        try await deleteRow(table: "feed_posts", id: postId)
    }

    func loadFeed(userId: UUID) async throws -> [FeedPost] {
        // RLS scopes feed_posts to the caller + their friends, so select all and sort.
        var components = URLComponents(url: restURL("feed_posts"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "order", value: "timestamp.desc"),
            URLQueryItem(name: "limit", value: "100")
        ]
        let req = authorizedRequest(url: components.url!)
        let (data, response) = try await performAuthorizedRequest(req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            logError("select:feed_posts", data: data, response: response)
            throw BackendError.loadFailed("feed_posts")
        }
        let rows = try decoder.decode([SupabaseFeedPostRow].self, from: data)
        return rows.compactMap { $0.toFeedPost() }.sorted { $0.timestamp > $1.timestamp }
    }

    func loadUserPosts(userId: UUID) async throws -> [FeedPost] {
        // RLS on feed_posts enforces visibility (public + friends-of-caller), so we
        // just filter to this author. Returns only what the caller is allowed to see.
        var components = URLComponents(url: restURL("feed_posts"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userId.uuidString)"),
            URLQueryItem(name: "order", value: "timestamp.desc"),
            URLQueryItem(name: "limit", value: "200")
        ]
        let req = authorizedRequest(url: components.url!)
        let (data, response) = try await performAuthorizedRequest(req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            logError("select:feed_posts:user", data: data, response: response)
            throw BackendError.loadFailed("feed_posts")
        }
        let rows = try decoder.decode([SupabaseFeedPostRow].self, from: data)
        return rows.compactMap { $0.toFeedPost() }.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Follow graph + privacy

    func followUser(target: UUID) async throws -> String {
        struct StatusRow: Decodable { let status: String }
        let rows: [StatusRow] = try await rpc("follow_user", body: ["target": target.uuidString])
        return rows.first?.status ?? "accepted"
    }

    func unfollowUser(target: UUID) async throws {
        try await rpcVoid("unfollow_user", body: ["target": target.uuidString])
    }

    func profileSocial(target: UUID) async throws -> ProfileSocial {
        let rows: [ProfileSocial] = try await rpc("profile_social", body: ["target": target.uuidString])
        return rows.first ?? .empty
    }

    func setProfilePrivacy(_ isPrivate: Bool) async throws {
        try await rpcVoid("set_profile_privacy", body: ["is_priv": isPrivate])
    }

    func loadIncomingFollowRequests() async throws -> [IncomingFollowRequest] {
        try await rpc("incoming_follow_requests", body: [:])
    }

    func respondFollowRequest(follower: UUID, accept: Bool) async throws {
        try await rpcVoid("respond_follow_request", body: ["follower": follower.uuidString, "accept": accept])
    }

    func loadFollowList(target: UUID, followers: Bool) async throws -> [FollowListEntry] {
        try await rpc("follow_list", body: ["target": target.uuidString, "want_followers": followers])
    }

    func loadCoachNotes() async throws -> [CoachNote] {
        // RLS scopes ai_coach_notes to the caller, so no user filter is needed here.
        var components = URLComponents(url: restURL("ai_coach_notes"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "100")
        ]
        let req = authorizedRequest(url: components.url!)
        let (data, response) = try await performAuthorizedRequest(req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            logError("select:ai_coach_notes", data: data, response: response)
            throw BackendError.loadFailed("ai_coach_notes")
        }
        return try decoder.decode([CoachNote].self, from: data)
    }

    func loadFeedPage(userId: UUID, cursor: Date?, limit: Int) async throws -> FeedPage {
        var queryItems = [
            URLQueryItem(name: "order", value: "timestamp.desc"),
            URLQueryItem(name: "limit", value: "\(max(1, limit + 1))")
        ]
        if let cursor {
            queryItems.append(URLQueryItem(name: "timestamp", value: "lt.\(ISO8601DateFormatter().string(from: cursor))"))
        }

        var components = URLComponents(url: restURL("feed_posts"), resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems
        let req = authorizedRequest(url: components.url!)
        let (data, response) = try await performAuthorizedRequest(req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            logError("select:feed_posts:page", data: data, response: response)
            throw BackendError.loadFailed("feed_posts")
        }

        let rows = try decoder.decode([SupabaseFeedPostRow].self, from: data)
        let decoded = rows.compactMap { $0.toFeedPost() }.sorted { $0.timestamp > $1.timestamp }
        let pagePosts = Array(decoded.prefix(limit))
        return FeedPage(posts: pagePosts, nextCursor: decoded.count > limit ? pagePosts.last?.timestamp : nil, hasMore: decoded.count > limit)
    }

    func loadEngagement(postIds: [UUID], userId: UUID) async throws -> FeedEngagementSummary {
        guard !postIds.isEmpty else { return FeedEngagementSummary() }
        let idList = postIds.map(\.uuidString).joined(separator: ",")

        var reactionsComponents = URLComponents(url: restURL("feed_reactions"), resolvingAgainstBaseURL: false)!
        reactionsComponents.queryItems = [
            URLQueryItem(name: "post_id", value: "in.(\(idList))"),
            URLQueryItem(name: "emoji", value: "eq.gimme")
        ]
        let reactionsRequest = authorizedRequest(url: reactionsComponents.url!)
        let (reactionData, reactionResponse) = try await performAuthorizedRequest(reactionsRequest)
        guard (reactionResponse as? HTTPURLResponse)?.statusCode == 200 else {
            logError("select:feed_reactions:batch", data: reactionData, response: reactionResponse)
            throw BackendError.loadFailed("feed_reactions")
        }

        var summary = FeedEngagementSummary()
        let reactionRows = try decoder.decode([SupabaseReactionRow].self, from: reactionData)
        for row in reactionRows {
            guard let postId = UUID(uuidString: row.postId), let reactingUserId = UUID(uuidString: row.userId) else { continue }
            summary.gimmeCounts[postId, default: 0] += 1
            if reactingUserId == userId {
                summary.gimmedByMe.insert(postId)
            }
        }

        var commentsComponents = URLComponents(url: restURL("feed_comments"), resolvingAgainstBaseURL: false)!
        commentsComponents.queryItems = [
            URLQueryItem(name: "post_id", value: "in.(\(idList))"),
            URLQueryItem(name: "select", value: "id,post_id")
        ]
        let commentsRequest = authorizedRequest(url: commentsComponents.url!)
        let (commentData, commentResponse) = try await performAuthorizedRequest(commentsRequest)
        guard (commentResponse as? HTTPURLResponse)?.statusCode == 200 else {
            logError("select:feed_comments:batch", data: commentData, response: commentResponse)
            throw BackendError.loadFailed("feed_comments")
        }

        let commentRows = try decoder.decode([SupabaseCommentCountRow].self, from: commentData)
        for row in commentRows {
            guard let postId = UUID(uuidString: row.postId) else { continue }
            summary.commentCounts[postId, default: 0] += 1
        }
        return summary
    }

    // MARK: - Gimmes (feed reactions)

    func loadGimmes() async throws -> [FeedReaction] {
        // RLS scopes reactions to posts the caller can see.
        var components = URLComponents(url: restURL("feed_reactions"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "emoji", value: "eq.gimme")]
        let req = authorizedRequest(url: components.url!)
        let (data, response) = try await performAuthorizedRequest(req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            logError("select:feed_reactions", data: data, response: response)
            throw BackendError.loadFailed("feed_reactions")
        }
        let rows = try decoder.decode([SupabaseReactionRow].self, from: data)
        return rows.compactMap { row in
            guard let pid = UUID(uuidString: row.postId), let uid = UUID(uuidString: row.userId) else { return nil }
            return FeedReaction(id: UUID(uuidString: row.id) ?? UUID(), postId: pid, userId: uid, emoji: row.emoji)
        }
    }

    func addGimme(postId: UUID, userId: UUID) async throws {
        let body: [String: Any] = [
            "post_id": postId.uuidString,
            "user_id": userId.uuidString,
            "emoji": "gimme"
        ]
        var components = URLComponents(url: restURL("feed_reactions"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "on_conflict", value: "post_id,user_id")]
        var req = authorizedRequest(url: components.url!, method: "POST")
        req.setValue("return=minimal,resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await performAuthorizedRequest(req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 201 || status == 204 else {
            logError("addGimme", data: data, response: response)
            throw BackendError.saveFailed("feed_reactions")
        }
    }

    func removeGimme(postId: UUID, userId: UUID) async throws {
        var components = URLComponents(url: restURL("feed_reactions"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "post_id", value: "eq.\(postId.uuidString)"),
            URLQueryItem(name: "user_id", value: "eq.\(userId.uuidString)"),
            URLQueryItem(name: "emoji", value: "eq.gimme")
        ]
        var req = authorizedRequest(url: components.url!, method: "DELETE")
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        _ = try? await performAuthorizedRequest(req)
    }

    // MARK: - Comments

    func loadComments(postId: UUID) async throws -> [FeedComment] {
        var components = URLComponents(url: restURL("feed_comments"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "post_id", value: "eq.\(postId.uuidString)"),
            URLQueryItem(name: "order", value: "created_at.asc")
        ]
        let req = authorizedRequest(url: components.url!)
        let (data, response) = try await performAuthorizedRequest(req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            logError("select:feed_comments", data: data, response: response)
            throw BackendError.loadFailed("feed_comments")
        }
        let rows = try decoder.decode([SupabaseCommentRow].self, from: data)
        return rows.compactMap { $0.toFeedComment() }
    }

    func addComment(_ comment: FeedComment) async throws {
        let body: [String: Any] = [
            "id": comment.id.uuidString,
            "post_id": comment.postId.uuidString,
            "user_id": comment.userId.uuidString,
            "author_name": comment.authorName,
            "body": comment.body
        ]
        try await upsert(table: "feed_comments", body: body)
    }

    // MARK: - Friends / contacts

    func searchUsers(query: String) async throws -> [FriendProfile] {
        let rows: [SupabaseUserSearchRow] = try await rpc("search_users", body: ["q": query])
        return rows.compactMap { $0.toFriendProfile() }
    }

    func golfersAtHomeCourse() async throws -> [FriendProfile] {
        let rows: [SupabaseUserSearchRow] = try await rpc("golfers_at_home_course", body: [:])
        return rows.compactMap { $0.toFriendProfile() }
    }

    func sendFriendRequest(fromUserId: UUID, toUserId: UUID) async throws {
        let body: [String: Any] = [
            "from_user_id": fromUserId.uuidString,
            "to_user_id": toUserId.uuidString,
            "status": "pending"
        ]
        try await upsert(table: "friend_requests", body: body)
    }

    func loadIncomingRequests() async throws -> [IncomingFriendRequest] {
        let rows: [SupabaseIncomingRequestRow] = try await rpc("list_incoming_requests", body: [:])
        return rows.compactMap { $0.toIncomingRequest() }
    }

    func acceptFriendRequest(requestId: UUID) async throws {
        try await rpcVoid("accept_friend_request", body: ["req_id": requestId.uuidString])
    }

    func declineFriendRequest(requestId: UUID) async throws {
        let body: [String: Any] = ["status": "declined", "resolved_at": ISO8601DateFormatter().string(from: Date())]
        var components = URLComponents(url: restURL("friend_requests"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(requestId.uuidString)")]
        var req = authorizedRequest(url: components.url!, method: "PATCH")
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try? await performAuthorizedRequest(req)
    }

    func loadFriends() async throws -> [FriendProfile] {
        let rows: [SupabaseUserSearchRow] = try await rpc("list_friends", body: [:])
        return rows.compactMap { $0.toFriendProfile() }
    }

    // MARK: - Round attestation

    func requestRoundAttestation(round: CourseRound, requesterId: UUID, requesterName: String, attesterId: UUID) async throws {
        var body: [String: Any] = [
            "id": UUID().uuidString,
            "round_id": round.id.uuidString,
            "requester_id": requesterId.uuidString,
            "requester_name": requesterName,
            "attester_id": attesterId.uuidString,
            "course_name": round.courseName,
            "round_date": ISO8601DateFormatter().string(from: round.startedAt),
            "status": "pending"
        ]
        if round.scoreSummary.totalScore > 0 { body["score"] = round.scoreSummary.totalScore }
        if round.scoreSummary.totalPar > 0 {
            body["to_par"] = round.scoreSummary.totalScore - round.scoreSummary.totalPar
        }
        try await upsert(table: "round_attestations", body: body)
    }

    func loadIncomingAttestations(userId: UUID) async throws -> [IncomingAttestation] {
        // RLS lets the attester read rows addressed to them; keep only the still-pending ones.
        let rows: [IncomingAttestation] = try await selectWhere(
            table: "round_attestations", column: "attester_id", value: userId.uuidString)
        return rows.filter { $0.status == "pending" }.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    func loadSentAttestations(userId: UUID) async throws -> [SentAttestation] {
        // RLS lets the requester read rows they created, so they can see status.
        let rows: [SentAttestation] = try await selectWhere(
            table: "round_attestations", column: "requester_id", value: userId.uuidString)
        return rows.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    // MARK: - Camera-verified weekly challenges

    func submitChallengeEntry(carryYards: Double, ballSpeedMph: Double?, clubName: String, shotId: UUID?) async throws {
        // Goes through submit_challenge_entry() so the server enforces sanity
        // bounds and the keep-best-per-week upsert.
        var body: [String: Any] = [
            "p_carry_yards": carryYards,
            "p_club_name": clubName,
        ]
        if let ballSpeedMph { body["p_ball_speed_mph"] = ballSpeedMph }
        if let shotId { body["p_shot_id"] = shotId.uuidString }
        try await rpcVoid("submit_challenge_entry", body: body)
    }

    func loadChallengeLeaderboard() async throws -> [ChallengeLeaderboardEntry] {
        try await rpc("weekly_challenge_leaderboard", body: [:])
    }

    func loadHomeCourseLeaderboard(course: String) async throws -> [HomeCourseLeaderboardEntry] {
        let trimmed = course.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return try await rpc("home_course_leaderboard", body: ["p_course": trimmed, "p_limit": 25])
    }

    // MARK: - Course ratings & bookmarks

    /// Ratings/bookmarks are keyed on the base course name so all tees share one.
    private func baseCourseName(_ s: String) -> String {
        (s.components(separatedBy: " ~ ").first ?? s).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func rateCourse(userId: UUID, course: String, rating: Int, review: String?) async throws {
        var body: [String: Any] = [
            "user_id": userId.uuidString,
            "course_name": baseCourseName(course),
            "rating": max(1, min(5, rating)),
            "updated_at": ISO8601DateFormatter().string(from: Date()),
        ]
        if let review, !review.isEmpty { body["review"] = review }
        try await upsert(table: "course_ratings", body: body, onConflict: "user_id,course_name")
    }

    func courseRatingSummary(course: String) async throws -> CourseRatingSummary {
        let rows: [CourseRatingSummary] = try await rpc("course_rating_summary", body: ["p_course": course])
        return rows.first ?? .empty
    }

    func addCourseBookmark(userId: UUID, course: String) async throws {
        let body: [String: Any] = ["user_id": userId.uuidString, "course_name": baseCourseName(course)]
        try await upsert(table: "course_bookmarks", body: body, onConflict: "user_id,course_name")
    }

    func removeCourseBookmark(userId: UUID, course: String) async throws {
        var components = URLComponents(url: restURL("course_bookmarks"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userId.uuidString)"),
            URLQueryItem(name: "course_name", value: "eq.\(baseCourseName(course))"),
        ]
        var req = authorizedRequest(url: components.url!, method: "DELETE")
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        _ = try? await performAuthorizedRequest(req)
    }

    func loadCourseBookmarks(userId: UUID) async throws -> [CourseBookmark] {
        var components = URLComponents(url: restURL("course_bookmarks"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,course_name"),
            URLQueryItem(name: "order", value: "created_at.desc"),
        ]
        let req = authorizedRequest(url: components.url!)
        let (data, response) = try await performAuthorizedRequest(req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            logError("select:course_bookmarks", data: data, response: response)
            throw BackendError.loadFailed("course_bookmarks")
        }
        return try decoder.decode([CourseBookmark].self, from: data)
    }

    func respondToAttestation(id: UUID, accept: Bool) async throws {
        // Goes through respond_to_attestation() so the responder's display name is
        // stamped onto the row (from their profile) for the requester's "Verified by" UI.
        try await rpcVoid("respond_to_attestation", body: [
            "p_id": id.uuidString,
            "p_accept": accept,
        ])
    }

    func requestRoundAttestationLink(round: CourseRound, requesterId: UUID, requesterName: String) async throws -> String {
        // attester_id is left out entirely (nullable since migration 033) — the recipient isn't
        // a known user yet. share_token is generated client-side so we can hand back the URL
        // immediately without a second round-trip to read the inserted row back.
        let token = UUID()
        var body: [String: Any] = [
            "id": UUID().uuidString,
            "round_id": round.id.uuidString,
            "requester_id": requesterId.uuidString,
            "requester_name": requesterName,
            "share_token": token.uuidString,
            "course_name": round.courseName,
            "round_date": ISO8601DateFormatter().string(from: round.startedAt),
            "status": "pending"
        ]
        if round.scoreSummary.totalScore > 0 { body["score"] = round.scoreSummary.totalScore }
        if round.scoreSummary.totalPar > 0 {
            body["to_par"] = round.scoreSummary.totalScore - round.scoreSummary.totalPar
        }
        try await upsert(table: "round_attestations", body: body)
        return token.uuidString
    }

    func loadFeedNotifications() async throws -> [FeedNotification] {
        let rows: [SupabaseFeedNotificationRow] = try await rpc("list_feed_notifications", body: [:])
        return rows.compactMap { $0.toNotification() }
    }

    func createInviteCode(userId: UUID) async throws -> String {
        // 12 hex chars (~48 bits) — invite codes gate friend creation via the
        // public redeem_invite RPC, so they must not be feasibly guessable.
        let code = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)).uppercased()
        try await upsert(table: "invite_codes", body: ["code": code, "user_id": userId.uuidString])
        return code
    }

    func redeemInvite(code: String) async throws {
        try await rpcVoid("redeem_invite", body: ["p_code": code])
    }

    /// Redeems an invite and returns the Pro days granted to the caller (0 if the
    /// reward didn't apply, e.g. the user was already referred).
    func redeemInviteReward(code: String) async throws -> Int {
        let url = config.rpcBaseURL.appendingPathComponent("redeem_invite")
        var req = authorizedRequest(url: url, method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["p_code": code])
        let (data, response) = try await performAuthorizedRequest(req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 201 || status == 204 else {
            logError("rpc:redeem_invite", data: data, response: response)
            throw BackendError.saveFailed("rpc:redeem_invite")
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           (obj["granted"] as? Bool) == true,
           let days = obj["reward_days"] as? Int {
            return days
        }
        return 0
    }

    // MARK: - Entitlement

    func loadEntitlement(userId: UUID) async throws -> UserEntitlement {
        let rows: [SupabaseEntitlementRow] = try await selectWhere(
            table: "user_entitlements", column: "user_id", value: userId.uuidString)
        let ent = rows.first?.toUserEntitlement() ?? UserEntitlement.freeTier(userId: userId)
        print("[TrueCarry][Supabase] entitlement — tier=\(ent.tier.rawValue) status=\(ent.paymentStatus.rawValue)")
        return ent
    }

    func loadUsageCounter(userId: UUID, date: String) async throws -> UsageCounter? {
        var components = URLComponents(url: restURL("usage_counters"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userId.uuidString)"),
            URLQueryItem(name: "date", value: "eq.\(date)")
        ]
        let req = authorizedRequest(url: components.url!)
        let (data, response) = try await performAuthorizedRequest(req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let rows = try decoder.decode([UsageCounter].self, from: data)
        return rows.first
    }

    func incrementUsage(userId: UUID, action: EntitlementAction) async throws {
        let url = config.rpcBaseURL.appendingPathComponent("increment_usage")
        var req = authorizedRequest(url: url, method: "POST")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "p_user_id": userId.uuidString,
            "p_action": action.rpcKey
        ])
        let (data, response) = try await performAuthorizedRequest(req)
        if (response as? HTTPURLResponse)?.statusCode != 200 {
            logError("incrementUsage", data: data, response: response)
        }
    }

    /// Registers (or refreshes) this device and enforces the per-account device
    /// cap via the register_device RPC. Returns true if the device is allowed,
    /// false if the account is already at its limit. Fails OPEN (returns true)
    /// on any transient/RPC error so a legitimate user is never locked out.
    func registerDevice(token: String, name: String, platform: String, appVersion: String) async -> Bool {
        let url = config.rpcBaseURL.appendingPathComponent("register_device")
        var req = authorizedRequest(url: url, method: "POST")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "p_device_token": token,
            "p_device_name":  name,
            "p_platform":     platform,
            "p_app_version":  appVersion,
        ])
        do {
            let (data, response) = try await performAuthorizedRequest(req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                logError("registerDevice", data: data, response: response)
                return true   // fail open
            }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let allowed = obj["allowed"] as? Bool {
                return allowed
            }
            return true       // unexpected shape → fail open
        } catch {
            return true       // network error → fail open
        }
    }

    // MARK: - REST helpers

    private func restURL(_ table: String) -> URL {
        config.restBaseURL.appendingPathComponent(table)
    }

    private func baseRequest(url: URL, method: String = "GET") -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        return req
    }

    private func authorizedRequest(url: URL, method: String = "GET") -> URLRequest {
        var req = baseRequest(url: url, method: method)
        if let token = accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    /// exp claim of a JWT (unix seconds), or nil when unreadable.
    private static func tokenExpiry(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = obj["exp"] as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    private func performAuthorizedRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var req = request
        if req.value(forHTTPHeaderField: "Authorization") == nil, refreshToken != nil {
            try? await refreshSession()
        }
        // Same proactive refresh as currentUser(): don't send a token the exp claim
        // already proves dead. The reactive 401/403 retry below stays as the safety net.
        if let token = accessToken, refreshToken != nil,
           let expiry = Self.tokenExpiry(token), expiry <= Date().addingTimeInterval(60) {
            try? await refreshSession()
        }
        if let token = accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (status == 401 || status == 403), refreshToken != nil else {
            return (data, response)
        }

        let previousToken = accessToken
        try? await refreshSession()
        guard let refreshedToken = accessToken, refreshedToken != previousToken else {
            return (data, response)
        }

        req.setValue("Bearer \(refreshedToken)", forHTTPHeaderField: "Authorization")
        return try await session.data(for: req)
    }

    private func selectWhere<T: Decodable>(table: String, column: String, value: String) async throws -> [T] {
        var components = URLComponents(url: restURL(table), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: column, value: "eq.\(value)")]
        let req = authorizedRequest(url: components.url!)
        let (data, response) = try await performAuthorizedRequest(req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            logError("select:\(table)", data: data, response: response)
            throw BackendError.loadFailed(table)
        }
        do {
            return try decoder.decode([T].self, from: data)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            print("[TrueCarry][Supabase] DECODE ERROR select:\(table): \(error) — body: \(body.prefix(300))")
            throw error
        }
    }

    /// Calls a table-returning Postgres RPC and decodes the JSON array result.
    private func rpc<T: Decodable>(_ name: String, body: [String: Any]) async throws -> [T] {
        let url = config.rpcBaseURL.appendingPathComponent(name)
        var req = authorizedRequest(url: url, method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await performAuthorizedRequest(req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 201 else {
            logError("rpc:\(name)", data: data, response: response)
            throw BackendError.loadFailed("rpc:\(name)")
        }
        if data.isEmpty { return [] }
        return try decoder.decode([T].self, from: data)
    }

    /// Calls a void-returning Postgres RPC (ignores the body).
    private func rpcVoid(_ name: String, body: [String: Any]) async throws {
        let url = config.rpcBaseURL.appendingPathComponent(name)
        var req = authorizedRequest(url: url, method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await performAuthorizedRequest(req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 201 || status == 204 else {
            logError("rpc:\(name)", data: data, response: response)
            throw BackendError.saveFailed("rpc:\(name)")
        }
    }

    // MARK: - Account lifecycle, export & telemetry

    /// Hard-deletes the signed-in account via the delete-account Edge Function
    /// (service role: removes the auth user + cascades all data + storage). On
    /// success the caller should clear the local session.
    func deleteAccount() async throws {
        let url = config.functionsBaseURL.appendingPathComponent("delete-account")
        var req = authorizedRequest(url: url, method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: [:])
        let (data, response) = try await performAuthorizedRequest(req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            logError("delete-account", data: data, response: response)
            throw BackendError.saveFailed("delete-account")
        }
    }

    /// Returns the caller's complete data as a JSON document (GDPR/CCPA export),
    /// via the export_my_data() RPC (scalar jsonb → returned as-is).
    func exportMyData() async throws -> Data {
        let url = config.rpcBaseURL.appendingPathComponent("export_my_data")
        var req = authorizedRequest(url: url, method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: [:])
        let (data, response) = try await performAuthorizedRequest(req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            logError("rpc:export_my_data", data: data, response: response)
            throw BackendError.loadFailed("export_my_data")
        }
        return data
    }

    /// Appends a product-telemetry event. Fire-and-forget: swallows all errors so
    /// analytics can never break or slow a user flow.
    func logAnalyticsEvent(_ event: String, properties: [String: Any], sessionId: UUID?) async {
        var body: [String: Any] = ["event": event, "properties": properties]
        if let uid = accessTokenUserId { body["user_id"] = uid }
        if let sid = sessionId { body["session_id"] = sid.uuidString }
        body["app_version"] = Self.appVersion
        body["platform"] = "iOS"
        do {
            var req = authorizedRequest(url: restURL("analytics_events"), method: "POST")
            req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            _ = try? await performAuthorizedRequest(req)
        } catch { /* telemetry must never throw */ }
    }

    private static let appVersion: String =
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"

    /// Decodes the `sub` (user id) claim from the current access token's JWT payload.
    private var accessTokenUserId: String? {
        guard let token = accessToken else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = obj["sub"] as? String else { return nil }
        return sub
    }

    private func upsert(table: String, body: [String: Any], onConflict: String? = nil) async throws {
        var components = URLComponents(url: restURL(table), resolvingAgainstBaseURL: false)!
        if let col = onConflict {
            components.queryItems = [URLQueryItem(name: "on_conflict", value: col)]
        }
        var req = authorizedRequest(url: components.url!, method: "POST")
        req.setValue("return=minimal,resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await performAuthorizedRequest(req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 201 || status == 204 else {
            logError("upsert:\(table)", data: data, response: response)
            throw BackendError.saveFailed(table)
        }
    }

    private func deleteRow(table: String, id: UUID) async throws {
        var components = URLComponents(url: restURL(table), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")]
        var req = authorizedRequest(url: components.url!, method: "DELETE")
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        _ = try? await performAuthorizedRequest(req)
    }

    private func toDict<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try encoder.encode(value)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func payloadToDict<T: Encodable>(_ value: T) throws -> [String: Any] {
        let payloadEncoder = JSONEncoder()
        payloadEncoder.dateEncodingStrategy = .iso8601
        let data = try payloadEncoder.encode(value)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func payloadRowBody<T: Encodable>(
        id: UUID,
        userId: UUID,
        payload: T,
        dateColumn: String,
        date: Date
    ) throws -> [String: Any] {
        [
            "id": id.uuidString,
            "user_id": userId.uuidString,
            "payload": try payloadToDict(payload),
            dateColumn: ISO8601DateFormatter().string(from: date)
        ]
    }

    private func profileToDict(_ p: UserProfile) -> [String: Any] {
        var d: [String: Any] = [
            "id": p.id.uuidString,
            "user_id": p.userId.uuidString,
            "display_name": p.displayName,
            "handedness": p.handedness.rawValue,
            "gender": p.gender.rawValue,
            "distance_unit": p.distanceUnit.rawValue,
            "speed_unit": p.speedUnit.rawValue,
            "home_course_name": p.homeCourseName
        ]
        if let path = p.profileImagePath { d["profile_image_path"] = path }
        if let u = p.username, !u.isEmpty { d["username"] = u }
        if let done = p.onboardingCompleted {
            d["onboarding_completed"] = done
            if done { d["onboarding_completed_at"] = ISO8601DateFormatter().string(from: Date()) }
        }
        return d
    }

    private func appUser(from su: SupabaseUser) -> AppUser {
        let name = (su.userMetadata?["display_name"]?.value as? String) ?? su.email ?? "User"
        return AppUser(
            id: UUID(uuidString: su.id) ?? UUID(),
            name: name,
            email: su.email ?? "",
            createdAt: Date(),
            subscriptionStatus: .free,
            isGuest: false,
            rememberedLogin: true
        )
    }

    // MARK: - Session persistence

    private func persistSession(_ auth: SupabaseAuthResponse) {
        persistSession(accessToken: auth.accessToken, refreshToken: auth.refreshToken)
    }

    private func persistSession(accessToken: String, refreshToken: String) {
        self.accessToken  = accessToken
        self.refreshToken = refreshToken
        UserDefaults.standard.set(accessToken,  forKey: "sb_access_token")
        UserDefaults.standard.set(refreshToken, forKey: "sb_refresh_token")
    }

    private func clearSession() {
        accessToken  = nil
        refreshToken = nil
        UserDefaults.standard.removeObject(forKey: "sb_access_token")
        UserDefaults.standard.removeObject(forKey: "sb_refresh_token")
    }

    func refreshSession() async throws {
        guard let rt = refreshToken else { throw BackendError.notAuthenticated }
        let url = config.authBaseURL
            .appendingPathComponent("token")
            .appending(queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")])
        var req = baseRequest(url: url, method: "POST")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": rt])
        let (data, response) = try await session.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            logError("refreshSession", data: data, response: response)
            clearSession()
            throw BackendError.notAuthenticated
        }
        let auth = try decoder.decode(SupabaseAuthResponse.self, from: data)
        persistSession(auth)
        print("[TrueCarry][Supabase] token refreshed")
    }

    // MARK: - Error logging

    private func logError(_ context: String, data: Data, response: URLResponse) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let body = String(data: data, encoding: .utf8) ?? "<binary>"
        print("[TrueCarry][Supabase] ERROR \(context) HTTP \(status): \(body.prefix(300))")
    }
}

// MARK: - EntitlementAction RPC key

private extension EntitlementAction {
    var rpcKey: String {
        switch self {
        case .rangeShot:        return "range_shot"
        case .simShot:          return "sim_shot"
        case .courseRound:      return "course_round"
        case .exportVideo:      return "export_video"
        case .advancedInsights: return "advanced_insights"
        case .courseMode:       return "course_mode"
        case .simMode:          return "sim_mode"
        }
    }
}
