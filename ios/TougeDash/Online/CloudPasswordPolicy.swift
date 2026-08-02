import Foundation

enum CloudPasswordPolicy {
    static let minimumLength = 10
    static let maximumLength = 72

    static func isValid(_ value: String) -> Bool {
        let lengthIsValid = value.count >= minimumLength && value.count <= maximumLength
        return lengthIsValid
            && value.rangeOfCharacter(from: .letters) != nil
            && value.rangeOfCharacter(from: .decimalDigits) != nil
    }

    static func strength(_ value: String) -> (score: Int, label: String) {
        guard !value.isEmpty else { return (0, "") }
        var score = 0
        if value.count >= minimumLength { score += 1 }
        if value.rangeOfCharacter(from: .lowercaseLetters) != nil,
           value.rangeOfCharacter(from: .uppercaseLetters) != nil { score += 1 }
        if value.rangeOfCharacter(from: .decimalDigits) != nil { score += 1 }
        let symbols = CharacterSet.alphanumerics.union(.whitespacesAndNewlines).inverted
        if value.count >= 14 || value.rangeOfCharacter(from: symbols) != nil { score += 1 }
        let label = isValid(value)
            ? ["Słabe", "Słabe", "W porządku", "Dobre", "Mocne"][score]
            : (score <= 1 ? "Słabe" : "Uzupełnij wymagania")
        return (score, label)
    }
}
