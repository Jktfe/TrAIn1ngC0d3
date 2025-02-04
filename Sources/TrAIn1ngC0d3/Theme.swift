import SwiftUI

enum Theme {
    static let primaryColor = Color(red: 0, green: 0.8, blue: 0.7) // Turquoise from logo
    static let secondaryColor = Color(red: 0.7, green: 0.9, blue: 0.2) // Lime green from logo
    static let backgroundColor = Color(.windowBackgroundColor)
    static let darkBackgroundColor = Color(red: 0.05, green: 0.1, blue: 0.15) // Dark navy from logo background
    static let textColor = Color(.labelColor)
    static let secondaryTextColor = Color(.secondaryLabelColor)
    static let errorColor = Color.red
    static let warningColor = Color.orange
    static let successColor = Color.green
    
    static let buttonGradient = LinearGradient(
        colors: [primaryColor, secondaryColor],
        startPoint: .leading,
        endPoint: .trailing
    )
}
