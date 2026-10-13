// Minimal assertion bridge for running the SAME test methods when CLT lacks XCTest.
// Full Xcode uses the normal XCTest targets instead.
import Foundation

class XCTestCase {
    func tearDownWithError() throws {}
}
enum CheckLog {
    static var failures = 0
    static func fail(_ message: String, file: StaticString, line: UInt) {
        failures += 1; print("FAIL \(file):\(line): \(message)")
    }
}
func XCTFail(_ message: String = "Failure", file: StaticString = #filePath, line: UInt = #line) { CheckLog.fail(message, file: file, line: line) }
func XCTAssertTrue(_ expression: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if try !expression() { XCTFail("Expected true. " + message, file: file, line: line) } }
    catch { XCTFail("Unexpected error: \(error)", file: file, line: line) }
}
func XCTAssertFalse(_ expression: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if try expression() { XCTFail("Expected false. " + message, file: file, line: line) } }
    catch { XCTFail("Unexpected error: \(error)", file: file, line: line) }
}
func XCTAssertEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { let a = try lhs(), b = try rhs(); if a != b { XCTFail("\(a) != \(b). " + message, file: file, line: line) } }
    catch { XCTFail("Unexpected error: \(error)", file: file, line: line) }
}
func XCTAssertNil<T>(_ expression: @autoclosure () throws -> T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if try expression() != nil { XCTFail("Expected nil. " + message, file: file, line: line) } }
    catch { XCTFail("Unexpected error: \(error)", file: file, line: line) }
}
func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expression(); XCTFail("Expected an error. " + message, file: file, line: line) } catch {}
}
func XCTUnwrap<T>(_ expression: @autoclosure () throws -> T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) throws -> T {
    if let value = try expression() { return value }
    XCTFail("Expected non-nil. " + message, file: file, line: line)
    throw UnwrapFailure.nilValue
}
enum UnwrapFailure: Error { case nilValue }
