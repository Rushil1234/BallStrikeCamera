import Foundation

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
        // Try to refresh if we have a refresh token but no access token
        if accessToken == nil, let _ = refreshToken {
            try? await refreshSession()
        }
        guard let token = accessToken else { return nil }

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
        let auth = try decoder.decode(SupabaseAuthResponse.self, from: data)
        persistSession(auth)
        print("[TrueCarry][Supabase] createAccount — \(auth.user.email ?? "?")")
        return appUser(from: auth.user)
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
        try await upsert(table: "profiles", body: body)
    }

    func loadUserProfile(userId: UUID) async throws -> UserProfile? {
        let rows: [SupabaseProfileRow] = try await selectWhere(
            table: "profiles", column: "user_id", value: userId.uuidString)
        return rows.first?.toUserProfile()
    }

    // MARK: - Clubs

    func saveClub(_ club: UserClub) async throws {
        do {
            try await upsert(table: "clubs", body: try toDict(club))
        } catch {
            var body = try toDict(club)
            body.removeValue(forKey: "brand")
            body.removeValue(forKey: "loft_degrees")
            try await upsert(table: "clubs", body: body)
        }
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
        try await upsert(table: "shots", body: try toDict(shot))
    }

    func loadShots(userId: UUID) async throws -> [SavedShot] {
        let rows: [SavedShot] = try await selectWhere(
            table: "shots", column: "user_id", value: userId.uuidString)
        return rows.sorted { $0.timestamp > $1.timestamp }
    }

    func deleteShot(shotId: UUID, userId: UUID) async throws {
        try await deleteRow(table: "shots", id: shotId)
    }

    // MARK: - Range Sessions

    func saveRangeSession(_ session: PracticeSession) async throws {
        try await upsert(table: "range_sessions", body: try toDict(session))
    }

    func deleteRangeSession(sessionId: UUID, userId: UUID) async throws {
        try await deleteRow(table: "range_sessions", id: sessionId)
    }

    func loadRangeSessions(userId: UUID) async throws -> [PracticeSession] {
        let rows: [PracticeSession] = try await selectWhere(
            table: "range_sessions", column: "user_id", value: userId.uuidString)
        return rows.sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: - Sim Sessions

    func saveSimSession(_ session: SimSession) async throws {
        try await upsert(table: "sim_sessions", body: try toDict(session))
    }

    func loadSimSessions(userId: UUID) async throws -> [SimSession] {
        let rows: [SimSession] = try await selectWhere(
            table: "sim_sessions", column: "user_id", value: userId.uuidString)
        return rows.sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: - Course Rounds

    func saveRound(_ round: CourseRound) async throws {
        try await upsert(table: "course_rounds", body: try toDict(round))
    }

    func loadCourseRounds(userId: UUID) async throws -> [CourseRound] {
        let rows: [CourseRound] = try await selectWhere(
            table: "course_rounds", column: "user_id", value: userId.uuidString)
        return rows.sorted { $0.startedAt > $1.startedAt }
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
        if let confidence = metadata.confidence { body["confidence"] = confidence }
        if let generatedBy = metadata.generatedBy { body["generated_by"] = generatedBy }
        if let imagerySource = metadata.imagerySource { body["imagery_source"] = imagerySource }
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
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 201 || status == 204 else {
            logError("upsert:geometry_backfill_requests", data: data, response: response)
            throw BackendError.saveFailed("geometry_backfill_requests")
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
        let (data, response) = try await session.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            logError("select:feed_posts", data: data, response: response)
            throw BackendError.loadFailed("feed_posts")
        }
        let rows = try decoder.decode([SupabaseFeedPostRow].self, from: data)
        return rows.compactMap { $0.toFeedPost() }.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Gimmes (feed reactions)

    func loadGimmes() async throws -> [FeedReaction] {
        // RLS scopes reactions to posts the caller can see.
        var components = URLComponents(url: restURL("feed_reactions"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "emoji", value: "eq.gimme")]
        let req = authorizedRequest(url: components.url!)
        let (data, response) = try await session.data(for: req)
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
        let (data, response) = try await session.data(for: req)
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
        _ = try? await session.data(for: req)
    }

    // MARK: - Comments

    func loadComments(postId: UUID) async throws -> [FeedComment] {
        var components = URLComponents(url: restURL("feed_comments"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "post_id", value: "eq.\(postId.uuidString)"),
            URLQueryItem(name: "order", value: "created_at.asc")
        ]
        let req = authorizedRequest(url: components.url!)
        let (data, response) = try await session.data(for: req)
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
        _ = try? await session.data(for: req)
    }

    func loadFriends() async throws -> [FriendProfile] {
        let rows: [SupabaseUserSearchRow] = try await rpc("list_friends", body: [:])
        return rows.compactMap { $0.toFriendProfile() }
    }

    func createInviteCode(userId: UUID) async throws -> String {
        let code = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).uppercased()
        try await upsert(table: "invite_codes", body: ["code": code, "user_id": userId.uuidString])
        return code
    }

    func redeemInvite(code: String) async throws {
        try await rpcVoid("redeem_invite", body: ["p_code": code])
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
        let (data, response) = try await session.data(for: req)
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
        let (data, response) = try await session.data(for: req)
        if (response as? HTTPURLResponse)?.statusCode != 200 {
            logError("incrementUsage", data: data, response: response)
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

    private func selectWhere<T: Decodable>(table: String, column: String, value: String) async throws -> [T] {
        var components = URLComponents(url: restURL(table), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: column, value: "eq.\(value)")]
        let req = authorizedRequest(url: components.url!)
        let (data, response) = try await session.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            logError("select:\(table)", data: data, response: response)
            throw BackendError.loadFailed(table)
        }
        return try decoder.decode([T].self, from: data)
    }

    /// Calls a table-returning Postgres RPC and decodes the JSON array result.
    private func rpc<T: Decodable>(_ name: String, body: [String: Any]) async throws -> [T] {
        let url = config.rpcBaseURL.appendingPathComponent(name)
        var req = authorizedRequest(url: url, method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: req)
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
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 201 || status == 204 else {
            logError("rpc:\(name)", data: data, response: response)
            throw BackendError.saveFailed("rpc:\(name)")
        }
    }

    private func upsert(table: String, body: [String: Any]) async throws {
        var req = authorizedRequest(url: restURL(table), method: "POST")
        req.setValue("return=representation,resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 201 else {
            logError("upsert:\(table)", data: data, response: response)
            throw BackendError.saveFailed(table)
        }
    }

    private func deleteRow(table: String, id: UUID) async throws {
        var components = URLComponents(url: restURL(table), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")]
        var req = authorizedRequest(url: components.url!, method: "DELETE")
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        _ = try? await session.data(for: req)
    }

    private func toDict<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try encoder.encode(value)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func profileToDict(_ p: UserProfile) -> [String: Any] {
        var d: [String: Any] = [
            "id": p.id.uuidString,
            "user_id": p.userId.uuidString,
            "display_name": p.displayName,
            "handedness": p.handedness.rawValue,
            "distance_unit": p.distanceUnit.rawValue,
            "speed_unit": p.speedUnit.rawValue,
            "home_course_name": p.homeCourseName
        ]
        if let path = p.profileImagePath { d["profile_image_path"] = path }
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
        accessToken  = auth.accessToken
        refreshToken = auth.refreshToken
        UserDefaults.standard.set(auth.accessToken,  forKey: "sb_access_token")
        UserDefaults.standard.set(auth.refreshToken, forKey: "sb_refresh_token")
    }

    private func clearSession() {
        accessToken  = nil
        refreshToken = nil
        UserDefaults.standard.removeObject(forKey: "sb_access_token")
        UserDefaults.standard.removeObject(forKey: "sb_refresh_token")
    }

    private func refreshSession() async throws {
        guard let rt = refreshToken else { return }
        let url = config.authBaseURL
            .appendingPathComponent("token")
            .appending(queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")])
        var req = baseRequest(url: url, method: "POST")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": rt])
        let (data, response) = try await session.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let auth = try? decoder.decode(SupabaseAuthResponse.self, from: data) else { return }
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
