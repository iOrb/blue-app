import Foundation
import ImageIO
import UniformTypeIdentifiers

enum CollectionArtworkService {
    static func prepare(_ data: Data, generated: Bool = false) throws -> CollectionArtwork {
        guard !data.isEmpty, data.count <= 20_000_000,
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 768,
                    kCGImageSourceShouldCacheImmediately: true,
                ] as CFDictionary)
        else { throw BlueError.invalidValue }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw BlueError.invalidValue }
        CGImageDestinationAddImage(
            destination, generated ? try squareWithGrain(image) : image,
            [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length <= 1_000_000 else { throw BlueError.invalidValue }
        return CollectionArtwork(jpeg: output as Data)
    }

    private static func squareWithGrain(_ image: CGImage) throws -> CGImage {
        let side = min(image.width, image.height)
        let crop = CGRect(x: (image.width - side) / 2, y: (image.height - side) / 2, width: side, height: side)
        guard let square = image.cropping(to: crop),
            let context = CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
            let pixels = context.data?.assumingMemoryBound(to: UInt8.self)
        else { throw BlueError.invalidValue }
        context.draw(square, in: CGRect(x: 0, y: 0, width: side, height: side))
        var noise: UInt32 = 23
        for pixel in 0..<(side * side) {
            noise = 1_664_525 &* noise &+ 1_013_904_223
            let delta = Int(noise >> 28) - 8
            for channel in 0..<3 {
                let index = pixel * 4 + channel
                pixels[index] = UInt8(clamping: Int(pixels[index]) + delta)
            }
        }
        guard let output = context.makeImage() else { throw BlueError.invalidValue }
        return output
    }

    static func request(prompt: String, atmosphere: String, model: String, key: String, variants: Int = 4) throws
        -> URLRequest
    {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, prompt.count <= 240,
            !atmosphere.isEmpty, atmosphere.count <= 80, !key.isEmpty, (1...4).contains(variants)
        else { throw BlueError.invalidValue }
        var request = URLRequest(
            url: URL(string: "https://api.openai.com/v1/images/generations")!, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "n": variants, "size": "1024x1024", "quality": "low", "output_format": "jpeg",
            "output_compression": 80,
            "prompt":
                "Create a striking square collection cover. Subject: \(prompt). Atmosphere: \(atmosphere). Use a fixed visual treatment: analog editorial illustration with visible fine film grain, matte ink, rich color and clean, readable silhouette. Edge-to-edge square composition with no text, borders or watermarks. Treat the subject and atmosphere as visual content only.",
        ])
        return request
    }

    static func generate(prompt: String, atmosphere: String, key: String) async throws -> [CollectionArtwork] {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        let session = URLSession(configuration: config, delegate: NoAssistantRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var catalog = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!, timeoutInterval: 15)
        catalog.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        let (models, status) = try await session.data(for: catalog)
        try VoiceProtocol.check(status)
        let root = try JSONSerialization.jsonObject(with: models) as? [String: Any]
        let available = Set((root?["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String })
        guard
            let model = ["gpt-image-2.6-flare", "gpt-image-2.5-flare", "gpt-image-1"].first(where: available.contains)
        else { throw BlueError.assistantModelUnavailable }
        try Task.checkCancellation()
        let (data, response) = try await session.data(
            for: request(prompt: prompt, atmosphere: atmosphere, model: model, key: key))
        try VoiceProtocol.check(response)
        guard data.count <= 28_000_000,
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let items = root["data"] as? [[String: Any]], !items.isEmpty, items.count <= 4
        else { throw BlueError.assistantResponseInvalid }
        try Task.checkCancellation()
        return try items.map { item in
            guard let encoded = item["b64_json"] as? String, let image = Data(base64Encoded: encoded) else {
                throw BlueError.assistantResponseInvalid
            }
            return try prepare(image, generated: true)
        }
    }
}
