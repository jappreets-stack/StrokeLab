import Foundation

/// One hole on the card. Never changes, so it lives in code.
nonisolated struct Hole: Identifiable, Hashable, Sendable {
    let number: Int
    let par: Int
    let yards: Int
    let strokeIndex: Int
    var id: Int { number }
}

/// Redwood Empire Golf & Country Club, Fortuna CA — White tees.
nonisolated enum Course {
    static let name = "Redwood Empire GCC"
    static let tees = "White"
    static let rating = 68.7
    static let slope = 124

    private static let yards = [361,160,507,376,344,118,444,492,145, 480,188,461,298,158,496,119,294,377]
    private static let pars  = [4,3,5,4,4,3,5,5,3, 5,3,5,4,3,5,3,4,4]
    private static let si    = [7,11,1,3,9,17,5,13,15, 2,8,14,10,12,4,18,16,6]

    static let holes: [Hole] = (0..<18).map {
        Hole(number: $0 + 1, par: pars[$0], yards: yards[$0], strokeIndex: si[$0])
    }

    static func hole(_ number: Int) -> Hole { holes[number - 1] }
    static var par: Int { pars.reduce(0, +) }
    static func par(of numbers: [Int]) -> Int { numbers.map { hole($0).par }.reduce(0, +) }
}
