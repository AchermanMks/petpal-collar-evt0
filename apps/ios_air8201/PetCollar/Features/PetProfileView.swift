import SwiftUI
import PhotosUI
import UIKit

// MARK: - Data Model

enum PetGender: String, Codable, CaseIterable, Identifiable {
    case male = "公", female = "母", unknown = "未知"
    var id: String { rawValue }
}

struct PetPhoto: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var filename: String        // pet_media/ 下的相对文件名
    var caption: String = ""
    var takenAt: Date = .now
}

struct PetProfile: Codable, Equatable {
    var name: String = ""
    var birthday: Date? = nil
    var breed: String = ""
    var gender: PetGender = .unknown
    var story: String = ""
    var avatarFilename: String? = nil
    var photos: [PetPhoto] = []
    var isDeceased: Bool = false       // 纪念模式开关
    var deceasedAt: Date? = nil        // 离开时间

    static let empty = PetProfile()
}

// MARK: - Media Store（图片二进制走 Documents/pet_media/，metadata 走 AppStorage JSON）

enum PetMediaStore {
    static let dir: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let d = docs.appendingPathComponent("pet_media", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    static func url(for filename: String) -> URL {
        dir.appendingPathComponent(filename)
    }

    static func save(_ data: Data, ext: String = "jpg") -> String {
        let filename = "\(UUID().uuidString).\(ext)"
        try? data.write(to: url(for: filename), options: .atomic)
        return filename
    }

    static func loadImage(_ filename: String) -> UIImage? {
        guard let data = try? Data(contentsOf: url(for: filename)) else { return nil }
        return UIImage(data: data)
    }

    static func delete(_ filename: String) {
        try? FileManager.default.removeItem(at: url(for: filename))
    }
}

// MARK: - Share Card（用 ImageRenderer 渲染为图片分享）

struct PetProfileShareCard: View {
    let profile: PetProfile
    let avatar: UIImage?

    var body: some View {
        VStack(spacing: 14) {
            Group {
                if let avatar {
                    Image(uiImage: avatar)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "pawprint.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(20)
                }
            }
            .frame(width: 110, height: 110)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white, lineWidth: 4))

            Text(profile.name.isEmpty ? "我的宠物" : profile.name)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)

            HStack(spacing: 10) {
                if !profile.breed.isEmpty { Text(profile.breed) }
                Text(profile.gender.rawValue)
                if let b = profile.birthday { Text(Self.ageLabel(birthday: b)) }
            }
            .font(.callout)
            .foregroundStyle(.white.opacity(0.9))

            if !profile.story.isEmpty {
                Text(profile.story)
                    .font(.body)
                    .lineLimit(4)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(.horizontal, 8)
            }

            Text("via 宠宝PetPel")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, 4)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .frame(width: 340)
        .background(
            LinearGradient(
                colors: [Color.pink.opacity(0.9), Color.orange.opacity(0.7)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    static func ageLabel(birthday: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month], from: birthday, to: .now)
        let y = comps.year ?? 0, m = comps.month ?? 0
        if y > 0 { return "\(y) 岁" }
        return "\(max(m, 0)) 个月"
    }
}

// MARK: - Main View

