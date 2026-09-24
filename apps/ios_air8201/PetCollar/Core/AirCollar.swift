import Foundation

// No views here: keep the original PetPal UI and ESPClient method signatures.
struct AirDevice: Decodable, Sendable {
    let device_id: String
    let online: Bool
    let telemetry: AirTelemetry?
    let legacy_status: ESPStatus?
}
struct AirTelemetry: Decodable, Sendable {
    struct Position: Decodable, Sendable {
        let lat: Double; let lng: Double; let source: String
        let accuracy_m: Double?; let fix_age_s: Int?; let sats: Int?
        let speed_kmh: Double?; let alt_m: Double?
    }
    struct LastFix: Decodable, Sendable { let ts: Double; let lat: Double; let lng: Double; let source: String }
    struct Outputs: Decodable, Sendable { let motor_on: Bool?; let led_on: Bool? }
    let position: Position?
    let last_fix: LastFix?
    let outputs: Outputs?
}
struct AirAck: Decodable, Sendable {
    let id: String; let status: String; let reason: String?
}
enum AirValue: Encodable, Sendable {
    case string(String), number(Double), bool(Bool)
    func encode(to encoder: Encoder) throws {
        var c=encoder.singleValueContainer()
        switch self { case .string(let s): try c.encode(s); case .number(let n): try c.encode(n); case .bool(let b): try c.encode(b) }
    }
}
struct AirCommand: Encodable, Sendable {
    let id: String; let device_id: String; let issued_at: Int; let expires_at: Int; let type: String
    let args: [String:AirValue]
}
enum AirError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? { switch self { case .unavailable(let s): return s } }
}
struct AirClient: Sendable {
    let baseURL: URL
    let token: String
    let deviceID: String
    init(address: String,token: String,deviceID: String) throws {
        guard let u=URL(string:address),let host=u.host,u.user==nil,u.password==nil,u.query==nil,u.fragment==nil else {
            throw AirError.unavailable("Air8201G 服务地址格式不正确")
        }
        let parts=host.split(separator:".",omittingEmptySubsequences:false)
        let octets=parts.compactMap { Int($0) }
        let privateIP=parts.count==4 && octets.count==4 && octets.allSatisfy { (0...255).contains($0) } &&
            (octets[0]==10 || (octets[0]==192 && octets[1]==168) || (octets[0]==172 && (16...31).contains(octets[1])))
        let local=host=="localhost" || host=="127.0.0.1" || privateIP
        guard u.scheme=="https" || (u.scheme=="http" && local) else {
            throw AirError.unavailable("远程硬件服务必须使用 HTTPS；HTTP 仅限本机/私有局域网台架")
        }
        guard (1...64).contains(deviceID.count),deviceID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0=="-" || $0=="_") }) else {
            throw AirError.unavailable("项圈设备编号未配置")
        }
        baseURL=u; self.token=token; self.deviceID=deviceID
    }
    private func request(_ suffix: String,body: Data?=nil,timeout: TimeInterval=10) async throws -> Data {
        var u=baseURL.appendingPathComponent("v1/devices").appendingPathComponent(deviceID)
        if let q=suffix.firstIndex(of:"?") { u=u.appendingPathComponent(String(suffix[..<q])); u=URL(string:u.absoluteString+String(suffix[q...])) ?? u }
        else { u=u.appendingPathComponent(suffix) }
        var r=URLRequest(url:u); r.timeoutInterval=timeout
        if !token.isEmpty { r.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization") }
        if let body { r.httpMethod="POST"; r.httpBody=body; r.setValue("application/json",forHTTPHeaderField:"Content-Type") }
        // This session has no compatibility URLProtocol: no recursion/old-host requests.
        let (data,response)=try await URLSession.shared.data(for:r)
        guard let h=response as? HTTPURLResponse,(200..<300).contains(h.statusCode) else {
            let parsed=try? JSONSerialization.jsonObject(with:data) as? [String:Any]
            throw AirError.unavailable(parsed?["error"] as? String ?? "Air8201G 服务未连接")
        }
        return data
    }
    func snapshot() async throws -> AirDevice {
        let d=try JSONDecoder().decode(AirDevice.self,from:await request("snapshot"))
        guard d.device_id==deviceID,d.online else { throw AirError.unavailable("项圈离线或设备编号不匹配") }
        return d
    }
    func cameraFrame() async throws -> Data {
        let d=try await request("camera/frame",timeout:40)
        guard (4...262144).contains(d.count),d.prefix(2)==Data([0xff,0xd8]),d.suffix(2)==Data([0xff,0xd9]) else {
            throw AirError.unavailable("开发板返回的 JPEG 画面无效")
        }
        return d
    }
    /// Raw snapshot / 24 h history for the collar data panel. Returned as-is from the service: the panel shows
    /// only fields that are present and never fills in placeholders.
    func rawSnapshot() async throws -> [String:Any] {
        guard let o=try JSONSerialization.jsonObject(with:await request("snapshot")) as? [String:Any] else { throw AirError.unavailable("状态数据格式不正确") }
        return o
    }
    func history(hours: Int) async -> [[String:Any]]? {
        do {
            let d=try await request("history?hours=\(hours)")
            return (try JSONSerialization.jsonObject(with:d) as? [String:Any])?["samples"] as? [[String:Any]]
        } catch { return nil }   // USB bench bridge has no history endpoint: the panel says so instead of drawing an empty chart
    }
    func command(_ type: String,args: [String:AirValue]) async throws {
        let now=Int(Date().timeIntervalSince1970)
        let c=AirCommand(id:UUID().uuidString,device_id:deviceID,issued_at:now,expires_at:now+120,type:type,args:args)
        var a=try JSONDecoder().decode(AirAck.self,from:await request("commands",body:JSONEncoder().encode(c)))
        for attempt in 0...35 {
            guard a.id==c.id else { throw AirError.unavailable("开发板回执编号不匹配") }
            if a.status=="executed" { return }
            if a.status != "accepted" { throw AirError.unavailable("开发板未执行：\(a.reason ?? a.status)") }
            if attempt==35 { break }
            try await Task.sleep(for:.seconds(2))
            a=try JSONDecoder().decode(AirAck.self,from:await request("commands/\(c.id)"))
        }
        throw AirError.unavailable("未确认执行：回执超时，不会自动重发新的动作")
    }
}

