import Foundation
import Promises
import WebRTC

public class LiveKit {
    static let queue = DispatchQueue(label: "lk_queue")
    public static func connect(options: ConnectOptions, delegate: RoomDelegate? = nil) -> Promise<Room> {
        let room = Room(connectOptions: options, delegate: delegate)
        return room.connect()
    }
    
    public static var isDebug: Bool {
        set {
            logger.isDebug = newValue
        }
        
        get {
            return logger.isDebug
        }
    }
}
