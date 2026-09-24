import Foundation

final class StreamProbe: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    var continuation: CheckedContinuation<Void,Error>?
    var session: URLSession?
    var frames=0
    var finished=false
    func start(_ c: CheckedContinuation<Void,Error>) {
        continuation=c
        let config=URLSessionConfiguration.ephemeral
        config.protocolClasses=[AirHardwareProtocol.self]
        config.timeoutIntervalForResource=10
        session=URLSession(configuration:config,delegate:self,delegateQueue:nil)
        session!.dataTask(with:URL(string:"http://never-connect-old-esp32.invalid/stream")!).resume()
    }
    func urlSession(_ session: URLSession,dataTask: URLSessionDataTask,didReceive response: URLResponse,completionHandler: @escaping (URLSession.ResponseDisposition)->Void) {
        precondition((response as? HTTPURLResponse)?.value(forHTTPHeaderField:"Content-Type")?.contains("multipart/x-mixed-replace")==true)
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession,dataTask: URLSessionDataTask,didReceive data: Data) {
        guard !finished else { return }
        precondition(data.starts(with:Data("--petpal-air-frame\r\n".utf8)))
        precondition(data.range(of:Data([0xff,0xd8])) != nil && data.range(of:Data([0xff,0xd9])) != nil)
        frames+=1
        if frames==2 { finished=true; session.invalidateAndCancel(); continuation?.resume(); continuation=nil }
    }
    func urlSession(_ session: URLSession,task: URLSessionTask,didCompleteWithError error: Error?) {
        if !finished { finished=true; continuation?.resume(throwing:error ?? AirError.unavailable("Stream ended before two frames")); continuation=nil }
    }
}

@main struct AdapterTest {
    static func main() async throws {
        let c=ESPClient(baseURL:URL(string:"http://never-connect-old-esp32.invalid")!)
        try await c.setOn()
        try await c.setOff()
        try await c.setBreathe()
        try await c.motorVibrate()
        try await c.motorStop()
        let m=try await c.motorStatus(); precondition(!m.on)
        let data=try await AirHardwareBackend.response(to:URLRequest(url:URL(string:"http://never-connect-old-esp32.invalid/api/gps")!))
        let g=try JSONDecoder().decode(ESPClient.GPSData.self,from:data)
        // The fixture fix (31.23, 121.47 = Shanghai, WGS-84) must reach the map page as GCJ-02: a few hundred metres NE.
        let gcj=ChinaGeo.wgs84ToGcj02(lat:31.23,lng:121.47)
        precondition(g.fix && abs(g.lat-gcj.lat)<1e-9 && abs(g.lng-gcj.lng)<1e-9 && abs(g.lat-31.23)>1e-4 && abs(g.lng-121.47)>1e-4 && abs(g.lat-31.23)<0.01 && abs(g.lng-121.47)<0.01 && g.speedKmh==3.704 && g.sats==12 && g.ageMs==2000)
        // Known vector: Tiananmen WGS-84 (39.90733, 116.39128) -> GCJ-02 ≈ (39.90874, 116.39751); identity outside China.
        let t=ChinaGeo.wgs84ToGcj02(lat:39.90733,lng:116.39128); precondition(abs(t.lat-39.90874)<2e-4 && abs(t.lng-116.39751)<2e-4)
        let o=ChinaGeo.wgs84ToGcj02(lat:37.7749,lng:-122.4194); precondition(o.lat==37.7749 && o.lng == -122.4194)
        let jpeg=try await AirHardwareBackend.response(to:URLRequest(url:URL(string:"http://never-connect-old-esp32.invalid/capture")!))
        precondition(jpeg.prefix(2)==Data([0xff,0xd8]) && jpeg.suffix(2)==Data([0xff,0xd9]))
        let probe=StreamProbe()
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void,Error>) in probe.start(c) }
        precondition(probe.frames==2)
        for path in ["/led/rgb", "/speaker/play", "/arc/fire", "/api/status", "/motor/vibrate?duration=5000", "/motor/vibrate?intensity=100"] {
            do {
                _=try await AirHardwareBackend.response(to:URLRequest(url:URL(string:"http://never-connect-old-esp32.invalid"+path)!))
                fatalError("Unsupported hardware reported success: \(path)")
            } catch is AirError { }
        }
        print("PASS: original ESPClient API -> Air transport; terminal ACK; GPS; real output state; unavailable hardware errors")
    }
}