/// GNSS receivers output WGS-84. Map tiles served in mainland China (Apple Maps included) use GCJ-02, and CoreLocation
/// already returns GCJ-02 there, so a raw WGS-84 collar fix drawn on the map lands a few hundred metres off while the
/// phone's own dot is right. Standard public WGS-84 -> GCJ-02 transform; identity outside China.
enum ChinaGeo {
    static func outOfChina(_ lat: Double,_ lng: Double) -> Bool { !(lng > 72.004 && lng < 137.8347 && lat > 0.8293 && lat < 55.8271) }
    static func wgs84ToGcj02(lat: Double, lng: Double) -> (lat: Double, lng: Double) {
        if outOfChina(lat, lng) { return (lat, lng) }
        let a = 6378245.0, ee = 0.00669342162296594323
        var dLat = transformLat(lng - 105.0, lat - 35.0), dLng = transformLng(lng - 105.0, lat - 35.0)
        let radLat = lat / 180.0 * .pi
        var magic = sin(radLat); magic = 1 - ee * magic * magic
        let sqrtMagic = sqrt(magic)
        dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * .pi)
        dLng = (dLng * 180.0) / (a / sqrtMagic * cos(radLat) * .pi)
        return (lat + dLat, lng + dLng)
    }
    private static func transformLat(_ x: Double, _ y: Double) -> Double {
        var r = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        r += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        r += (20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0
        r += (160.0 * sin(y / 12.0 * .pi) + 320.0 * sin(y * .pi / 30.0)) * 2.0 / 3.0
        return r
    }
    private static func transformLng(_ x: Double, _ y: Double) -> Double {
        var r = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        r += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        r += (20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0
        r += (150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0
        return r
    }
}

enum AirHardwareBackend {
    /// Client for views that talk to the Air service directly (no legacy path to translate).
    static func defaultClient() throws -> AirClient { try client(for: URLRequest(url: URL(string:"http://esp32-led.local/")!)) }
    static func client(for request: URLRequest) throws -> AirClient {
        guard let url=request.url else { throw AirError.unavailable("缺少硬件地址") }
        // Launch environment first (simctl / Xcode scheme), then persisted settings (UserDefaults, survives launching from
        // the home screen), then the original address box. Token is never written into source.
        let env=ProcessInfo.processInfo.environment
        let defaults=UserDefaults.standard
        func setting(_ key: String) -> String? {
            if let v=env[key],!v.isEmpty { return v }
            if let v=defaults.string(forKey:key),!v.isEmpty { return v }
            return nil
        }
        let address: String
        if let configured=setting("PETPAL_AIR_SERVICE_URL") { address=configured }
        else if url.host=="esp32-led.local" {
            #if targetEnvironment(simulator)
            address="http://127.0.0.1:8210"
            #else
            throw AirError.unavailable("请在原地址输入框填入 Air8201G 的可达服务地址；默认 ESP32 地址不再连接旧板")
            #endif
        } else {
            var c=URLComponents(url:url,resolvingAgainstBaseURL:false)
            c?.path=""; c?.query=nil; c?.fragment=nil
            guard let s=c?.url?.absoluteString else { throw AirError.unavailable("硬件服务地址格式不正确") }
            address=s
        }
        return try AirClient(address:address,token:setting("PETPAL_BRIDGE_TOKEN") ?? "",deviceID:setting("PETPAL_AIR_DEVICE_ID") ?? "collar-evt-001")
    }
    static func response(to request: URLRequest) async throws -> Data {
        guard let url=request.url else { throw AirError.unavailable("缺少请求地址") }
        let path=url.path
        // Retain original controls, reject unimplemented hardware through their existing errors.
        if path.hasPrefix("/arc/") && path != "/arc/stop" {
            throw AirError.unavailable("Air8201G 宠物项圈固件不提供电弧/高压输出")
        }
        // Tone / self-test / built-in sound go to firmware BUZZ (docs/16 §7.1). File management has no device-side store yet.
        if ["/speaker/files","/speaker/play","/speaker/upload","/speaker/delete"].contains(path) {
            throw AirError.unavailable("Air8201G 声音文件管理尚未接入，未执行文件操作")
        }
        if path=="/led/rgb" { throw AirError.unavailable("RGB 外设尚未接入；板载单色指示灯不能冒充 RGB 灯") }
        let c=try client(for:request)
        let params=URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems ?? []
        func integer(_ key: String,_ fallback: Int) throws -> Int {
            guard let value=params.first(where:{$0.name==key})?.value else { return fallback }
            guard let n=Int(value) else { throw AirError.unavailable("无效硬件参数：\(key)") }; return n
        }
        switch path {
        case "/capture": return try await c.cameraFrame()
        case "/led/on": try await c.command("LED",args:["pattern":.string("on"),"duration_s":.number(300)])
        case "/led/off": try await c.command("LED",args:["pattern":.string("off"),"duration_s":.number(0)])
        case "/led/breathe": try await c.command("LED",args:["pattern":.string("breathe"),"duration_s":.number(300)])
        case "/motor/stop", "/speaker/stop", "/arc/stop": try await c.command("STOP",args:[:])
        case "/speaker/beep":
            // Firmware clamps volume/duration to its safety limits and reports applied_args; out-of-range input is rejected there.
            let freq=try integer("freq",1000),duration=try integer("duration",2000),volume=try integer("volume",80)
            try await c.command("BUZZ",args:["kind":.string("beep"),"freq_hz":.number(Double(freq)),"duration_ms":.number(Double(duration)),"volume":.number(Double(volume))])
        case "/speaker/test": try await c.command("BUZZ",args:["kind":.string("test")])
        case "/speaker/meow":
            // No real meow asset on the board yet: firmware answers rejected/unsupported rather than playing a substitute.
            try await c.command("BUZZ",args:["kind":.string("meow"),"volume":.number(Double(try integer("volume",80)))])
        case "/motor/vibrate":
            let duration=try integer("duration",500),intensity=try integer("intensity",255)
            guard (50...500).contains(duration) else { throw AirError.unavailable("Air8201G 震动台架上限500ms；不伪报按原界面长时参数执行") }
            if intensity==0 { try await c.command("STOP",args:[:]) }
            else {
                guard intensity==255 else { throw AirError.unavailable("可调强度驱动尚未接入，不能把所选强度当作满功率执行") }
                try await c.command("VIBRATE",args:["duration_ms":.number(Double(duration)),"count":.number(1)])
            }
        case "/motor/status":
            guard let on=try await c.snapshot().telemetry?.outputs?.motor_on else { throw AirError.unavailable("尚无真实马达状态") }
            return try JSONSerialization.data(withJSONObject:["on":on])
        case "/api/status":
            guard let status=try await c.snapshot().legacy_status else { throw AirError.unavailable("完整设备诊断数据尚未接入，不用虚构 ESP32/Wi-Fi/温度数据填充原状态页") }
            return try JSONEncoder().encode(status)
        case "/api/gps":
            let d=try await c.snapshot()
            let p=d.telemetry?.position
            let valid=p != nil && p?.source=="gnss" && (p?.fix_age_s ?? Int.max)<=120
            if let p {
                guard p.lat.isFinite,p.lng.isFinite,abs(p.lat)<=90,abs(p.lng)<=180,
                      p.alt_m != nil,p.speed_kmh != nil,p.sats != nil,p.fix_age_s != nil else { throw AirError.unavailable("GNSS 原始数据尚不完整") }
            }
            let ts=d.telemetry?.last_fix?.ts ?? 0
            let date=ts>=1700000000 ? ISO8601DateFormatter().string(from:Date(timeIntervalSince1970:ts)) : ""
            // The map page draws this on GCJ-02 tiles in China: convert here, keep WGS-84 everywhere else (data panel, cloud).
            let shown = p.map { ChinaGeo.wgs84ToGcj02(lat: $0.lat, lng: $0.lng) }
            return try JSONSerialization.data(withJSONObject:["fix":valid,"lat":shown?.lat ?? 0,"lng":shown?.lng ?? 0,
                "alt":p?.alt_m ?? 0,"speed_kmh":p?.speed_kmh ?? 0,"sats":p?.sats ?? 0,
                "age_ms":p.map { min(4294967295,max(0,$0.fix_age_s ?? 4294967)*1000) } ?? 4294967295,"datetime":date])
        default: throw AirError.unavailable("Air8201G 尚未接入此硬件接口：\(path)")
        }
        return Data("OK".utf8) // Only emitted after terminal 'executed', never just accepted.
    }
}

final class AirHardwareProtocol: URLProtocol, @unchecked Sendable {
    private var operation: Task<Void,Never>?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        operation=Task { [weak self] in
            guard let self else { return }
            do {
                if self.request.url?.path=="/stream" {
                    try await self.streamCamera()
                    return
                }
                let data=try await AirHardwareBackend.response(to:self.request)
                guard !Task.isCancelled,let url=self.request.url else { return }
                let response=HTTPURLResponse(url:url,statusCode:200,httpVersion:"HTTP/1.1",headerFields:["Cache-Control":"no-store","Content-Type":url.path=="/capture" ? "image/jpeg" : "text/plain"] )!
                self.client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
                self.client?.urlProtocol(self,didLoad:data)
                self.client?.urlProtocolDidFinishLoading(self)
            } catch {
                if !Task.isCancelled { self.client?.urlProtocol(self,didFailWithError:error) }
            }
        }
    }
    private func streamCamera() async throws {
        let hardware=try AirHardwareBackend.client(for:request)
        var frame=try await hardware.cameraFrame() // Never announce a live stream without a fresh frame.
        guard !Task.isCancelled,let url=request.url else { return }
        let response=HTTPURLResponse(url:url,statusCode:200,httpVersion:"HTTP/1.1",headerFields:[
            "Content-Type":"multipart/x-mixed-replace; boundary=petpal-air-frame","Cache-Control":"no-store"])!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        while !Task.isCancelled {
            var part=Data("--petpal-air-frame\r\nContent-Type: image/jpeg\r\nContent-Length: \(frame.count)\r\n\r\n".utf8)
            part.append(frame); part.append(Data("\r\n".utf8))
            client?.urlProtocol(self,didLoad:part)
            try await Task.sleep(for:.milliseconds(250))
            frame=try await hardware.cameraFrame()
            try Task.checkCancellation()
        }
    }
    override func stopLoading() { operation?.cancel(); operation=nil }
}
