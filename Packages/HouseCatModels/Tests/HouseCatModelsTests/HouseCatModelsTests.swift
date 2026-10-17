@testable import HouseCatModels
import Testing

@Test func packageLoads() {
    #expect(String(describing: HouseCatModels.self) == "HouseCatModels")
}
