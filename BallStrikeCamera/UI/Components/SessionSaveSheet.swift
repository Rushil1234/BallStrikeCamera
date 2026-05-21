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
    let onSave: (String, String?) -> Void

    @State private var name: String
    @State private var description: String = ""

    init(config: SessionSaveConfig, onSave: @escaping (String, String?) -> Void) {
        self.config = config
        self.onSave = onSave
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
                        onSave(finalName, desc.isEmpty ? nil : desc)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
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
