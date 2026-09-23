import SwiftUI

struct ConnectionView: View {
    @Environment(AppState.self) private var state
    @AppStorage("lastBaseURL") private var lastBaseURL: String = ""
    @State private var urlString: String = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 10) {
                Image(systemName: "pawprint.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.tint)
                Text("Pet Collar")
                    .font(.largeTitle.weight(.bold))
                Text("连接到后端服务器")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("服务器地址")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("http://<ip>:5008", text: $urlString)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(connect)
                    .disabled(isConnecting)
                Text("连接 Linux 真后端；实时预览读取 Linux 视频源")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 360)

            Button(action: connect) {
                HStack(spacing: 8) {
                    if isConnecting { ProgressView().controlSize(.small) }
                    Text(isConnecting ? "连接中…" : "连接")
                        .frame(maxWidth: 140)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isConnecting || urlString.isEmpty)

            if case .failed(let msg) = state.status {
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            if case .reconnecting(let msg) = state.status {
                Label("重连中… \(msg)", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
            if case .connected = state.status {
                Label("已连接 Linux 后端", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if urlString.isEmpty {
                let migrated = BackendEndpoint.migratedSavedURL(lastBaseURL)
                urlString = migrated
                lastBaseURL = migrated
            }
        }
    }

    private var isConnecting: Bool {
        if case .connecting = state.status { return true }
        return false
    }

    private func connect() {
        Task {
            guard await state.connect(urlString: urlString), let connectedURL = state.baseURL else { return }
            let canonical = connectedURL.absoluteString
            lastBaseURL = canonical
            urlString = canonical
        }
    }
}
