import SwiftUI

extension Color {
    static let fairway = Color(red: 0.10, green: 0.55, blue: 0.25)
    static let card = Color(.secondarySystemBackground)
}

/// Big, glare-proof choice button: solid green with white text when picked.
struct ChoiceButton: View {
    let title: String
    let selected: Bool
    var height: CGFloat = 56
    var font: Font = .title3.weight(.bold)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(font)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: height)
                .foregroundStyle(selected ? .white : .primary)
                .background(selected ? Color.fairway : Color.card, in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(selected ? 0 : 0.15)))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
    }
}

/// A labeled grid of choice buttons for one stat.
struct ChoiceRow<T: Hashable>: View {
    let label: String
    var hint: String? = nil
    let options: [T]
    let title: (T) -> String
    @Binding var value: T?
    var columns = 4
    var height: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.headline)
                if let hint { Text(hint).font(.subheadline).foregroundStyle(.secondary) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
                ForEach(options, id: \.self) { option in
                    ChoiceButton(title: title(option), selected: value == option, height: height) {
                        value = option
                    }
                }
            }
        }
    }
}

struct Pill: View {
    let text: String
    var color: Color = .card
    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(color, in: .capsule)
    }
}

/// Score colored like a scorecard: birdie or better, par, bogey, double+.
func scoreColor(_ score: Int, par: Int) -> Color {
    switch score - par {
    case ..<0: .blue
    case 0: .fairway
    case 1: .primary
    case 2: .orange
    default: .red
    }
}
