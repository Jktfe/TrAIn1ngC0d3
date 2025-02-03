import SwiftUI
import AppKit

enum Theme {
    static let primaryColor = Color.blue // Refined blue from logo
    static let secondaryColor = Color(red: 0.75, green: 0.25, blue: 0.35) // Complementary accent
    static let backgroundColor = Color(red: 0.95, green: 0.95, blue: 0.97) // Lighter background
    static let textColor = Color.primary // Darker text for better contrast
    static let borderColor = Color.gray.opacity(0.3)
    static let errorColor = Color.red
    static let warningColor = Color.orange
    static let successColor = Color.green
    
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
