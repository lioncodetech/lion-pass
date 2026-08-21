import SwiftUI

extension Color {
    static let lionCyan = Color(red: 0.322, green: 0.824, blue: 0.847)
    static let lionSky = Color(red: 0.263, green: 0.659, blue: 0.835)
    static let lionBlue = Color(red: 0.078, green: 0.345, blue: 0.722)
    static let lionViolet = Color(red: 0.518, green: 0.341, blue: 0.961)
    static let lionInk = Color(red: 0.027, green: 0.067, blue: 0.122)
    static let lionAccent = Color.lionViolet

    static var lionGradient: LinearGradient {
        LinearGradient(
            colors: [.lionCyan, .lionSky, .lionBlue, .lionViolet],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct LionSidebarButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(isSelected ? .semibold : .regular)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.lionViolet.opacity(0.82))
                } else if configuration.isPressed {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.lionViolet.opacity(0.18))
                }
            }
            .contentShape(Rectangle())
    }
}

struct LionCompactActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Color.lionViolet, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
