import Foundation
import WebRTC

public struct VideoParameters {

    // 4:3 aspect ratio
    public static let presetQVGA43 = VideoParameters(
        dimensions: Dimensions(width: 240, height: 180),
        encoding: VideoEncoding(maxBitrate: 100_000, maxFps: 15)
    )
    public static let presetVGA43 = VideoParameters(
        dimensions: Dimensions(width: 480, height: 360),
        encoding: VideoEncoding(maxBitrate: 320_000, maxFps: 30)
    )
    public static let presetQHD43 = VideoParameters(
        dimensions: Dimensions(width: 720, height: 540),
        encoding: VideoEncoding(maxBitrate: 640_000, maxFps: 30)
    )
    public static let presetHD43 = VideoParameters(
        dimensions: Dimensions(width: 960, height: 720),
        encoding: VideoEncoding(maxBitrate: 2_000_000, maxFps: 30)
    )
    public static let presetFHD43 = VideoParameters(
        dimensions: Dimensions(width: 1440, height: 1080),
        encoding: VideoEncoding(maxBitrate: 3_200_000, maxFps: 30)
    )

    // 16:9 aspect ratio
    public static let presetQVGA169 = VideoParameters(
        dimensions: Dimensions(width: 320, height: 180),
        encoding: VideoEncoding(maxBitrate: 125_000, maxFps: 15)
    )
    public static let presetVGA169 = VideoParameters(
        dimensions: Dimensions(width: 640, height: 360),
        encoding: VideoEncoding(maxBitrate: 400_000, maxFps: 30)
    )
    public static let presetQHD169 = VideoParameters(
        dimensions: Dimensions(width: 960, height: 540),
        encoding: VideoEncoding(maxBitrate: 800_000, maxFps: 30)
    )
    public static let presetHD169 = VideoParameters(
        dimensions: Dimensions(width: 1280, height: 720),
        encoding: VideoEncoding(maxBitrate: 2_500_000, maxFps: 30)
    )
    public static let presetFHD169 = VideoParameters(
        dimensions: Dimensions(width: 1920, height: 1080),
        encoding: VideoEncoding(maxBitrate: 4_000_000, maxFps: 30)
    )

    public static let presets43 = [
        presetQVGA43, presetVGA43, presetQHD43, presetHD43, presetFHD43
    ]

    public static let presets169 = [
        presetQVGA169, presetVGA169, presetQHD169, presetHD169, presetFHD169
    ]

    public let dimensions: Dimensions
    public let encoding: VideoEncoding

    init(dimensions: Dimensions, encoding: VideoEncoding) {
        self.dimensions = dimensions
        self.encoding = encoding
    }
}
