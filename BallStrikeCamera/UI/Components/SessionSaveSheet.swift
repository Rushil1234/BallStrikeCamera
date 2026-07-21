import SwiftUI

// MARK: - Config

enum SessionSaveType {
    case range, sim, course

    var title: String {
        switch self {
        case .range:  return "Save Range Session"
        case .sim:    return "Save Sim Session"
        case .course: return "Save Round"
        }
    }

    var namePlaceholder: String {
        switch self {
        case .range:  return "Range Session 1"
        case .sim:    return "Sim Session 1"
        case .course: return "Course Round"
        }
    }
}

struct SessionSaveConfig {
    let type: SessionSaveType
    var defaultName: String
    var date: Date
}

// MARK: - Sheet

struct SessionSaveSheet: View {
    @Environment(\.dismiss) private var dismiss

    let config: SessionSaveConfig
    /// (name, description, shareVisibility). `shareVisibility` is nil to keep the session
    /// private (History only, no feed post), else the chosen feed audience.
    let onSave:   (String, String?, FeedVisibility?) -> Void
    var onDelete: (() -> Void)? = nil

    @State private var name: String
    @State private var description: String = ""
    @State private var showDeleteConfirm = false
    @State private var share: ShareChoice = .justSave

    /// The three ways a saved session can go out — mirrors the course-mode Post/Private flow.
    private enum ShareChoice: String, CaseIterable {
        case justSave = "Just Save", friends = "Friends", everyone = "Public"
        var visibility: FeedVisibility? {
            switch self {
            case .justSave: return nil
            case .friends:  return .friends
            case .everyone: return .everyone
            }
        }
        var caption: String {
            switch self {
            case .justSave: return "Saved to your History only — nothing is posted."
            case .friends:  return "Posts to the feed for your friends and home-course golfers."
            case .everyone: return "Posts to the feed for everyone."
            }
        }
    }

    init(config: SessionSaveConfig,
         onSave: @escaping (String, String?, FeedVisibility?) -> Void,
         onDelete: (() -> Void)? = nil) {
        self.config = config
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: config.defaultName)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedName.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(config.type.namePlaceholder, text: $name)
                        .submitLabel(.done)
                } header: {
                    Text("Name")
                }

                Section {
                    HStack {
                        Text(formattedDate)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } header: {
                    Text("Date")
                }

                Section {
                    ZStack(alignment: .topLeading) {
                        if description.isEmpty {
                            Text("Optional notes about this session…")
                                .foregroundColor(Color(UIColor.placeholderText))
                                .padding(.vertical, 8)
                                .padding(.horizontal, 4)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $description)
                            .frame(minHeight: 80)
                    }
                } header: {
                    Text("Description (Optional)")
                }

                Section {
                    Picker("Share", selection: $share) {
                        ForEach(ShareChoice.allCases, id: \.self) { c in
                            Text(c.rawValue).tag(c)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(share.caption)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } header: {
                    Text("Share to Feed")
                }

                if onDelete != nil {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            HStack {
                                Spacer()
                                Text("Delete Session")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(config.type.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let finalName = trimmedName.isEmpty ? config.defaultName : trimmedName
                        let desc = description.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(finalName, desc.isEmpty ? nil : desc, share.visibility)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .confirmationDialog(
                "Delete this session?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Session", role: .destructive) {
                    dismiss()
                    onDelete?()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
        }
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: config.date)
    }
}
