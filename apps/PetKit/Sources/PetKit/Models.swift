import Foundation

// 后端 :5008 的数据模型（REST 轮询）。纯 Foundation，四端共享。
// 与原 ios_app / mac_app 各自的 Models.swift 同构，抽到此处去重。

public struct APIEnvelope<T: Decodable>: Decodable {
    public let ok: Bool
    public let data: T?
    public let error: APIErrorBody?
}

public struct APIErrorBody: Decodable {
    public let code: String
    public let message: String
    public let hint: String?
}

public struct Health: Decodable, Equatable, Sendable {
    public let status: String
    public let startedAt: Double
    public let uptimeSec: Double

    enum CodingKeys: String, CodingKey {
        case status
        case startedAt = "started_at"
        case uptimeSec = "uptime_sec"
    }

    public var isReady: Bool { status == "ready" }
    public var isWarming: Bool { status == "warming" || status == "loading" }
}

public struct SystemInfo: Decodable, Equatable, Sendable {
    public let version: String
    public let gpu: GPU
    public let models: Models
    public let video: Video
    public let room: Room
    public let capabilities: Capabilities

    public struct GPU: Decodable, Equatable, Sendable {
        public let name: String
        public let vramGb: Int?
        public let cuda: String?
        enum CodingKeys: String, CodingKey {
            case name
            case vramGb = "vram_gb"
            case cuda
        }
    }

    public struct Models: Decodable, Equatable, Sendable {
        public let detector: String
        public let tracker: String
        public let vlm: String
    }

    public struct Video: Decodable, Equatable, Sendable {
        public let source: String
        public let resolution: Resolution
        public let fps: Int
    }

    public struct Resolution: Decodable, Equatable, Sendable {
        public let width: Int
        public let height: Int
    }

    public struct Room: Decodable, Equatable, Sendable {
        public let calibrated: Bool
        public let dimensionsM: Dimensions
        public let origin: String?
        enum CodingKeys: String, CodingKey {
            case calibrated
            case dimensionsM = "dimensions_m"
            case origin
        }
    }

    public struct Dimensions: Decodable, Equatable, Sendable {
        public let width: Double
        public let depth: Double
    }

    public struct Capabilities: Decodable, Equatable, Sendable {
        public let ptz: Bool
        public let vlm: Bool
        public let sseEvents: Bool
        public let collar: Bool
        enum CodingKeys: String, CodingKey {
            case ptz, vlm, collar
            case sseEvents = "sse_events"
        }
    }
}

public struct DetectionsResponse: Decodable, Sendable {
    public let count: Int
    public let averageConfidence: Double
    public let recent: [Detection]

    enum CodingKeys: String, CodingKey {
        case count, recent
        case averageConfidence = "average_confidence"
    }
}

public struct Detection: Decodable, Identifiable, Equatable, Sendable {
    public let klass: String
    public let confidence: Double
    public let bbox: [Int]
    public let center: [Int]
    public let area: Int
    public let aspectRatio: Double
    public let trackId: Int
    public let physicalCoords: PhysicalCoords
    public let qualityScore: Double
    public let detectionType: String
    public let ts: Double

    public var id: Int { trackId }

    enum CodingKeys: String, CodingKey {
        case klass = "class"
        case confidence, bbox, center, area, ts
        case aspectRatio = "aspect_ratio"
        case trackId = "track_id"
        case physicalCoords = "physical_coords"
        case qualityScore = "quality_score"
        case detectionType = "detection_type"
    }

    public struct PhysicalCoords: Decodable, Equatable, Sendable {
        public let x: Double
        public let y: Double
        public let z: Double
    }
}

public struct VLMResponse: Decodable, Equatable, Sendable {
    public let analysis: VLMAnalysis
}

public struct VLMAnalysis: Decodable, Equatable, Sendable {
    public let scene: String
    public let behavior: String

    public var sceneIsPlaceholder: Bool { scene.hasPrefix("正在分析") }
    public var behaviorIsPlaceholder: Bool { behavior.hasPrefix("正在分析") }
}

public struct Stats: Decodable, Equatable, Sendable {
    public let catDetections: Int
    public let dogDetections: Int
    public let uniqueCats: Int
    public let uniqueDogs: Int
    public let totalDetections: Int
    public let totalFrames: Int
    public let running: Bool

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

public struct FeedingEvent: Decodable, Equatable, Identifiable, Sendable {
    public let startTs: Double
    public let endTs: Double
    public let durationSec: Double

    public var id: Double { startTs }
    public var start: Date { Date(timeIntervalSince1970: startTs) }
    public var end: Date { Date(timeIntervalSince1970: endTs) }

    enum CodingKeys: String, CodingKey {
        case startTs = "start_ts"
        case endTs = "end_ts"
        case durationSec = "duration_sec"
    }
}

public struct FeedingSummary: Decodable, Equatable, Sendable {
    public let todayCount: Int
    public let totalCount: Int
    public let inProgress: Bool
    public let currentDurationSec: Double
    public let recentEvents: [FeedingEvent]

    enum CodingKeys: String, CodingKey {
        case todayCount = "today_count"
        case totalCount = "total_count"
        case inProgress = "in_progress"
        case currentDurationSec = "current_duration_sec"
        case recentEvents = "recent_events"
    }
}

public struct ActivityBucket: Decodable, Equatable, Identifiable, Sendable {
    public let startTs: Double
    public let meters: Double

    public var id: Double { startTs }
    public var start: Date { Date(timeIntervalSince1970: startTs) }

    enum CodingKeys: String, CodingKey {
        case startTs = "start_ts"
        case meters
    }
}

public struct ActivitySummary: Decodable, Equatable, Sendable {
    public let bucketSec: Int
    public let lastHourMeters: Double
    public let todayMeters: Double
    public let recentBuckets: [ActivityBucket]

    enum CodingKeys: String, CodingKey {
        case bucketSec = "bucket_sec"
        case lastHourMeters = "last_hour_meters"
        case todayMeters = "today_meters"
        case recentBuckets = "recent_buckets"
    }
}
