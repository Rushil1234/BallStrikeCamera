import SwiftUI

// History tab — reuses PastSessionsView which already supports
// Range / Course / Sim / Saved Shots with filter tabs and search.
struct TrueCarryHistoryView: View {
    var body: some View {
        PastSessionsView()
            .navigationBarHidden(true)
    }
}
