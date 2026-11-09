import SwiftUI

/// A note's paper.
struct NoteBackground: View {
    let color: NoteColor

    var body: some View { color.fill }
}
