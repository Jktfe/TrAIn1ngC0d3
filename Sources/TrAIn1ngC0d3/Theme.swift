import SwiftUI
import AppKit

enum Theme {
    static let primaryColor = Color(red: 0.2, green: 0.4, blue: 0.8) // Blue from logo
    static let secondaryColor = Color(red: 0.8, green: 0.3, blue: 0.3) // Red accent
    static let backgroundColor = Color(red: 0.95, green: 0.95, blue: 0.97) // Light blue-gray
    static let textColor = Color(red: 0.2, green: 0.2, blue: 0.25) // Dark blue-gray
    
    static let buttonStyle = BorderedButtonStyle()
    
    struct BorderedButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(configuration.isPressed ? primaryColor.opacity(0.8) : primaryColor)
                )
                .foregroundColor(.white)
                .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
        }
    }
    
    struct SecondaryButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(primaryColor, lineWidth: 1)
                )
                .foregroundColor(primaryColor)
                .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
        }
    }
}
