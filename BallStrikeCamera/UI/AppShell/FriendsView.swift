import SwiftUI

struct FriendsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: FriendsViewModel
    private let backend: AppBackend
    @State private var profileTarget: ProfileTarget?

    init(userId: UUID, backend: AppBackend) {
        self.backend = backend
        _vm = StateObject(wrappedValue: FriendsViewModel(userId: userId, backend: backend))
    }

    var body: some View {
        ZStack {
            TCTheme.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: TCTheme.sectionGap) {
                    searchSection
                    if !vm.requests.isEmpty { requestsSection }
                    if !vm.attestations.isEmpty { attestationsSection }
                    inviteSection
                    friendsSection
                    Spacer(minLength: 32)
                }
                .padding(.horizontal, TCTheme.hPad)
                .padding(.top, 8)
            }
        }
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }.foregroundColor(TCTheme.gold)
            }
        }
        .task { await vm.loadAll() }
        .overlay(alignment: .bottom) { statusToast }
        .sheet(item: $profileTarget) { t in
            NavigationStack {
                PublicProfileView(userId: t.id, seedName: t.name, seedHomeCourse: t.homeCourse,
                                  seedPosts: t.seedPosts, backend: backend)
            }
            .tcAppearance()
        }
    }

    private func openProfile(_ profile: FriendProfile) {
        profileTarget = ProfileTarget(id: profile.userId, name: profile.displayName,
                                      homeCourse: profile.homeCourseName, seedPosts: [])
    }

    // MARK: Search

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Add by name")
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundColor(TCTheme.textMuted)
                TextField("Search golfers…", text: $vm.query)
                    .textFieldStyle(.plain)
                    .foregroundColor(TCTheme.textPrimary)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await vm.search() } }
                    .onChange(of: vm.query) { _ in Task { await vm.search() } }
                if vm.isSearching { ProgressView().tint(TCTheme.gold) }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(TCTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous))

            ForEach(vm.results) { profile in
                personRow(profile) {
                    if vm.isFriend(profile) {
                        Text("Friends").font(.system(size: 12, weight: .semibold)).foregroundColor(TCTheme.sage)
                    } else if vm.sentRequestIds.contains(profile.userId) {
                        Text("Requested").font(.system(size: 12, weight: .semibold)).foregroundColor(TCTheme.textMuted)
                    } else {
                        actionButton("Add", filled: true) { Task { await vm.sendRequest(to: profile) } }
                    }
                }
            }
            if vm.query.count >= 2 && vm.results.isEmpty && !vm.isSearching {
                Text("No golfers found.").font(.system(size: 13)).foregroundColor(TCTheme.textMuted)
            }
        }
    }

    // MARK: Requests

    private var requestsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Friend requests")
            ForEach(vm.requests) { req in
                let profile = FriendProfile(userId: req.fromUserId, displayName: req.displayName, homeCourseName: nil)
                personRow(profile) {
                    HStack(spacing: 8) {
                        actionButton("Accept", filled: true) { Task { await vm.accept(req) } }
                        actionButton("Decline", filled: false) { Task { await vm.decline(req) } }
                    }
                }
            }
        }
    }

    // MARK: Attestation requests

    private var attestationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Attestation requests")
            ForEach(vm.attestations) { a in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        AvatarCircle(name: a.requesterName, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.requesterName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(TCTheme.textPrimary)
                                .fitOneLine(0.6)
                            Text(attestationDetail(a))
                                .font(.system(size: 12))
                                .foregroundColor(TCTheme.textMuted)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    HStack(spacing: 8) {
                        actionButton("Attest", filled: true) { Task { await vm.respondAttestation(a, accept: true) } }
                        actionButton("Decline", filled: false) { Task { await vm.respondAttestation(a, accept: false) } }
                    }
                }
                .tcCard(padding: 12)
            }
        }
    }

    private func attestationDetail(_ a: IncomingAttestation) -> String {
        var parts: [String] = []
        if !a.courseName.isEmpty { parts.append(a.courseName) }
        if let score = a.score {
            if let toPar = a.toPar {
                let tp = toPar == 0 ? "E" : (toPar > 0 ? "+\(toPar)" : "\(toPar)")
                parts.append("\(score) (\(tp))")
            } else {
                parts.append("\(score)")
            }
        }
        return parts.isEmpty ? "Wants you to verify a round" : parts.joined(separator: " · ")
    }

    // MARK: Invite

    private var inviteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Invite a friend")
            VStack(alignment: .leading, spacing: 12) {
                if let code = vm.inviteCode {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Your invite code").font(.system(size: 12)).foregroundColor(TCTheme.textMuted)
                            Text(code).font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundColor(TCTheme.gold)
                        }
                        Spacer()
                        ShareLink(item: "Add me on True Carry — open the app, go to Friends, and redeem code \(code)") {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 18)).foregroundColor(TCTheme.gold)
                        }
                    }
                } else {
                    actionButton("Generate invite code", filled: true) { Task { await vm.makeInviteCode() } }
                }

                Rectangle().fill(TCTheme.border).frame(height: 1)

                Text("Have a code?").font(.system(size: 12)).foregroundColor(TCTheme.textMuted)
                HStack(spacing: 10) {
                    TextField("Enter code", text: $vm.redeemCode)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .foregroundColor(TCTheme.textPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(TCTheme.panelRaised)
                        .clipShape(RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous))
                    actionButton("Redeem", filled: true) { Task { await vm.redeem() } }
                }
            }
            .tcCard(padding: 16)
        }
    }

    // MARK: Friends

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Your friends (\(vm.friends.count))")
            if vm.friends.isEmpty {
                Text("No friends yet. Add golfers above to build your feed.")
                    .font(.system(size: 13)).foregroundColor(TCTheme.textMuted)
            } else {
                ForEach(vm.friends) { friend in
                    personRow(friend) { EmptyView() }
                }
            }
        }
    }

    // MARK: Reusable bits

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.8)
            .foregroundColor(TCTheme.textMuted)
    }

    private func personRow<Trailing: View>(_ profile: FriendProfile, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            // Tap the avatar/name to open this golfer's profile.
            Button { openProfile(profile) } label: {
                HStack(spacing: 12) {
                    AvatarCircle(name: profile.displayName, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(TCTheme.textPrimary)
                            .fitOneLine(0.6)
                        if let home = profile.homeCourseName, !home.isEmpty {
                            Text(home).font(.system(size: 12)).foregroundColor(TCTheme.textMuted)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            trailing()
        }
        .tcCard(padding: 12)
    }

    private func actionButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(filled ? TCTheme.background : TCTheme.gold)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(filled ? TCTheme.gold : Color.clear)
                .overlay(
                    Capsule().strokeBorder(TCTheme.gold.opacity(filled ? 0 : 0.6), lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var statusToast: some View {
        if let msg = vm.statusMessage {
            Text(msg)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(TCTheme.textPrimary)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(TCTheme.panelRaised)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(TCTheme.border, lineWidth: 1))
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    withAnimation { vm.statusMessage = nil }
                }
        }
    }
}