struct PetProfileView: View {
    @AppStorage("petProfileJson") private var petProfileJson: String = ""
    @State private var profile: PetProfile = .empty
    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var avatarImage: UIImage?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var shareCardImage: UIImage?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                avatarHeader
                basicInfoCard
                storyCard
                photosCard
                shareSection
            }
            .padding()
        }
        .navigationTitle("宠物身份")
        .onAppear(perform: loadProfile)
        .onChange(of: profile) { _, _ in save() }
        .onChange(of: avatarPickerItem) { _, item in handleAvatar(item) }
        .onChange(of: photoPickerItem) { _, item in handleAddPhoto(item) }
    }

    // MARK: - Cards

    private var avatarHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Group {
                    if let avatarImage {
                        Image(uiImage: avatarImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        LinearGradient(colors: [.pink.opacity(0.4), .orange.opacity(0.3)],
                                       startPoint: .top, endPoint: .bottom)
                            .overlay(Image(systemName: "pawprint.fill")
                                .font(.system(size: 50)).foregroundStyle(.white))
                    }
                }
                .frame(width: 140, height: 140)
                .clipShape(Circle())

                PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                    Image(systemName: "camera.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .background(Circle().fill(.black.opacity(0.5)).frame(width: 36, height: 36))
                }
                .offset(x: 48, y: 48)
            }

            TextField("宠物名字", text: $profile.name)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 40)
        }
    }

    private var basicInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("基本信息", systemImage: "info.circle.fill").font(.headline)
            DatePicker("生日", selection: Binding(
                get: { profile.birthday ?? .now },
                set: { profile.birthday = $0 }
            ), displayedComponents: .date)

            HStack {
                Text("品种").foregroundStyle(.secondary)
                Spacer()
                TextField("英短/狸花/田园…", text: $profile.breed)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain)
            }

            HStack {
                Text("性别").foregroundStyle(.secondary)
                Spacer()
                Picker("性别", selection: $profile.gender) {
                    ForEach(PetGender.allCases) { g in
                        Text(g.rawValue).tag(g)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var storyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("故事", systemImage: "text.book.closed.fill").font(.headline)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $profile.story)
                    .frame(minHeight: 100, maxHeight: 200)
                    .scrollContentBackground(.hidden)
                    .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                if profile.story.isEmpty {
                    Text("写点关于它的故事…")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var photosCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("照片集", systemImage: "photo.on.rectangle.angled").font(.headline)
                Spacer()
                Text("\(profile.photos.count) 张")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    PhotosPicker(selection: $photoPickerItem, matching: .images) {
                        VStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill").font(.title)
                            Text("添加").font(.caption2)
                        }
                        .foregroundStyle(.pink)
                        .frame(width: 90, height: 90)
                        .background(Color.pink.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                    ForEach(profile.photos) { photo in
                        photoTile(photo)
                    }
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func photoTile(_ photo: PetPhoto) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let img = PetMediaStore.loadImage(photo.filename) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Color.secondary.opacity(0.1)
                }
            }
            .frame(width: 90, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button {
                deletePhoto(photo)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, .black.opacity(0.6))
                    .font(.title3)
            }
            .padding(4)
        }
    }

    private var shareSection: some View {
        VStack(spacing: 12) {
            Button(action: renderShareCard) {
                Label("生成分享名片", systemImage: "square.and.arrow.up.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(colors: [.pink, .orange],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .foregroundStyle(.white)
            }

            if let img = shareCardImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(radius: 4)

                ShareLink(
                    item: Image(uiImage: img),
                    subject: Text("我的宠物 \(profile.name)"),
                    preview: SharePreview(
                        profile.name.isEmpty ? "我的宠物" : profile.name,
                        image: Image(uiImage: img)
                    )
                ) {
                    Label("分享到…", systemImage: "paperplane.fill")
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                        .foregroundStyle(.blue)
                }
            }
        }
    }

    // MARK: - Persistence & actions

    private func loadProfile() {
        if !petProfileJson.isEmpty,
           let data = petProfileJson.data(using: .utf8),
           let p = try? JSONDecoder().decode(PetProfile.self, from: data) {
            profile = p
        }
        if let av = profile.avatarFilename {
            avatarImage = PetMediaStore.loadImage(av)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profile),
           let s = String(data: data, encoding: .utf8) {
            petProfileJson = s
        }
    }

    private func handleAvatar(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let filename = PetMediaStore.save(data)
                let old = profile.avatarFilename
                await MainActor.run {
                    if let old { PetMediaStore.delete(old) }
                    profile.avatarFilename = filename
                    avatarImage = UIImage(data: data)
                    avatarPickerItem = nil
                }
            }
        }
    }

    private func handleAddPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let filename = PetMediaStore.save(data)
                let photo = PetPhoto(filename: filename)
                await MainActor.run {
                    profile.photos.append(photo)
                    photoPickerItem = nil
                }
            }
        }
    }

    private func deletePhoto(_ photo: PetPhoto) {
        PetMediaStore.delete(photo.filename)
        profile.photos.removeAll { $0.id == photo.id }
    }

    @MainActor
    private func renderShareCard() {
        let renderer = ImageRenderer(content: PetProfileShareCard(profile: profile, avatar: avatarImage))
        renderer.scale = 3
        shareCardImage = renderer.uiImage
    }
}
