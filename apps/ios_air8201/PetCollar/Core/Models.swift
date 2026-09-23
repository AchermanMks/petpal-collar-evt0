import Foundation

struct APIEnvelope<T: Decodable>: Decodable {
    let ok: Bool
    let data: T?
    let error: APIErrorBody?
}

struct APIErrorBody: Decodable {
    let code: String
    let message: String
    let hint: String?
}

struct Health: Decodable, Equatable {
    let status: String
    let startedAt: Double
    let uptimeSec: Double

    enum CodingKeys: String, CodingKey {
        case status
        case startedAt = "started_at"
        case uptimeSec = "uptime_sec"
    }

    var isReady: Bool { status == "ready" }
    var isWarming: Bool { status == "warming" || status == "loading" }
}

struct SystemInfo: Decodable, Equatable {
    let version: String
    let gpu: GPU
    let models: Models
    let video: Video
    let room: Room
    let capabilities: Capabilities

    struct GPU: Decodable, Equatable {
        let name: String
        let vramGb: Double?
        let cuda: String?
        enum CodingKeys: String, CodingKey {
            case name
            case vramGb = "vram_gb"
            case cuda
        }
    }

    struct Models: Decodable, Equatable {
        let detector: String
        let tracker: String
        let vlm: String
    }

    struct Video: Decodable, Equatable {
        let source: String
        let resolution: Resolution
        let fps: Int
    }

    struct Resolution: Decodable, Equatable {
        let width: Int
        let height: Int
    }

    struct Room: Decodable, Equatable {
        let calibrated: Bool
        let dimensionsM: Dimensions
        let origin: String?
        enum CodingKeys: String, CodingKey {
            case calibrated
            case dimensionsM = "dimensions_m"
            case origin
        }
    }

    struct Dimensions: Decodable, Equatable {
        let width: Double
        let depth: Double
    }

    struct Capabilities: Decodable, Equatable {
        let ptz: Bool
        let vlm: Bool
        let sseEvents: Bool
        let collar: Bool
        enum CodingKeys: String, CodingKey {
            case ptz, vlm, collar
            case sseEvents = "sse_events"
        }
    }
}

struct DetectionsResponse: Decodable {
    let count: Int
    let averageConfidence: Double
    let recent: [Detection]

    enum CodingKeys: String, CodingKey {
        case count, recent
        case averageConfidence = "average_confidence"
    }
}

struct Detection: Decodable, Identifiable, Equatable {
    let klass: String
    let confidence: Double
    let bbox: [Int]
    let center: [Int]
    let area: Double
    let aspectRatio: Double
    let trackId: Int?
    let physicalCoords: PhysicalCoords
    let qualityScore: Double
    let detectionType: String
    let ts: Double

    var id: String { "\(trackId.map(String.init) ?? "x")@\(ts)" }
    var trackIdLabel: String { trackId.map { "#\($0)" } ?? "#?" }

    enum CodingKeys: String, CodingKey {
        case klass = "class"
        case confidence, bbox, center, area, ts
        case aspectRatio = "aspect_ratio"
        case trackId = "track_id"
        case physicalCoords = "physical_coords"
        case qualityScore = "quality_score"
        case detectionType = "detection_type"
    }

    struct PhysicalCoords: Decodable, Equatable {
        let x: Double
        let y: Double
        let z: Double
    }

    var isStale: Bool {
        Date().timeIntervalSince1970 - ts > 0.3
    }
}

struct VLMResponse: Decodable, Equatable {
    let analysis: VLMAnalysis
    let updatedAt: Double?

    enum CodingKeys: String, CodingKey {
        case analysis
        case updatedAt = "updated_at"
    }
}

struct VLMAnalysis: Decodable, Equatable {
    let scene: String
    let behavior: String

    var sceneIsPlaceholder: Bool { scene.hasPrefix("正在分析") }
    var behaviorIsPlaceholder: Bool { behavior.hasPrefix("正在分析") }
}

struct Stats: Decodable, Equatable {
    let catDetections: Int
    let dogDetections: Int
    let uniqueCats: Int
    let uniqueDogs: Int
    let totalDetections: Int
    let totalFrames: Int
    let running: Bool

    enum CodingKeys: String, CodingKey {
        case running
        case catDetections = "cat_detections"
        case dogDetections = "dog_detections"
        case uniqueCats = "unique_cats"
        case uniqueDogs = "unique_dogs"
        case totalDetections = "total_detections"
        case totalFrames = "total_frames"
    }
}


struct FeedingEvent: Decodable, Equatable, Identifiable, Sendable {
    let startTs: Double
    let endTs: Double
    let durationSec: Double

    var id: Double { startTs }
    var start: Date { Date(timeIntervalSince1970: startTs) }
    var end: Date { Date(timeIntervalSince1970: endTs) }

    enum CodingKeys: String, CodingKey {
        case startTs = "start_ts"
        case endTs = "end_ts"
        case durationSec = "duration_sec"
    }
}

struct FeedingSummary: Decodable, Equatable, Sendable {
    let todayCount: Int
    let totalCount: Int
    let inProgress: Bool
    let currentDurationSec: Double
    let recentEvents: [FeedingEvent]

    enum CodingKeys: String, CodingKey {
        case todayCount = "today_count"
        case totalCount = "total_count"
        case inProgress = "in_progress"
        case currentDurationSec = "current_duration_sec"
        case recentEvents = "recent_events"
    }
}


struct ActivityBucket: Decodable, Equatable, Identifiable, Sendable {
    let startTs: Double
    let meters: Double

    var id: Double { startTs }
    var start: Date { Date(timeIntervalSince1970: startTs) }

    enum CodingKeys: String, CodingKey {
        case startTs = "start_ts"
        case meters
    }
}

struct ActivitySummary: Decodable, Equatable, Sendable {
    let bucketSec: Int
    let lastHourMeters: Double
    let todayMeters: Double
    let recentBuckets: [ActivityBucket]

    enum CodingKeys: String, CodingKey {
        case bucketSec = "bucket_sec"
        case lastHourMeters = "last_hour_meters"
        case todayMeters = "today_meters"
        case recentBuckets = "recent_buckets"
    }
}
