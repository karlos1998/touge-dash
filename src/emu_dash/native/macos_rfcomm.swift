import Foundation
import IOBluetooth

final class RFCOMMReceiver: NSObject, IOBluetoothRFCOMMChannelDelegate {
    var closed = false

    func rfcommChannelData(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!,
        data dataPointer: UnsafeMutableRawPointer!,
        length dataLength: Int
    ) {
        guard let dataPointer, dataLength > 0 else { return }
        FileHandle.standardOutput.write(Data(bytes: dataPointer, count: dataLength))
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        closed = true
    }
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

guard CommandLine.arguments.count >= 2 else {
    fail("Usage: emu-rfcomm-macos MAC [CHANNEL]")
}

let address = CommandLine.arguments[1]
let channelNumber = CommandLine.arguments.count >= 3 ? Int(CommandLine.arguments[2]) ?? 1 : 1
guard (1...30).contains(channelNumber) else { fail("Invalid RFCOMM channel") }
guard let device = IOBluetoothDevice(addressString: address) else { fail("Invalid Bluetooth address: \(address)") }
guard device.isPaired() else { fail("Bluetooth device is not paired: \(address)") }

let receiver = RFCOMMReceiver()
var channel: IOBluetoothRFCOMMChannel?
let result = device.openRFCOMMChannelSync(
    &channel,
    withChannelID: BluetoothRFCOMMChannelID(channelNumber),
    delegate: receiver
)
guard result == kIOReturnSuccess, let channel else {
    fail("Cannot open RFCOMM channel \(channelNumber), IOReturn=\(result)")
}

FileHandle.standardError.write(Data("Connected to \(device.nameOrAddress ?? address), RFCOMM channel \(channelNumber)\n".utf8))
while !receiver.closed {
    RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.25))
}
channel.close()
