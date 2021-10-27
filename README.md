# iOS Swift SDK for LiveKit

# Why am I fork LiveKit?
- Because I need support iOS 10 for my project.
- Many bugs critical need fix, I hope I solved it for you.
- You have issue please not report here\nso you can report in root repo for community can see and fix it together.

Official Client SDK for [LiveKit](https://github.com/livekit/livekit-server). Easily add video & audio capabilities to your iOS apps.

Example: [LiveKit-iOS-Example](https://github.com/baveku/LiveKit-iOS-Example)
## Docs

Docs and guides at [https://docs.livekit.io](https://docs.livekit.io)

## Installation

LiveKit for iOS is available as a Swift Package, Carthage, Cocoapods.

### Package.swift

Add the dependency and also to your target

```swift title="Package.swift"
let package = Package(
  ...
  dependencies: [
    .package(name: "LiveKit", url: "https://github.com/baveku/LiveKit.git", .upToNextMajor("version")),
  ],
  targets: [
    .target(
      name: "MyApp",
      dependencies: ["LiveKit"]
    )
  ]
}
```

### Carthage
```bash
github "baveku/LiveKit"
```

### Cocoapods
```ruby
pod "LiveKit", :git => "htttps://github.com/baveku/LiveKit"
#... more

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['ENABLE_BITCODE'] = 'NO'
    end
  end
end
```

### XCode
LiveKit need to disable Bitcode.
You can go to Xcode => Project => Buid setting => search bitcode and disable it.

## Usage

LiveKit provides an UIKit based `VideoView` class that renders video tracks. Subscribed audio tracks are automatically played.

```swift
import LiveKit
import UIKit

class RoomViewController: UIViewController {
    var room: Room!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        let url: String = "ws://your_host"
        let token: String = "your_jwt_token"

        room = Room(options: ConnectOptions(url: url, token: token), delegate: self)
        room.connect()
    }

    func attachVideo(track: VideoTrack, participant: Participant) {
      let videoView = VideoView(frame: .zero)
      // find destination view
      ...
      target.addSubview(videoView)
      track.addRenderer(videoView.renderer)
    }
}

extension RoomViewController: RoomDelegate {
    func didConnect(room: Room) {
        guard let localParticipant = room.localParticipant else {
            return
        }

        // perform work in the background, to not block WebRTC threads
        DispatchQueue.global(qos: .background).async {
          do {
              let videoTrack = try LocalVideoTrack.createTrack(name: "localVideo")
              _ = localParticipant.publishVideoTrack(track: videoTrack)
              let audioTrack = LocalAudioTrack.createTrack(name: "localAudio")
              _ = localParticipant.publishAudioTrack(track: audioTrack)
          } catch {
              // error publishing
          }
        }

        // attach video view
        attachVideo(videoTrack, localParticipant)
    }

    func didSubscribe(track: Track, publication _: RemoteTrackPublication, participant _: RemoteParticipant) {
        guard let videoTrack = track as? VideoTrack else {
          return
        }
        DispatchQueue.main.async {
            attachVideo(videoTrack, participant)
        }
    }
}
```
