import XCTest
@testable import FallLineCore

// MARK: - 角度计算测试

final class AngleCalculationTests: XCTestCase {

    let calculator = PoseMetricsCalculator()

    // MARK: angleBetween 测试

    func testAngleBetween_rightAngle() {
        // 直角：(0,1) -- (0,0) -- (1,0) 应为 90°
        let a = CGPoint(x: 0, y: 1)
        let b = CGPoint(x: 0, y: 0)  // 顶点
        let c = CGPoint(x: 1, y: 0)
        let angle = calculator.angleBetween(a, b, c)
        XCTAssertEqual(angle, 90.0, accuracy: 0.01)
    }

    func testAngleBetween_straightLine() {
        // 三点共线：180°
        let a = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: 1, y: 0)
        let c = CGPoint(x: 2, y: 0)
        let angle = calculator.angleBetween(a, b, c)
        XCTAssertEqual(angle, 180.0, accuracy: 0.01)
    }

    func testAngleBetween_obtuseAngle() {
        // 顶点处为 135° 的钝角
        let a = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: 1, y: 0)
        let c = CGPoint(x: 2, y: 1)
        let angle = calculator.angleBetween(a, b, c)
        XCTAssertEqual(angle, 135.0, accuracy: 0.01)
    }

    func testAngleBetween_identicalPoints_returnsZero() {
        // 两点重合应返回 0（向量长度为零的边界情况）
        let a = CGPoint(x: 1, y: 1)
        let b = CGPoint(x: 1, y: 1)
        let c = CGPoint(x: 2, y: 2)
        let angle = calculator.angleBetween(a, b, c)
        XCTAssertEqual(angle, 0.0, accuracy: 0.01)
    }

    // MARK: leanAngleFromVertical 测试

    func testLeanAngle_verticalZero() {
        // 纯垂直方向：倾斜角应为 0°
        let top = CGPoint(x: 0, y: 10)
        let bottom = CGPoint(x: 0, y: 0)
        let angle = calculator.leanAngleFromVertical(from: top, to: bottom)
        XCTAssertEqual(angle, 0.0, accuracy: 0.01)
    }

    func testLeanAngle_45degrees() {
        // 45° 倾斜：dx == dy
        let top = CGPoint(x: 0, y: 10)
        let bottom = CGPoint(x: 10, y: 0)
        let angle = calculator.leanAngleFromVertical(from: top, to: bottom)
        XCTAssertEqual(angle, 45.0, accuracy: 0.01)
    }

    func testLeanAngle_horizontal90() {
        // 纯水平：dy = 0 → 返回 90°
        let top = CGPoint(x: 0, y: 0)
        let bottom = CGPoint(x: 10, y: 0)
        let angle = calculator.leanAngleFromVertical(from: top, to: bottom)
        XCTAssertEqual(angle, 90.0, accuracy: 0.01)
    }
}
