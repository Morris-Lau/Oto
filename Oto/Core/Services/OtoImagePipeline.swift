import Foundation
import Nuke

public enum OtoImagePipeline {
    /// Configures the shared Nuke pipeline with disk data cache and display-friendly decompression.
    public static func bootstrap() {
        var configuration = ImagePipeline.Configuration.withDataCache(
            name: "works.storymusic.image-datacache",
            sizeLimit: 300 * 1024 * 1024
        )
        configuration.isUsingPrepareForDisplay = true
        ImagePipeline.shared = ImagePipeline(configuration: configuration)
    }
}
