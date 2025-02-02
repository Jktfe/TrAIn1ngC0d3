import SwiftUI
import AppKit

enum Theme {
    static let primaryColor = Color(red: 0.25, green: 0.35, blue: 0.75) // Refined blue from logo
    static let secondaryColor = Color(red: 0.75, green: 0.25, blue: 0.35) // Complementary accent
    static let backgroundColor = Color(red: 0.97, green: 0.97, blue: 0.98) // Lighter background
    static let textColor = Color(red: 0.15, green: 0.15, blue: 0.2) // Darker text for better contrast
    
    static let buttonStyle = BorderedButtonStyle()
    
    struct BorderedButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(configuration.isPressed ? primaryColor.opacity(0.8) : primaryColor)
                )
                .foregroundColor(.white)
                .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
        }
    }
    
    struct SecondaryButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(primaryColor, lineWidth: 1.5)
                )
                .foregroundColor(primaryColor)
                .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
        }
    }
}
