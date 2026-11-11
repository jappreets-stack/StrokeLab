import Foundation

/// Front / center / back of every green, worked out from the course map in OpenStreetMap
/// (green outlines + each hole's tee-to-green line). Map data © OpenStreetMap contributors, ODbL.
nonisolated enum CourseGreens {
    static let pins: [GreenPins] = [
        GreenPins(hole: 1, front: Coordinate(lat: 40.5664276, lon: -124.1033329), center: Coordinate(lat: 40.5664914, lon: -124.1032421), back: Coordinate(lat: 40.5665518, lon: -124.1031559)),
        GreenPins(hole: 2, front: Coordinate(lat: 40.566503, lon: -124.1008442), center: Coordinate(lat: 40.5664926, lon: -124.1006561), back: Coordinate(lat: 40.5664831, lon: -124.1004832)),
        GreenPins(hole: 3, front: Coordinate(lat: 40.5649356, lon: -124.1056419), center: Coordinate(lat: 40.5648901, lon: -124.1057684), back: Coordinate(lat: 40.5648454, lon: -124.1058927)),
        GreenPins(hole: 4, front: Coordinate(lat: 40.5653837, lon: -124.1021192), center: Coordinate(lat: 40.5654311, lon: -124.1019611), back: Coordinate(lat: 40.5654758, lon: -124.101812)),
        GreenPins(hole: 5, front: Coordinate(lat: 40.5635737, lon: -124.1061311), center: Coordinate(lat: 40.5635282, lon: -124.1062815), back: Coordinate(lat: 40.5634869, lon: -124.106418)),
        GreenPins(hole: 6, front: Coordinate(lat: 40.5629346, lon: -124.1053839), center: Coordinate(lat: 40.5628966, lon: -124.1052681), back: Coordinate(lat: 40.5628643, lon: -124.1051694)),
        GreenPins(hole: 7, front: Coordinate(lat: 40.5604588, lon: -124.1088028), center: Coordinate(lat: 40.5604006, lon: -124.1089003), back: Coordinate(lat: 40.5603415, lon: -124.1089995)),
        GreenPins(hole: 8, front: Coordinate(lat: 40.5642498, lon: -124.106622), center: Coordinate(lat: 40.5643435, lon: -124.1065751), back: Coordinate(lat: 40.5644085, lon: -124.1065426)),
        GreenPins(hole: 9, front: Coordinate(lat: 40.56498, lon: -124.1071396), center: Coordinate(lat: 40.5650223, lon: -124.1072301), back: Coordinate(lat: 40.5650721, lon: -124.1073365)),
        GreenPins(hole: 10, front: Coordinate(lat: 40.5612621, lon: -124.1097179), center: Coordinate(lat: 40.5611854, lon: -124.1098052), back: Coordinate(lat: 40.5610934, lon: -124.1099098)),
        GreenPins(hole: 11, front: Coordinate(lat: 40.5610847, lon: -124.1106274), center: Coordinate(lat: 40.56115, lon: -124.1107253), back: Coordinate(lat: 40.5612056, lon: -124.1108089)),
        GreenPins(hole: 12, front: Coordinate(lat: 40.5566477, lon: -124.1114102), center: Coordinate(lat: 40.5565223, lon: -124.11142), back: Coordinate(lat: 40.5564126, lon: -124.1114285)),
        GreenPins(hole: 13, front: Coordinate(lat: 40.5593371, lon: -124.1100922), center: Coordinate(lat: 40.5594017, lon: -124.1100559), back: Coordinate(lat: 40.5595097, lon: -124.1099952)),
        GreenPins(hole: 14, front: Coordinate(lat: 40.5603035, lon: -124.1109467), center: Coordinate(lat: 40.5603504, lon: -124.1110676), back: Coordinate(lat: 40.5603844, lon: -124.1111554)),
        GreenPins(hole: 15, front: Coordinate(lat: 40.5647013, lon: -124.1107654), center: Coordinate(lat: 40.564804, lon: -124.1107369), back: Coordinate(lat: 40.5648986, lon: -124.1107107)),
        GreenPins(hole: 16, front: Coordinate(lat: 40.5640243, lon: -124.1105696), center: Coordinate(lat: 40.5639079, lon: -124.1106455), back: Coordinate(lat: 40.5638016, lon: -124.1107148)),
        GreenPins(hole: 17, front: Coordinate(lat: 40.5618223, lon: -124.1106148), center: Coordinate(lat: 40.5617084, lon: -124.1106157), back: Coordinate(lat: 40.5615757, lon: -124.1106167)),
        GreenPins(hole: 18, front: Coordinate(lat: 40.5644036, lon: -124.1082667), center: Coordinate(lat: 40.5645603, lon: -124.108163), back: Coordinate(lat: 40.56469, lon: -124.1080772)),
    ]
}
