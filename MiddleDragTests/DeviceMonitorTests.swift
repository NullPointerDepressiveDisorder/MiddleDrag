import XCTest

@testable import MiddleDrag

final class DeviceMonitorTests: XCTestCase {

    var monitor: DeviceMonitor!
    var mockFramework: MockMultitouchFramework!

    override func setUp() {
        super.setUp()
        mockFramework = MockMultitouchFramework()
        monitor = DeviceMonitor(framework: mockFramework)
    }

    override func tearDown() {
        monitor = nil
        mockFramework = nil
        super.tearDown()
    }

    // MARK: - Tests

    func testStart_FindsDevicesAndRegistersCallback() {
        // Setup mock devices
        let device1 = UnsafeMutableRawPointer(bitPattern: 0x1234)!
        mockFramework.mockDevices = [device1]

        // Start monitor
        monitor.start()

        // Verify
        XCTAssertTrue(mockFramework.getAllDevicesCalled)
        XCTAssertEqual(mockFramework.registeredDevices.count, 1)
        XCTAssertTrue(mockFramework.registeredDevices.contains(device1))
        XCTAssertEqual(mockFramework.startedDevices.count, 1)
        XCTAssertTrue(mockFramework.startedDevices.contains(device1))
    }

    func testStart_FallbackToDefaultDevice() {
        // Setup mock: list returns empty, default device returns something
        mockFramework.mockDevices = []
        let defaultDevice = UnsafeMutableRawPointer(bitPattern: 0x5678)!
        mockFramework.mockDefaultDevice = defaultDevice

        monitor.start()

        XCTAssertTrue(mockFramework.getAllDevicesCalled)
        XCTAssertTrue(mockFramework.getDefaultDeviceCalled)
        XCTAssertEqual(mockFramework.registeredDevices.count, 1)
        XCTAssertTrue(mockFramework.registeredDevices.contains(defaultDevice))
    }

    func testStart_DoesNotRegisterDuplicateDefaultDevice() {
        // Setup mock: list returns device1, default is also device1
        let device1 = UnsafeMutableRawPointer(bitPattern: 0x1234)!
        mockFramework.mockDevices = [device1]
        mockFramework.mockDefaultDevice = device1

        monitor.start()

        // Should only register once
        XCTAssertEqual(mockFramework.registerCallbackCount, 1)
    }

    func testStop_UnregistersAndStopsDevice() {
        // Setup
        let device1 = UnsafeMutableRawPointer(bitPattern: 0x1234)!
        mockFramework.mockDevices = [device1]
        monitor.start()

        // Stop
        monitor.stop()

        XCTAssertTrue(mockFramework.unregisterCallbackCalled)
        XCTAssertTrue(mockFramework.stopDeviceCalled)
        // Verify stopped device is correct
        XCTAssertEqual(mockFramework.lastStoppedDevice, device1)
    }

    func testStart_AlreadyRunning_DoesNothing() {
        let device1 = UnsafeMutableRawPointer(bitPattern: 0x1234)!
        mockFramework.mockDevices = [device1]
        monitor.start()

        // Reset counters
        mockFramework.reset()

        // Start again
        monitor.start()

        // Should not have called anything
        XCTAssertFalse(mockFramework.getAllDevicesCalled)
        XCTAssertEqual(mockFramework.registerCallbackCount, 0)
    }
}

// MARK: - Mocks

class MockMultitouchFramework: MultitouchFrameworkProtocol {

    var isAvailable: Bool = true

    var mockDevices: [MTDeviceRef] = []
    var mockDefaultDevice: MTDeviceRef?

    // Tracking calls
    var getAllDevicesCalled = false
    var getDefaultDeviceCalled = false
    var startDeviceCalled = false
    var stopDeviceCalled = false
    var registerCallbackCount = 0
    var unregisterCallbackCalled = false

    var registeredDevices = Set<MTDeviceRef>()
    var startedDevices = Set<MTDeviceRef>()
    var lastStoppedDevice: MTDeviceRef?

    func reset() {
        getAllDevicesCalled = false
        getDefaultDeviceCalled = false
        startDeviceCalled = false
        stopDeviceCalled = false
        registerCallbackCount = 0
        unregisterCallbackCalled = false
        registeredDevices.removeAll()
        startedDevices.removeAll()
        lastStoppedDevice = nil
    }

    func getAllDevices() -> CFArray? {
        getAllDevicesCalled = true
        if mockDevices.isEmpty { return nil }

        // Create CFArray
        let callbacks = UnsafeMutablePointer<CFArrayCallBacks>.allocate(capacity: 1)
        // We use kCFTypeArrayCallBacks but we need to mock it or pass defaults
        // Since we are mocking, we can just return a CFArray with our pointers
        // But CFArray expects objects or pointers.

        let values = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: mockDevices.count)
        for (i, dev) in mockDevices.enumerated() {
            values[i] = UnsafeRawPointer(dev)
        }

        let array = CFArrayCreate(kCFAllocatorDefault, values, CFIndex(mockDevices.count), nil)

        values.deallocate()
        callbacks.deallocate()

        return array
    }

    func getDefaultDevice() -> MTDeviceRef? {
        getDefaultDeviceCalled = true
        return mockDefaultDevice
    }

    func startDevice(_ device: MTDeviceRef, mode: Int32) {
        startDeviceCalled = true
        startedDevices.insert(device)
    }

    func stopDevice(_ device: MTDeviceRef) {
        stopDeviceCalled = true
        lastStoppedDevice = device
    }

    func registerContactFrameCallback(_ device: MTDeviceRef, _ callback: @escaping MTContactCallbackFunction) {
        registerCallbackCount += 1
        registeredDevices.insert(device)
    }

    func unregisterContactFrameCallback(_ device: MTDeviceRef, _ callback: MTContactCallbackFunction?) {
        unregisterCallbackCalled = true
    }
}
