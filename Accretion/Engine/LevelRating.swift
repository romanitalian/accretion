import Foundation

/// 1–3 stars for a won level: the less mass the player threw away, the better.
public enum LevelRating {
    /// Ejected mass as a share of the starting mass, for 3 and 2 stars. Tune after playtests.
    public static let threeStarLimit = 0.6
    public static let twoStarLimit = 1.5

    public static func stars(ejectedMass: Double, initialMass: Double) -> Int {
        guard initialMass > 0 else { return 1 }
        let spent = ejectedMass / initialMass
        if spent <= threeStarLimit { return 3 }
        if spent <= twoStarLimit { return 2 }
        return 1
    }
}
