// Temporary: lets the app build (with the bundled skins) until SkinRenderer.swift is ported. Delete with it.
import CoreGraphics

enum SkinRenderer {
    struct Result {
        let keypad: CGRect
        let mask: [UInt8]
        let maskWidth: Int
        let maskHeight: Int
        let backgroundColor: ARGB
    }

    struct NotPorted: Error {}

    static func render(model: CalcModel, type: SkinType, into cg: CGContext, area: CGRect, oledContrast: Int = 70, threeD: Bool = false) throws -> Result {
        throw NotPorted()
    }
}
