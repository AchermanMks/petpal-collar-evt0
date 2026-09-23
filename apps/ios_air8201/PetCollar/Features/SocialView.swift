import SwiftUI
import Observation
import PhotosUI
import UIKit

// MARK: - 数据模型

struct SocialPet: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let breed: String
    let age: String
    let genderRaw: String
    let distance: String
    let bio: String
    let iconSymbol: String
    let colorHex: String  // 卡片背景色相
    /// 照片（Assets 里的 breed_* 素材），没有时回落到 colorHex + iconSymbol
    var photoAsset: String? = nil

    var gender: PetGender { PetGender(rawValue: genderRaw) ?? .unknown }
}

struct VetClinic: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let address: String
    let rating: Double
    let priceRange: String
    let services: [String]
    let slots: [String]
    /// 医院卡缩略图（Assets 里的 clinic_* 素材），没有时不显示
    var photoAsset: String? = nil
}

struct VetAppointment: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    let clinicId: String
    let clinicName: String
    let slot: String
    var price: String = ""
    var bookedAt: Date = .now
    var paid: Bool = true
}

struct BreedingAppointment: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    let petName: String
    let petBreed: String
    let service: String
    var price: String = "¥800"
    var slot: String = ""
    var bookedAt: Date = .now
    var paid: Bool = true
}

struct MemorialMessage: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    let author: String
    let text: String
    let when: Date
}

struct FeedPost: Identifiable, Codable, Equatable {
    let id: String
    let author: String
    let authorIcon: String  // SF Symbol
    let authorColorHex: String
    let title: String
    let body: String
    let coverSymbol: String      // SF Symbol 当封面（没传照片时用）
    let coverColorHex: String
    let coverAspect: Double      // 0.7~1.4，控制瀑布流参差
    let likes: Int
    let comments: Int
    let tags: [String]
    var imageFiles: [String]? = nil   // 用户上传的照片（Documents/feed_images 下的文件名）
    /// 内置素材封面（Assets 里的图片名，如 breed_ragdoll）。
    /// 封面优先级：用户上传照片 > 内置素材图 > 色块 + SF Symbol。
    var coverAsset: String? = nil
}

// MARK: - 动态照片存储（文件存 Documents，UserDefaults 只存文件名）

enum FeedImageStore {
    static var dir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("feed_images", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// 压缩到最长边 1280、JPEG 0.72 后落盘，返回文件名
    static func save(_ data: Data) -> String? {
        guard let img = UIImage(data: data) else { return nil }
        let resized = img.resizedIfNeeded(maxDim: 1280)
        guard let jpeg = resized.jpegData(compressionQuality: 0.72) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do {
            try jpeg.write(to: dir.appendingPathComponent(name))
            return name
        } catch {
            return nil
        }
    }

    static func load(_ name: String) -> UIImage? {
        UIImage(contentsOfFile: dir.appendingPathComponent(name).path)
    }

    static func delete(_ names: [String]) {
        for n in names {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(n))
        }
    }
}

private extension UIImage {
    func resizedIfNeeded(maxDim: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDim else { return self }
        let k = maxDim / longest
        let newSize = CGSize(width: size.width * k, height: size.height * k)
        return UIGraphicsImageRenderer(size: newSize).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

struct PostComment: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    let author: String
    let authorIcon: String
    let authorColorHex: String
    let text: String
    let when: Date
    var likeCount: Int = 0
}

// MARK: - 假数据

enum SocialCatalog {
    static let nearbyPets: [SocialPet] = [
        SocialPet(id: "p1", name: "麻薯", breed: "英短银渐层", age: "2 岁", genderRaw: "母",
                  distance: "0.8 km", bio: "喜欢追激光笔，最近刚学会握手 🐾", iconSymbol: "cat.fill", colorHex: "F8B5C0", photoAsset: "breed_blue"),
        SocialPet(id: "p2", name: "黑米", breed: "孟买猫", age: "3 岁", genderRaw: "公",
                  distance: "1.2 km", bio: "夜行性，最爱钻纸箱。寻找一个温柔的女朋友。", iconSymbol: "moon.stars.fill", colorHex: "BCB6FF", photoAsset: "breed_cow"),
        SocialPet(id: "p3", name: "豆豆", breed: "中华田园猫", age: "1 岁", genderRaw: "母",
                  distance: "2.0 km", bio: "胆小但好奇，会偷主人的发圈", iconSymbol: "leaf.fill", colorHex: "C5E8B7", photoAsset: "breed_lihua"),
        SocialPet(id: "p4", name: "Mochi", breed: "暹罗", age: "4 岁", genderRaw: "公",
                  distance: "3.5 km", bio: "话痨，每天唱歌给主人听", iconSymbol: "music.note", colorHex: "FFE8A3", photoAsset: "breed_siamese"),
        SocialPet(id: "p5", name: "雪糕", breed: "布偶", age: "2 岁", genderRaw: "母",
                  distance: "0.5 km", bio: "甜美治愈，蓝眼睛。爱吃猫条胜过一切。", iconSymbol: "snowflake", colorHex: "B7E0F8", photoAsset: "breed_ragdoll"),
        SocialPet(id: "p6", name: "拿铁", breed: "美短", age: "3 岁", genderRaw: "公",
                  distance: "4.2 km", bio: "运动健将，能跳一米五。性格稳定。", iconSymbol: "figure.run", colorHex: "DDC0A3", photoAsset: "breed_amshort"),
        SocialPet(id: "p7", name: "桃子", breed: "金渐层", age: "1 岁 6 月", genderRaw: "母",
                  distance: "1.8 km", bio: "圆滚滚，爱卖萌。会自己开柜门偷零食。", iconSymbol: "heart.fill", colorHex: "FFCBA4", photoAsset: "breed_golden"),
        SocialPet(id: "p8", name: "墨墨", breed: "无毛猫", age: "5 岁", genderRaw: "公",
                  distance: "6.0 km", bio: "成熟稳重，绅士风度。寻找懂他的人。", iconSymbol: "circle.fill", colorHex: "D4D4D4", photoAsset: "breed_exotic"),
    ]

    static let clinics: [VetClinic] = [
        VetClinic(
            id: "v1", name: "瑞鹏宠物医院 · 中关村店",
            address: "海淀区中关村大街 27 号",
            rating: 4.8, priceRange: "¥1280-1680",
            services: ["公猫绝育", "母猫绝育", "术前体检", "术后住院 1 晚"],
            slots: ["明天 10:00", "明天 14:30", "后天 09:00", "后天 11:00", "周六 14:00"],
            photoAsset: "clinic_1"
        ),
        VetClinic(
            id: "v2", name: "美联众合 · 五道口分院",
            address: "海淀区成府路 28 号",
            rating: 4.6, priceRange: "¥980-1280",
            services: ["公猫绝育", "母猫绝育", "微创腔镜", "门诊回访"],
            slots: ["明天 11:30", "明天 16:00", "后天 14:00", "周日 10:30"],
            photoAsset: "clinic_2"
        ),
        VetClinic(
            id: "v3", name: "芭比堂 · 望京旗舰店",
            address: "朝阳区望京西路 48 号",
            rating: 4.9, priceRange: "¥1580-2080",
            services: ["公猫绝育", "母猫绝育", "高端麻醉监护", "术后接送"],
            slots: ["后天 10:00", "后天 15:30", "周六 11:00", "周日 14:30"],
            photoAsset: "clinic_3"
        ),
    ]

    static let feedPosts: [FeedPost] = [
        FeedPost(id: "f1", author: "麻薯妈", authorIcon: "person.crop.circle.fill", authorColorHex: "F8B5C0",
                 title: "猫主子又开始拆家了 😭",
                 body: "下班回家发现客厅一片狼藉。卷纸全撕了，沙发垫掀翻，最绝的是把我的运动鞋叼到猫砂盆边。\n谁懂啊家人们…",
                 coverSymbol: "pawprint.fill", coverColorHex: "FFD1DC", coverAspect: 1.2,
                 likes: 1234, comments: 89, tags: ["拆家", "日常"],
                 coverAsset: "breed_blue"),          // 麻薯 = 英短
        FeedPost(id: "f2", author: "雪糕的铲屎官", authorIcon: "snowflake", authorColorHex: "B7E0F8",
                 title: "布偶猫到底要不要剃毛？我有话说",
                 body: "夏天到了，很多铲屎官纠结这个。我家雪糕上次剃了之后整整两个月不理我，血泪教训。",
                 coverSymbol: "scissors", coverColorHex: "B7E0F8", coverAspect: 0.9,
                 likes: 2890, comments: 312, tags: ["布偶", "毛发护理"],
                 coverAsset: "breed_ragdoll"),
        FeedPost(id: "f3", author: "黑米爸爸", authorIcon: "moon.stars.fill", authorColorHex: "BCB6FF",
                 title: "深夜十二点，猫在跑酷",
                 body: "孟买猫的精力实在惊人。已经搬到次卧睡觉了，今晚还是被吵醒。",
                 coverSymbol: "figure.run", coverColorHex: "DDC0FF", coverAspect: 1.4,
                 likes: 567, comments: 42, tags: ["孟买", "夜行性"],
                 coverAsset: "breed_cow"),          // 素材里没有纯黑孟买，用黑白奶牛猫顶

        FeedPost(id: "f4", author: "豆豆麻", authorIcon: "leaf.fill", authorColorHex: "C5E8B7",
                 title: "新手养猫第一周记录",
                 body: "豆豆刚到家三天。开罐头她会从沙发后面探头，但还不让摸。\n准备了多个躲藏点。等就完了。",
                 coverSymbol: "house.fill", coverColorHex: "C5E8B7", coverAspect: 1.1,
                 likes: 845, comments: 67, tags: ["新手", "应激"],
                 coverAsset: "breed_lihua"),        // 豆豆 = 中华田园（狸花）
        FeedPost(id: "f5", author: "Mochi 唱歌团", authorIcon: "music.note", authorColorHex: "FFE8A3",
                 title: "暹罗猫的话痨日常 🎤",
                 body: "在家随便一句话她都要回。门铃响了她叫，我叹气她叫，洗碗水声她叫。\n我已经接受现实了。",
                 coverSymbol: "waveform", coverColorHex: "FFE8A3", coverAspect: 0.8,
                 likes: 3120, comments: 256, tags: ["暹罗", "话痨"],
                 coverAsset: "breed_siamese"),
        FeedPost(id: "f6", author: "拿铁运动会", authorIcon: "figure.run", authorColorHex: "DDC0A3",
                 title: "记录拿铁跳一米五的瞬间",
                 body: "美短爆发力实测。从地板到冰箱顶，三个跳跃步。\n训练了两周，奖励是冻干。",
                 coverSymbol: "bolt.fill", coverColorHex: "DDC0A3", coverAspect: 1.3,
                 likes: 1567, comments: 124, tags: ["美短", "训练"],
                 coverAsset: "breed_amshort"),
        FeedPost(id: "f7", author: "桃子柜子开门帮", authorIcon: "heart.fill", authorColorHex: "FFCBA4",
                 title: "我家猫学会开柜子之后…",
                 body: "零食柜已经加了儿童锁。她还在研究。\n猫的智商不能小看。",
                 coverSymbol: "lock.open.fill", coverColorHex: "FFCBA4", coverAspect: 1.0,
                 likes: 982, comments: 78, tags: ["金渐层", "智商"],
                 coverAsset: "breed_golden"),
        FeedPost(id: "f8", author: "墨墨大叔", authorIcon: "circle.fill", authorColorHex: "D4D4D4",
                 title: "无毛猫日常护理总结",
                 body: "每周一次温水擦身，耳朵更要勤清。皮脂分泌旺盛是常态，别慌。",
                 coverSymbol: "drop.fill", coverColorHex: "D4D4D4", coverAspect: 0.9,
                 likes: 423, comments: 31, tags: ["无毛猫", "护理"],
                 coverAsset: "breed_exotic"),       // 没有无毛猫素材，用同为特殊脸型的加菲
        FeedPost(id: "f9", author: "兽医刘医生", authorIcon: "cross.case.fill", authorColorHex: "B7E0F8",
                 title: "绝育后注意事项，划重点",
                 body: "1) 麻醉后 6 小时内禁食禁水\n2) 戴伊丽莎白圈 7-10 天\n3) 注意伤口红肿渗液\n4) 14 天内禁洗澡",
                 coverSymbol: "cross.fill", coverColorHex: "BFDDFF", coverAspect: 1.15,
                 likes: 5621, comments: 489, tags: ["绝育", "科普"],
                 coverAsset: "breed_bluewhite"),    // 科普贴，用张安静的蓝白
        FeedPost(id: "f10", author: "宠友群 · 桃子妈", authorIcon: "person.3.fill", authorColorHex: "FFCBA4",
                 title: "周末线下撸猫聚会回顾",
                 body: "10 家铲屎官 + 12 只猫，全程零打架。最受欢迎的是桃子，她全场卖萌。\n下次还约。",
                 coverSymbol: "person.3.sequence.fill", coverColorHex: "FFCBA4", coverAspect: 1.25,
                 likes: 712, comments: 95, tags: ["线下", "聚会"],
                 coverAsset: "breed_sanhua"),       // 聚会里最出风头的桃子
    ]

    static let commentsSeed: [String: [PostComment]] = [
        "f1": [
            PostComment(author: "雪糕的铲屎官", authorIcon: "snowflake", authorColorHex: "B7E0F8",
                        text: "哈哈哈我家也是！回家发现卷纸被撕得满地都是 😂", when: .now.addingTimeInterval(-3600), likeCount: 23),
            PostComment(author: "豆豆麻", authorIcon: "leaf.fill", authorColorHex: "C5E8B7",
                        text: "建议买那种带盖的纸巾盒，亲测有效", when: .now.addingTimeInterval(-7200), likeCount: 45),
            PostComment(author: "拿铁运动会", authorIcon: "figure.run", authorColorHex: "DDC0A3",
                        text: "运动鞋那个绝了 🤣", when: .now.addingTimeInterval(-10800), likeCount: 12),
        ],
        "f2": [
            PostComment(author: "麻薯妈", authorIcon: "person.crop.circle.fill", authorColorHex: "F8B5C0",
                        text: "千万别剃！我朋友家的布偶剃完抑郁了一个月", when: .now.addingTimeInterval(-1800), likeCount: 67),
            PostComment(author: "兽医刘医生", authorIcon: "cross.case.fill", authorColorHex: "B7E0F8",
                        text: "不建议剃毛，猫的毛发有隔热功能。定期梳毛即可。", when: .now.addingTimeInterval(-5400), likeCount: 156),
        ],
        "f3": [
            PostComment(author: "Mochi 唱歌团", authorIcon: "music.note", authorColorHex: "FFE8A3",
                        text: "暹罗也是！半夜三点开始唱歌 🎤", when: .now.addingTimeInterval(-2400), likeCount: 34),
        ],
        "f5": [
            PostComment(author: "黑米爸爸", authorIcon: "moon.stars.fill", authorColorHex: "BCB6FF",
                        text: "暹罗话痨是真的，我朋友家那只能叫一整天", when: .now.addingTimeInterval(-4800), likeCount: 28),
            PostComment(author: "桃子柜子开门帮", authorIcon: "heart.fill", authorColorHex: "FFCBA4",
                        text: "可以试试用逗猫棒消耗精力，叫的会少一点", when: .now.addingTimeInterval(-9600), likeCount: 19),
        ],
        "f9": [
            PostComment(author: "麻薯妈", authorIcon: "person.crop.circle.fill", authorColorHex: "F8B5C0",
                        text: "收藏了！下周就要去绝育，正好用得上", when: .now.addingTimeInterval(-600), likeCount: 89),
            PostComment(author: "墨墨大叔", authorIcon: "circle.fill", authorColorHex: "D4D4D4",
                        text: "补充一下：公猫恢复比母猫快，一般 3 天就活蹦乱跳了", when: .now.addingTimeInterval(-3000), likeCount: 72),
            PostComment(author: "桃子柜子开门帮", authorIcon: "heart.fill", authorColorHex: "FFCBA4",
                        text: "伊丽莎白圈真的要戴够天数，桃子提前摘了差点感染", when: .now.addingTimeInterval(-7800), likeCount: 41),
        ],
    ]

    static let memorialMessagesSeed: [MemorialMessage] = [
        MemorialMessage(author: "邻居王阿姨", text: "每次见到你都要蹭蹭我的腿，太想你了 🌹",
                        when: .now.addingTimeInterval(-86400 * 2)),
        MemorialMessage(author: "好友小李", text: "记得你最爱在阳台晒太阳的样子，去当星星了也要继续闪亮。",
                        when: .now.addingTimeInterval(-86400 * 4)),
        MemorialMessage(author: "兽医刘医生", text: "你是个非常勇敢的小家伙，我永远记得你。",
                        when: .now.addingTimeInterval(-86400 * 7)),
        MemorialMessage(author: "宠友群 · 麻薯妈", text: "请放心，我们都会想着你。彩虹桥见。",
                        when: .now.addingTimeInterval(-86400 * 10)),
    ]
}

// MARK: - Store

@MainActor
@Observable
final class SocialStore {
    var likedPetIds: Set<String> = []
    var passedPetIds: Set<String> = []
    var appointments: [VetAppointment] = []
    var breedingAppointments: [BreedingAppointment] = []
    var candlesLit: Int = 0
    var memorialMessages: [MemorialMessage] = SocialCatalog.memorialMessagesSeed
    var likedPostIds: Set<String> = []
    var followedAuthors: Set<String> = []
    var postComments: [String: [PostComment]] = SocialCatalog.commentsSeed
    var likedCommentIds: Set<UUID> = []
    var userPosts: [FeedPost] = []

    private let appointmentsKey = "vetAppointmentsJson"
    private let breedingKey = "breedingAppointmentsJson"
    private let candlesKey = "memorialCandlesLit"
    private let likedPostsKey = "socialLikedPostIds"
    private let followedKey = "socialFollowedAuthors"
    private let userPostsKey = "socialUserPostsJson"

    init() { load() }

    func like(_ id: String) { likedPetIds.insert(id) }
    func pass(_ id: String) { passedPetIds.insert(id) }

    var remainingPets: [SocialPet] {
        SocialCatalog.nearbyPets.filter { !likedPetIds.contains($0.id) && !passedPetIds.contains($0.id) }
    }

    func book(_ clinic: VetClinic, slot: String, price: String) -> VetAppointment {
        let appt = VetAppointment(clinicId: clinic.id, clinicName: clinic.name, slot: slot, price: price)
        appointments.insert(appt, at: 0)
        save()
        return appt
    }

    func bookBreeding(pet: SocialPet, service: String, slot: String, price: String) -> BreedingAppointment {
        let appt = BreedingAppointment(petName: pet.name, petBreed: pet.breed, service: service, price: price, slot: slot)
        breedingAppointments.insert(appt, at: 0)
        saveBreeding()
        return appt
    }

    func cancelAppointment(_ id: UUID) {
        appointments.removeAll { $0.id == id }
        save()
    }

    func cancelBreeding(_ id: UUID) {
        breedingAppointments.removeAll { $0.id == id }
        saveBreeding()
    }

    func lightCandle() {
        candlesLit += 1
        UserDefaults.standard.set(candlesLit, forKey: candlesKey)
    }

    func togglePostLike(_ id: String) {
        if likedPostIds.contains(id) {
            likedPostIds.remove(id)
        } else {
            likedPostIds.insert(id)
        }
        UserDefaults.standard.set(Array(likedPostIds), forKey: likedPostsKey)
    }

    func toggleFollow(_ author: String) {
        if followedAuthors.contains(author) {
            followedAuthors.remove(author)
        } else {
            followedAuthors.insert(author)
        }
        UserDefaults.standard.set(Array(followedAuthors), forKey: followedKey)
    }

    func isFollowing(_ author: String) -> Bool {
        followedAuthors.contains(author)
    }

    func addComment(postId: String, text: String) {
        let comment = PostComment(
            author: "我", authorIcon: "person.crop.circle.fill",
            authorColorHex: "FF8A65", text: text, when: .now
        )
        if postComments[postId] != nil {
            postComments[postId]!.insert(comment, at: 0)
        } else {
            postComments[postId] = [comment]
        }
    }

    func commentsFor(_ postId: String) -> [PostComment] {
        postComments[postId] ?? []
    }

    func commentCount(_ post: FeedPost) -> Int {
        post.comments + (postComments[post.id]?.count ?? 0)
            - (SocialCatalog.commentsSeed[post.id]?.count ?? 0)
    }

    func toggleCommentLike(_ commentId: UUID) {
        if likedCommentIds.contains(commentId) {
            likedCommentIds.remove(commentId)
        } else {
            likedCommentIds.insert(commentId)
        }
    }

    // MARK: 发布动态

    @discardableResult
    func publish(title: String, body: String, coverSymbol: String,
                 coverColorHex: String, tags: [String],
                 imageFiles: [String] = [], coverAspect: Double? = nil) -> FeedPost {
        let post = FeedPost(
            id: "user-\(UUID().uuidString)",
            author: "我",
            authorIcon: "person.crop.circle.fill",
            authorColorHex: "FF8A65",
            title: title,
            body: body,
            coverSymbol: coverSymbol,
            coverColorHex: coverColorHex,
            coverAspect: coverAspect ?? [1.0, 0.85, 1.2][title.count % 3],
            likes: 0,
            comments: 0,
            tags: tags,
            imageFiles: imageFiles.isEmpty ? nil : imageFiles
        )
        userPosts.insert(post, at: 0)
        saveUserPosts()
        return post
    }

    func deleteUserPost(_ id: String) {
        if let post = userPosts.first(where: { $0.id == id }), let files = post.imageFiles {
            FeedImageStore.delete(files)
        }
        userPosts.removeAll { $0.id == id }
        saveUserPosts()
    }

    private func saveUserPosts() {
        if let data = try? JSONEncoder().encode(userPosts),
           let s = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(s, forKey: userPostsKey)
        }
    }

    private func load() {
        if let json = UserDefaults.standard.string(forKey: appointmentsKey),
           let data = json.data(using: .utf8),
           let arr = try? JSONDecoder().decode([VetAppointment].self, from: data) {
            appointments = arr
        }
        if let json2 = UserDefaults.standard.string(forKey: breedingKey),
           let data2 = json2.data(using: .utf8),
           let arr2 = try? JSONDecoder().decode([BreedingAppointment].self, from: data2) {
            breedingAppointments = arr2
        }
        candlesLit = UserDefaults.standard.integer(forKey: candlesKey)
        if let arr = UserDefaults.standard.stringArray(forKey: likedPostsKey) {
            likedPostIds = Set(arr)
        }
        if let arr = UserDefaults.standard.stringArray(forKey: followedKey) {
            followedAuthors = Set(arr)
        }
        if let json = UserDefaults.standard.string(forKey: userPostsKey),
           let data = json.data(using: .utf8),
           let arr = try? JSONDecoder().decode([FeedPost].self, from: data) {
            userPosts = arr
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(appointments),
           let s = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(s, forKey: appointmentsKey)
        }
    }

    private func saveBreeding() {
        if let data = try? JSONEncoder().encode(breedingAppointments),
           let s = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(s, forKey: breedingKey)
        }
    }
}

// MARK: - 主视图

struct SocialView: View {
    enum SocialTab: String, CaseIterable, Identifiable {
        case feed = "动态"
        case memorial = "纪念"
        var id: String { rawValue }
    }

    @State private var selectedTab: SocialTab = .feed
    @State private var store = SocialStore()

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(SocialTab.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            Group {
                switch selectedTab {
                case .feed:     FeedView()
                case .memorial: MemorialView()
                }
            }
            .environment(store)
        }
        .navigationTitle(L("社交"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 独立入口视图

struct FeedEntryView: View {
    @State private var store = SocialStore()
    @State private var cart = CartStore()
    @State private var orders = OrderStore()
    @State private var showCompose = false

    var body: some View {
        FeedView()
            .environment(store)
            .environment(cart)
            .environment(orders)
            .navigationTitle(L("发现"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCompose = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $showCompose) {
                ComposePostSheet()
                    .environment(store)
            }
    }
}

struct MemorialEntryView: View {
    @State private var store = SocialStore()

    var body: some View {
        MemorialView()
            .environment(store)
            .navigationTitle(L("纪念"))
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct MatchingEntryView: View {
    @State private var store = SocialStore()

    var body: some View {
        MatchingView(store: store)
            .navigationTitle(L("配种"))
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct NeuteringEntryView: View {
    @State private var store = SocialStore()

    var body: some View {
        VetView(store: store)
            .navigationTitle(L("绝育预约"))
            .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 小红书风 Feed（顶部双栏：动态 | 商城）

enum FeedItem: Identifiable {
    case post(FeedPost)
    case product(SKU)

    var id: String {
        switch self {
        case .post(let p): return p.id
        case .product(let s): return "sku-\(s.id)"
        }
    }
}

struct FeedView: View {
    enum FeedTab: String, CaseIterable {
        case posts = "动态"
        case shop = "商城"
        case memorial = "纪念"
        case training = "训猫"
        case matching = "配种"
        case neutering = "医疗"

        var labelEN: String {
            switch self {
            case .posts: return "Feed"
            case .shop: return "Shop"
            case .memorial: return "Memorial"
            case .training: return "Training"
            case .matching: return "Mating"
            case .neutering: return "Medical"
            }
        }
    }

    @Environment(SocialStore.self) private var store
    @Environment(CartStore.self) private var cart
    @Environment(PetRouter.self) private var router
    @AppStorage("appLanguage") private var appLanguage: String = "zh"
    @State private var tab: FeedTab = .posts
    @State private var seenShopNonce = 0   // 已消费的上滑跳商城请求
    @State private var searchText = ""
    @State private var detailPost: FeedPost?
    @State private var detailSKU: SKU?
    @State private var showCartToast = false
    @State private var showCart = false

    private var query: String {
        searchText.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private var feedItems: [FeedItem] {
        let q = query
        switch tab {
        case .posts:
            var posts = store.userPosts + SocialCatalog.feedPosts
            if !q.isEmpty {
                posts = posts.filter { p in
                    p.title.lowercased().contains(q)
                        || p.body.lowercased().contains(q)
                        || p.author.lowercased().contains(q)
                        || p.tags.contains { $0.lowercased().contains(q) }
                }
            }
            return posts.map(FeedItem.post)
        default:
            // 医疗服务不进商城信息流，统一收在「医疗」栏目里
            var skus = ShopCatalog.all.filter { $0.category != .medical }
            if !q.isEmpty {
                skus = skus.filter { s in
                    s.name.lowercased().contains(q)
                        || s.subtitle.lowercased().contains(q)
                        || s.description.lowercased().contains(q)
                        || s.category.rawValue.lowercased().contains(q)
                }
            }
            return skus.map(FeedItem.product)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topTabBar
            searchBar
            content
        }
        // 首页上滑进来时直接落在商城栏目。
        // FeedView 可能在 nonce 变化后才首次挂载（发现页懒加载），
        // 所以 onAppear 也要补消费一次，否则首访会落在「动态」栏。
        .onAppear {
            if router.openShopNonce != seenShopNonce {
                seenShopNonce = router.openShopNonce
                tab = .shop
                searchText = ""
            }
        }
        .onChange(of: router.openShopNonce) {
            seenShopNonce = router.openShopNonce
            withAnimation(.easeInOut(duration: 0.2)) {
                tab = .shop
                searchText = ""
            }
        }
        .sheet(item: $detailPost) { post in
            FeedDetailSheet(post: post)
                .environment(store)
                .presentationDetents([.large])
        }
        .sheet(item: $detailSKU) { sku in
            NavigationStack {
                ProductDetailView(sku: sku)
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showCart) {
            NavigationStack {
                CartView()
            }
        }
        .overlay(alignment: .top) {
            if showCartToast {
                Label(L("已加入购物车"), systemImage: "cart.fill.badge.plus")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: 搜索栏（六个栏目通用，按栏目换提示语）

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.secondary)
            TextField(searchPrompt, text: $searchText)
                .font(.subheadline)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1), in: Capsule())
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private var en: Bool { appLanguage == "en" }

    private var searchPrompt: String {
        switch tab {
        case .posts: return en ? "Search posts: title / text / tag / author"
                               : "搜动态：标题 / 内容 / 标签 / 作者"
        case .shop: return en ? "Search products: name / category" : "搜商品：名称 / 分类"
        case .memorial: return en ? "Search messages" : "搜访客留言"
        case .training: return en ? "Search rules" : "搜训练规则"
        case .matching: return en ? "Search cats: name / breed" : "搜猫咪：名字 / 品种"
        case .neutering: return en ? "Search clinics: name / address / service"
                                   : "搜医院：名称 / 地址 / 服务"
        }
    }

    // MARK: 栏目内容

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .posts, .shop:
            let items = feedItems
            if items.isEmpty && !query.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ScrollView {
                    // 两列瀑布流：按 index 奇偶分两列，列内顺序追加。简单稳，不依赖外部库。
                    HStack(alignment: .top, spacing: 10) {
                        column(items: items.indices.filter { $0.isMultiple(of: 2) }.map { items[$0] })
                        column(items: items.indices.filter { !$0.isMultiple(of: 2) }.map { items[$0] })
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                }
            }
        case .memorial:
            MemorialView(searchText: query)
        case .training:
            TrainingView(searchText: query)
        case .matching:
            MatchingView(store: store, searchText: query)
        case .neutering:
            VetView(store: store, searchText: query)
        }
    }

    // MARK: 顶部栏目切换

    /// 六个栏目横向可滚动——英文标签比中文长得多，等分挤在一行会断词
    private var topTabBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(FeedTab.allCases, id: \.self) { t in
                        tabButton(t)
                    }
                }
                .padding(.horizontal, 10)
            }

            if tab == .shop {
                Button {
                    showCart = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "cart.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(PetPalTheme.primary))
                            .shadow(color: PetPalTheme.primary.opacity(0.35), radius: 5, y: 2)
                        if cart.totalCount > 0 {
                            Text("\(cart.totalCount)")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Capsule().fill(.red))
                                .overlay(Capsule().strokeBorder(.white, lineWidth: 1.5))
                                .offset(x: 6, y: -6)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 6)
    }

    private func tabButton(_ t: FeedTab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                tab = t
                searchText = ""
            }
        } label: {
            VStack(spacing: 4) {
                Text(en ? t.labelEN : t.rawValue)
                    .font(.subheadline.weight(tab == t ? .bold : .regular))
                    .foregroundStyle(tab == t ? .primary : .secondary)
                    .lineLimit(1)
                    .fixedSize()
                Capsule()
                    .fill(tab == t ? PetPalTheme.primary : .clear)
                    .frame(width: 22, height: 3)
            }
            .padding(.horizontal, 10)
        }
        .buttonStyle(.plain)
    }

    private func column(items: [FeedItem]) -> some View {
        VStack(spacing: 10) {
            ForEach(items) { item in
                switch item {
                case .post(let post):
                    Button {
                        detailPost = post
                    } label: {
                        postCard(post)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if post.id.hasPrefix("user-") {
                            Button(role: .destructive) {
                                store.deleteUserPost(post.id)
                            } label: {
                                Label(L("删除这条动态"), systemImage: "trash")
                            }
                        }
                    }
                case .product(let sku):
                    Button {
                        detailSKU = sku
                    } label: {
                        productCard(sku)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: 好物卡（信息流带货）

    private func productCard(_ sku: SKU) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                // 与 ShopView 商品卡同一套：底座定尺寸 → overlay 放图 → clipShape 裁溢出。
                // 直接给 Image 加 scaledToFill 会撑爆瀑布流列宽（横图尤其明显）。
                RoundedRectangle(cornerRadius: 14)
                    .fill(sku.category.color.opacity(0.14))
                    .aspectRatio(1.15, contentMode: .fit)
                    .overlay {
                        if let photo = sku.photo {
                            Image(photo)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: sku.icon)
                                .font(.system(size: 44))
                                .foregroundStyle(sku.category.color)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                Label(sku.category.rawValue, systemImage: sku.category.icon)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(sku.category.color, in: Capsule())
                    .padding(6)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            }

            Text(sku.name)
                .font(.subheadline.weight(.bold))
                .lineLimit(2)
                .padding(.horizontal, 8)

            Text(sku.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 8)

            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text(formatYuan(sku.price))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.red)
                if let orig = sku.originalPrice {
                    Text(formatYuan(orig))
                        .font(.caption2)
                        .strikethrough()
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button {
                    cart.add(sku.id)
                    withAnimation(.spring(duration: 0.3)) { showCartToast = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        withAnimation { showCartToast = false }
                    }
                } label: {
                    Image(systemName: "cart.badge.plus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(sku.category.color, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(sku.category.color.opacity(0.25), lineWidth: 1)
        )
    }

    private func postCard(_ post: FeedPost) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if let file = post.imageFiles?.first, let ui = FeedImageStore.load(file) {
                    Color.clear
                        .overlay(
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFill()
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    if (post.imageFiles?.count ?? 0) > 1 {
                        Image(systemName: "square.on.square.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                            .frame(maxWidth: .infinity, maxHeight: .infinity,
                                   alignment: .topTrailing)
                            .padding(8)
                    }
                } else if let asset = post.coverAsset {
                    // 内置素材封面：底座撑尺寸，图片叠上去裁切，避免横图把瀑布流撑宽
                    Color.clear
                        .overlay(
                            Image(asset)
                                .resizable()
                                .scaledToFill()
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                } else {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(hex: post.coverColorHex))
                    Image(systemName: post.coverSymbol)
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .aspectRatio(post.coverAspect, contentMode: .fit)

            Text(post.title)
                .font(.subheadline.weight(.bold))
                .lineLimit(2)
                .padding(.horizontal, 8)

            HStack(spacing: 6) {
                Image(systemName: post.authorIcon)
                    .foregroundStyle(Color(hex: post.authorColorHex))
                    .font(.caption)
                Text(post.author)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: store.likedPostIds.contains(post.id) ? "heart.fill" : "heart")
                    .foregroundStyle(store.likedPostIds.contains(post.id) ? .pink : .secondary)
                    .font(.caption)
                Text("\(post.likes + (store.likedPostIds.contains(post.id) ? 1 : 0))")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Image(systemName: "bubble.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(store.commentCount(post))")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - 发布动态

struct ComposePostSheet: View {
    @Environment(SocialStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var bodyText = ""
    @State private var coverSymbol = "cat.fill"
    @State private var coverColorHex = "F8B5C0"
    @State private var selectedTags: Set<String> = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var photoDatas: [Data] = []

    private let symbols = ["cat.fill", "pawprint.fill", "heart.fill", "camera.fill",
                           "fish.fill", "moon.stars.fill", "leaf.fill", "sparkles"]
    private let colors = ["F8B5C0", "BCB6FF", "C5E8B7", "FFE8A3", "B7E0F8", "FFCBA4"]
    private let tagOptions = ["日常", "萌宠", "新手", "好物", "求助", "记录"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    photoSection
                    coverPreview
                    if photoDatas.isEmpty {
                        symbolPicker
                        colorPicker
                    }
                    titleField
                    bodyField
                    tagPicker
                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationTitle(L("发布动态"))
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: photoItems) { _, items in
                Task {
                    var datas: [Data] = []
                    for item in items {
                        if let d = try? await item.loadTransferable(type: Data.self) {
                            datas.append(d)
                        }
                    }
                    photoDatas = datas
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("发布")) {
                        var files: [String] = []
                        for d in photoDatas {
                            if let name = FeedImageStore.save(d) { files.append(name) }
                        }
                        var aspect: Double? = nil
                        if let first = photoDatas.first, let ui = UIImage(data: first),
                           ui.size.height > 0 {
                            aspect = min(1.4, max(0.7, ui.size.width / ui.size.height))
                        }
                        store.publish(
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            body: bodyText.trimmingCharacters(in: .whitespacesAndNewlines),
                            coverSymbol: coverSymbol,
                            coverColorHex: coverColorHex,
                            tags: Array(selectedTags),
                            imageFiles: files,
                            coverAspect: aspect
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: 照片选择

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("照片")).font(.subheadline.weight(.bold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(photoDatas.enumerated()), id: \.offset) { i, data in
                        if let ui = UIImage(data: data) {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 84, height: 84)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        if i < photoItems.count { photoItems.remove(at: i) }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 17))
                                            .foregroundStyle(.white, .black.opacity(0.55))
                                    }
                                    .padding(3)
                                }
                        }
                    }
                    if photoDatas.count < 4 {
                        PhotosPicker(selection: $photoItems, maxSelectionCount: 4, matching: .images) {
                            VStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 20, weight: .bold))
                                Text(L("添加照片"))
                                    .font(.caption2)
                            }
                            .foregroundStyle(.secondary)
                            .frame(width: 84, height: 84)
                            .background(Color.secondary.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.secondary.opacity(0.25),
                                                  style: StrokeStyle(lineWidth: 1, dash: [4]))
                            )
                        }
                    }
                }
            }
            Text(photoDatas.isEmpty ? "不传照片就用下面的图案封面" : "第一张作为封面")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var coverPreview: some View {
        Group {
            if let first = photoDatas.first, let ui = UIImage(data: first) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(hex: coverColorHex))
                    Image(systemName: coverSymbol)
                        .font(.system(size: 56))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .frame(height: 140)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var symbolPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("封面图案")).font(.subheadline.weight(.bold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
                ForEach(symbols, id: \.self) { s in
                    Button {
                        coverSymbol = s
                    } label: {
                        Image(systemName: s)
                            .font(.system(size: 17))
                            .frame(width: 36, height: 36)
                            .background(
                                Circle().fill(coverSymbol == s
                                              ? Color(hex: coverColorHex).opacity(0.4)
                                              : Color.secondary.opacity(0.1))
                            )
                            .overlay(
                                Circle().strokeBorder(
                                    coverSymbol == s ? Color(hex: coverColorHex) : .clear,
                                    lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("封面颜色")).font(.subheadline.weight(.bold))
            HStack(spacing: 10) {
                ForEach(colors, id: \.self) { hex in
                    Button {
                        coverColorHex = hex
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle().strokeBorder(
                                    .primary.opacity(coverColorHex == hex ? 0.6 : 0),
                                    lineWidth: 2.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("标题")).font(.subheadline.weight(.bold))
            TextField("给这条动态起个标题", text: $title)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var bodyField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("正文")).font(.subheadline.weight(.bold))
            TextEditor(text: $bodyText)
                .frame(minHeight: 110)
                .padding(6)
                .scrollContentBackground(.hidden)
                .background(Color.secondary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var tagPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("标签")).font(.subheadline.weight(.bold))
            HStack(spacing: 8) {
                ForEach(tagOptions, id: \.self) { tag in
                    let on = selectedTags.contains(tag)
                    Button {
                        if on { selectedTags.remove(tag) } else { selectedTags.insert(tag) }
                    } label: {
                        Text("#\(tag)")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(on ? Color(hex: coverColorHex).opacity(0.45)
                                           : Color.secondary.opacity(0.1),
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Feed 详情 Sheet

struct FeedDetailSheet: View {
    @Environment(SocialStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let post: FeedPost
    @State private var commentText: String = ""
    @State private var showLikeAnimation: Bool = false
    @FocusState private var commentFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Cover：有照片时分页浏览，否则图案封面
                    Group {
                        if let files = post.imageFiles, !files.isEmpty {
                            TabView {
                                ForEach(files, id: \.self) { f in
                                    if let ui = FeedImageStore.load(f) {
                                        Color.clear
                                            .overlay(
                                                Image(uiImage: ui)
                                                    .resizable()
                                                    .scaledToFill()
                                            )
                                            .clipped()
                                    }
                                }
                            }
                            .tabViewStyle(.page(indexDisplayMode: files.count > 1 ? .automatic : .never))
                            .aspectRatio(post.coverAspect, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                        } else if let asset = post.coverAsset {
                            Color.clear
                                .overlay(
                                    Image(asset)
                                        .resizable()
                                        .scaledToFill()
                                )
                                .aspectRatio(post.coverAspect, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(Color(hex: post.coverColorHex))
                                Image(systemName: post.coverSymbol)
                                    .font(.system(size: 100))
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                            .aspectRatio(post.coverAspect, contentMode: .fit)
                        }
                    }
                    .overlay {
                        if showLikeAnimation {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 80))
                                .foregroundStyle(.white)
                                .shadow(color: .pink.opacity(0.6), radius: 12)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .onTapGesture(count: 2) {
                        if !store.likedPostIds.contains(post.id) {
                            store.togglePostLike(post.id)
                        }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            showLikeAnimation = true
                        }
                        Task {
                            try? await Task.sleep(for: .milliseconds(800))
                            withAnimation { showLikeAnimation = false }
                        }
                    }

                    // Author + Follow
                    HStack(spacing: 10) {
                        Image(systemName: post.authorIcon)
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color(hex: post.authorColorHex)))
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(post.author).font(.subheadline.weight(.bold))
                                if store.isFollowing(post.author) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(PetPalTheme.success)
                                }
                            }
                            Text(store.isFollowing(post.author) ? "已关注" : "猫友")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                store.toggleFollow(post.author)
                            }
                        } label: {
                            Text(store.isFollowing(post.author) ? "已关注" : "关注")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 14).padding(.vertical, 6)
                                .background(
                                    Capsule().fill(
                                        store.isFollowing(post.author)
                                            ? AnyShapeStyle(Color.gray.opacity(0.15))
                                            : AnyShapeStyle(LinearGradient(colors: [.pink, PetPalTheme.primaryDeep],
                                                                           startPoint: .leading, endPoint: .trailing))
                                    )
                                )
                                .foregroundStyle(store.isFollowing(post.author) ? Color.secondary : Color.white)
                        }
                    }

                    // Content
                    Text(post.title).font(.title3.bold())
                    Text(post.body).font(.body).foregroundStyle(.primary.opacity(0.85))

                    // Tags
                    HStack(spacing: 6) {
                        ForEach(post.tags, id: \.self) { tag in
                            Text("#" + tag)
                                .font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(.pink.opacity(0.12), in: Capsule())
                                .foregroundStyle(.pink)
                        }
                    }

                    // Like / Comment stats
                    HStack(spacing: 20) {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                store.togglePostLike(post.id)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: store.likedPostIds.contains(post.id) ? "heart.fill" : "heart")
                                    .foregroundStyle(store.likedPostIds.contains(post.id) ? .pink : .secondary)
                                    .scaleEffect(store.likedPostIds.contains(post.id) ? 1.15 : 1.0)
                                Text("\(post.likes + (store.likedPostIds.contains(post.id) ? 1 : 0))")
                                    .monospacedDigit()
                                    .foregroundStyle(store.likedPostIds.contains(post.id) ? .pink : .secondary)
                            }
                            .font(.subheadline.weight(.bold))
                        }

                        Button {
                            commentFocused = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "bubble.right")
                                Text("\(store.commentCount(post))")
                                    .monospacedDigit()
                            }
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)

                    Divider()

                    // Comments section
                    let comments = store.commentsFor(post.id)
                    HStack {
                        Text(L("评论"))
                            .font(.headline)
                        Text("\(comments.count)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(.pink)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(.pink.opacity(0.1), in: Capsule())
                    }

                    if comments.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.title)
                                .foregroundStyle(.secondary.opacity(0.4))
                            Text(L("还没有评论，来抢沙发吧"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        ForEach(comments) { comment in
                            commentRow(comment)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(L("帖子"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("关闭")) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                commentInputBar
            }
        }
    }

    // MARK: - Comment Row

    private func commentRow(_ comment: PostComment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: comment.authorIcon)
                .font(.caption)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color(hex: comment.authorColorHex)))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.author)
                        .font(.caption.weight(.bold))
                    if store.isFollowing(comment.author) {
                        Text(L("已关注"))
                            .font(.system(size: 9).weight(.bold))
                            .foregroundStyle(PetPalTheme.primary)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(PetPalTheme.primary.opacity(0.1), in: Capsule())
                    }
                    Spacer()
                    Text(comment.when, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(comment.text)
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.9))

                HStack(spacing: 16) {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            store.toggleCommentLike(comment.id)
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: store.likedCommentIds.contains(comment.id) ? "heart.fill" : "heart")
                                .foregroundStyle(store.likedCommentIds.contains(comment.id) ? Color.pink : Color.gray)
                            Text("\(comment.likeCount + (store.likedCommentIds.contains(comment.id) ? 1 : 0))")
                                .foregroundStyle(Color.gray)
                                .monospacedDigit()
                        }
                        .font(.caption2)
                    }

                    Button {
                        commentText = "@\(comment.author) "
                        commentFocused = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrowshape.turn.up.left")
                            Text(L("回复"))
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Comment Input Bar

    private var commentInputBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.fill")
                .font(.title3)
                .foregroundStyle(PetPalTheme.primary)

            TextField("写评论…", text: $commentText)
                .textFieldStyle(.roundedBorder)
                .focused($commentFocused)

            Button {
                submitComment()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.body)
                    .foregroundStyle(commentText.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : PetPalTheme.primary)
            }
            .disabled(commentText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal).padding(.vertical, 10)
        .background(.bar)
    }

    private func submitComment() {
        let trimmed = commentText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        withAnimation {
            store.addComment(postId: post.id, text: trimmed)
        }
        commentText = ""
        commentFocused = false
    }
}

// MARK: - 配种绝育主视图（独立入口）

struct BreedingView: View {
    enum BreedingTab: String, CaseIterable, Identifiable {
        case matching = "找伴侣"
        case vet = "绝育预约"
        var id: String { rawValue }
    }

    @State private var selectedTab: BreedingTab = .matching
    @State private var store = SocialStore()

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(BreedingTab.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            Group {
                switch selectedTab {
                case .matching: MatchingView(store: store)
                case .vet:      VetView(store: store)
                }
            }
            .environment(store)
        }
        .navigationTitle(L("配种 · 绝育"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 配种（Tinder 风卡片）

struct MatchingView: View {
    let store: SocialStore
    var searchText: String = ""
    @State private var matchedPet: SocialPet?
    @State private var showMatchSheet = false
    @State private var heartBurst = false
    @State private var cancelingBreedingId: UUID?

    /// 搜索过滤：名字 / 品种 / 简介
    private var visiblePets: [SocialPet] {
        guard !searchText.isEmpty else { return store.remainingPets }
        return store.remainingPets.filter { p in
            p.name.lowercased().contains(searchText)
                || p.breed.lowercased().contains(searchText)
                || p.bio.lowercased().contains(searchText)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                matingHero
                // 我的配种预约
                if !store.breedingAppointments.isEmpty {
                    breedingAppointmentsCard
                }

                if let pet = visiblePets.first {
                    petCard(pet)
                    actionButtons(pet)
                } else {
                    emptyState
                }
                Spacer(minLength: 20)
            }
            .padding()
        }
        .alert("取消配种预约", isPresented: Binding(
            get: { cancelingBreedingId != nil },
            set: { if !$0 { cancelingBreedingId = nil } }
        )) {
            Button(L("确认取消"), role: .destructive) {
                if let id = cancelingBreedingId {
                    withAnimation { store.cancelBreeding(id) }
                }
                cancelingBreedingId = nil
            }
            Button(L("保留预约"), role: .cancel) { cancelingBreedingId = nil }
        } message: {
            Text(L("取消后将全额退还费用"))
        }
        .sheet(isPresented: $showMatchSheet) {
            if let pet = matchedPet {
                NavigationStack {
                    BreedingBookingView(pet: pet, store: store)
                }
            }
        }
    }

    /// 顶部 hero：双猫合影 + 粉调叠层
    private var matingHero: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.pink.opacity(0.1))
            .aspectRatio(2.0, contentMode: .fit)
            .overlay {
                Image("mating_hero")
                    .resizable()
                    .scaledToFill()
            }
            .overlay {
                LinearGradient(colors: [.black.opacity(0.5), .clear],
                               startPoint: .bottom, endPoint: .center)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("寻找心动伙伴"))
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text(L("附近优质猫咪 · 配种预约一站搞定"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(12)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "heart.fill")
                    .font(.title3)
                    .foregroundStyle(.pink)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var breedingAppointmentsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("我的配种预约"), systemImage: "heart.circle.fill")
                .font(.headline)
                .foregroundStyle(.pink)

            ForEach(store.breedingAppointments) { appt in
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.pink.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: "heart.fill")
                            .font(.title3)
                            .foregroundStyle(.pink)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isEN ? "With \(appt.petName) · \(appt.service)" : "与 \(appt.petName) · \(appt.service)")
                            .font(.subheadline.weight(.bold))
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            Label(appt.slot, systemImage: "clock")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(appt.price)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.red)
                        }
                    }
                    Spacer()
                    Button {
                        cancelingBreedingId = appt.id
                    } label: {
                        Text(L("取消"))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.red.opacity(0.1))
                            )
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.pink.opacity(0.2), lineWidth: 0.5)
                )
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func petCard(_ pet: SocialPet) -> some View {
        VStack(spacing: 16) {
            ZStack {
                if let photo = pet.photoAsset {
                    Color.clear
                        .overlay(
                            Image(photo)
                                .resizable()
                                .scaledToFill()
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                } else {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(hex: pet.colorHex))
                    Image(systemName: pet.iconSymbol)
                        .font(.system(size: 80))
                        .foregroundStyle(.white)
                }

                // Heart burst on match
                if heartBurst {
                    ForEach(0..<6, id: \.self) { i in
                        Image(systemName: "heart.fill")
                            .font(.title)
                            .foregroundStyle(.pink)
                            .offset(
                                x: cos(Double(i) * .pi / 3) * 80,
                                y: sin(Double(i) * .pi / 3) * 80
                            )
                            .opacity(0)
                            .scaleEffect(0.3)
                    }
                }
            }
            .aspectRatio(0.9, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                Label(pet.distance, systemImage: "location.fill")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(12)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(pet.name).font(.title.bold())
                    Text("· \(pet.gender.rawValue) · \(pet.age)").foregroundStyle(.secondary)
                    Spacer()
                }
                Text(pet.breed).font(.subheadline).foregroundStyle(.secondary)
                Text(pet.bio).font(.body).padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func actionButtons(_ pet: SocialPet) -> some View {
        HStack(spacing: 24) {
            Button {
                withAnimation { store.pass(pet.id) }
            } label: {
                Image(systemName: "xmark")
                    .font(.title2.bold())
                    .foregroundStyle(.red)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(.thinMaterial))
                    .overlay(Circle().stroke(.red.opacity(0.5), lineWidth: 2))
            }
            Button {
                withAnimation { store.like(pet.id) }
                // 假匹配：50% 概率成功
                if Bool.random() {
                    matchedPet = pet
                    showMatchSheet = true
                }
            } label: {
                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundStyle(.pink)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(.thinMaterial))
                    .overlay(Circle().stroke(.pink.opacity(0.6), lineWidth: 2))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.text.square").font(.system(size: 60)).foregroundStyle(.secondary)
            Text(L("附近的猫都看完了")).foregroundStyle(.secondary)
            Text(isEN ? "\(store.likedPetIds.count) liked · \(store.passedPetIds.count) passed" : "已喜欢 \(store.likedPetIds.count) 只 · 已跳过 \(store.passedPetIds.count) 只")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }
}

// MARK: - 配种预约

struct BreedingBookingView: View {
    let pet: SocialPet
    let store: SocialStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedService = "自然配种"
    @State private var selectedDate: Date = .now.addingTimeInterval(86400)
    @State private var selectedSlot: String?
    @State private var showPayment = false
    @State private var showSuccess = false

    private let services = ["自然配种", "人工授精", "配种+孕检套餐", "配种咨询"]
    private let timeSlots = ["09:00", "10:30", "13:00", "14:30", "16:00", "17:30"]

    private var priceValue: String {
        switch selectedService {
        case "自然配种": return "¥800"
        case "人工授精": return "¥1500"
        case "配种+孕检套餐": return "¥2200"
        default: return "¥200"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 匹配成功头部
                matchHeader

                // 服务选择
                serviceSection

                // 日期
                dateSection

                // 时段
                slotSection

                // 订单摘要
                if selectedSlot != nil {
                    summarySection
                }

                Spacer(minLength: 80)
            }
            .padding()
        }
        .navigationTitle(L("预约配种"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L("取消")) { dismiss() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .fullScreenCover(isPresented: $showPayment) {
            BreedingPaymentView(
                petName: pet.name,
                service: selectedService,
                date: formatDate(selectedDate),
                slot: selectedSlot ?? "",
                price: priceValue,
                onComplete: {
                    showPayment = false
                    let slot = "\(formatDate(selectedDate)) \(selectedSlot ?? "")"
                    _ = store.bookBreeding(pet: pet, service: selectedService, slot: slot, price: priceValue)
                    showSuccess = true
                },
                onCancel: {
                    showPayment = false
                }
            )
        }
        .navigationDestination(isPresented: $showSuccess) {
            BreedingSuccessView(
                petName: pet.name,
                petBreed: pet.breed,
                service: selectedService,
                date: formatDate(selectedDate),
                slot: selectedSlot ?? "",
                price: priceValue,
                onDone: { dismiss() }
            )
        }
    }

    private var matchHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                if let photo = pet.photoAsset {
                    Image(photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(hex: pet.colorHex))
                        .frame(width: 60, height: 60)
                    Image(systemName: pet.iconSymbol)
                        .font(.title2)
                        .foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill").foregroundStyle(.pink)
                    Text(L("匹配成功！")).font(.headline).foregroundStyle(.pink)
                }
                Text("\(pet.name) · \(pet.breed) · \(pet.gender.rawValue) · \(pet.age)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(pet.distance)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.pink.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.pink.opacity(0.2), lineWidth: 1)
        )
    }

    private var serviceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("选择服务"), systemImage: "list.bullet.clipboard")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(services, id: \.self) { svc in
                    Button {
                        selectedService = svc
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: selectedService == svc ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedService == svc ? Color.pink : Color.secondary)
                                .font(.caption)
                            Text(svc)
                                .font(.subheadline)
                                .foregroundStyle(selectedService == svc ? Color.pink : Color.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selectedService == svc ? Color.pink.opacity(0.1) : Color.secondary.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(selectedService == svc ? Color.pink.opacity(0.3) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("选择日期"), systemImage: "calendar")
                .font(.headline)

            DatePicker("预约日期", selection: $selectedDate,
                       in: Date.now.addingTimeInterval(86400)...Date.now.addingTimeInterval(86400 * 14),
                       displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(.pink)
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var slotSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("选择时段"), systemImage: "clock")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 10)], spacing: 10) {
                ForEach(timeSlots, id: \.self) { slot in
                    Button {
                        withAnimation(.spring(response: 0.25)) {
                            selectedSlot = slot
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text(slot)
                                .font(.subheadline.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selectedSlot == slot ? Color.pink : Color.secondary.opacity(0.08))
                        )
                        .foregroundStyle(selectedSlot == slot ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("订单确认"), systemImage: "doc.text")
                .font(.headline)

            VStack(spacing: 8) {
                summaryRow("配对", value: pet.name)
                Divider()
                summaryRow("品种", value: pet.breed)
                Divider()
                summaryRow("服务", value: selectedService)
                Divider()
                summaryRow("日期", value: formatDate(selectedDate))
                Divider()
                summaryRow("时间", value: selectedSlot ?? "")
                Divider()
                HStack {
                    Text(L("费用"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(priceValue)
                        .font(.title3.bold())
                        .foregroundStyle(.red)
                }
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("费用"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(selectedSlot != nil ? priceValue : "--")
                    .font(.title2.bold())
                    .foregroundStyle(.red)
            }
            Spacer()
            Button {
                showPayment = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "creditcard.fill")
                    Text(L("支付预约"))
                        .font(.headline)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 28).padding(.vertical, 14)
                .background(
                    LinearGradient(colors: [.pink, .orange],
                                   startPoint: .leading, endPoint: .trailing),
                    in: Capsule()
                )
                .shadow(color: .pink.opacity(0.3), radius: 10, x: 0, y: 4)
            }
            .disabled(selectedSlot == nil)
            .opacity(selectedSlot == nil ? 0.5 : 1)
        }
        .padding(.horizontal).padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M月d日 EEEE"
        f.locale = Locale(identifier: "zh_CN")
        return f.string(from: date)
    }
}

// MARK: - Breeding Payment View

struct BreedingPaymentView: View {
    let petName: String
    let service: String
    let date: String
    let slot: String
    let price: String
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var phase: PayPhase = .ready
    @State private var progress: Double = 0
    @State private var ringRotation: Double = 0

    enum PayPhase { case ready, processing, success }

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                ZStack {
                    switch phase {
                    case .ready:
                        ZStack {
                            Circle().stroke(Color.white.opacity(0.1), lineWidth: 4)
                                .frame(width: 120, height: 120)
                            Image(systemName: "heart.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(LinearGradient(colors: [.pink, .orange],
                                                                startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    case .processing:
                        ZStack {
                            Circle().stroke(Color.white.opacity(0.1), lineWidth: 4)
                                .frame(width: 120, height: 120)
                            Circle().trim(from: 0, to: 0.3)
                                .stroke(LinearGradient(colors: [.pink, .orange],
                                                       startPoint: .leading, endPoint: .trailing),
                                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .frame(width: 120, height: 120)
                                .rotationEffect(.degrees(ringRotation))
                            Text("\(Int(progress * 100))%")
                                .font(.title2.weight(.bold).monospacedDigit())
                                .foregroundStyle(.white)
                        }
                    case .success:
                        ZStack {
                            Circle().fill(Color.green)
                                .frame(width: 120, height: 120)
                                .shadow(color: .green.opacity(0.5), radius: 20)
                            Image(systemName: "checkmark")
                                .font(.system(size: 50, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(height: 160)

                VStack(spacing: 8) {
                    Text(price)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(phase == .success ? "支付成功" : service)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                    if phase == .ready {
                        Text(isEN ? "Mating service with \(petName)" : "与 \(petName) 配种服务")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                        Text("\(date) \(slot)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                Spacer()

                if phase == .ready {
                    VStack(spacing: 12) {
                        Button { startPayment() } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "faceid").font(.title3)
                                Text(L("确认支付")).font(.headline)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(colors: [.pink, .orange],
                                               startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                        }
                        Button(L("取消"), action: onCancel)
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.vertical, 8)
                    }
                    .padding(.horizontal, 40)
                }

                if phase == .success {
                    Button {
                        onComplete()
                    } label: {
                        Text(L("完成"))
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.green, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(.horizontal, 40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer().frame(height: 40)
            }
        }
    }

    private func startPayment() {
        withAnimation(.easeInOut(duration: 0.3)) { phase = .processing }
        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { ringRotation = 360 }
        Task {
            for i in 1...20 {
                try? await Task.sleep(for: .milliseconds(80))
                withAnimation(.easeOut(duration: 0.1)) { progress = Double(i) / 20.0 }
            }
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { phase = .success }
        }
    }
}

// MARK: - Breeding Success View

struct BreedingSuccessView: View {
    let petName: String
    let petBreed: String
    let service: String
    let date: String
    let slot: String
    let price: String
    var onDone: (() -> Void)?

    @State private var showCheck = false
    @State private var showDetails = false
    @State private var confettiOffset: [CGSize] = (0..<12).map { _ in .zero }

    var body: some View {
        ZStack {
            GlassPageBackground()

            VStack(spacing: 24) {
                Spacer()

                ZStack {
                    ForEach(0..<12, id: \.self) { i in
                        Circle()
                            .fill(confettiColor(i))
                            .frame(width: 8, height: 8)
                            .offset(confettiOffset[i])
                            .opacity(showCheck ? 0 : 1)
                    }

                    Circle()
                        .fill(LinearGradient(colors: [.pink, .orange],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 100, height: 100)
                        .shadow(color: .pink.opacity(0.3), radius: 20)
                        .scaleEffect(showCheck ? 1.0 : 0.3)
                        .opacity(showCheck ? 1 : 0)

                    Image(systemName: "checkmark")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.white)
                        .scaleEffect(showCheck ? 1.0 : 0.3)
                        .opacity(showCheck ? 1 : 0)
                }
                .frame(height: 120)

                Text(L("配种预约成功"))
                    .font(.title.bold())
                    .opacity(showDetails ? 1 : 0)
                    .offset(y: showDetails ? 0 : 10)

                VStack(spacing: 12) {
                    detailRow(icon: "heart.fill", color: .pink, label: "配对", value: petName)
                    Divider()
                    detailRow(icon: "cat.fill", color: .orange, label: "品种", value: petBreed)
                    Divider()
                    detailRow(icon: "scissors", color: .purple, label: "服务", value: service)
                    Divider()
                    detailRow(icon: "calendar", color: .orange, label: "日期", value: date)
                    Divider()
                    detailRow(icon: "clock", color: .green, label: "时间", value: slot)
                    Divider()
                    HStack(spacing: 10) {
                        Image(systemName: "yensign.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.red)
                        Text(L("费用"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(price)
                            .font(.title3.bold())
                            .foregroundStyle(.red)
                    }
                    Divider()
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                        Text(L("支付状态"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(L("已支付"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.green)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.5), lineWidth: 0.5)
                )
                .opacity(showDetails ? 1 : 0)
                .offset(y: showDetails ? 0 : 20)

                Spacer()

            }
            .padding()
        }
        .navigationTitle(L("预约成功"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) {
                showCheck = true
                for i in 0..<12 {
                    let angle = Double(i) * (360.0 / 12.0) * .pi / 180
                    let dist: CGFloat = CGFloat.random(in: 60...100)
                    confettiOffset[i] = CGSize(width: cos(angle) * dist, height: sin(angle) * dist)
                }
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.4)) {
                showDetails = true
            }
        }
    }

    private func detailRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
        }
    }

    private func confettiColor(_ i: Int) -> Color {
        [Color.pink, .orange, .red, .yellow, .purple, .cyan][i % 6]
    }
}

// MARK: - 绝育预约

struct VetView: View {
    let store: SocialStore
    var searchText: String = ""
    @State private var cancelingId: UUID?
    // 医疗服务（疫苗/体检等）从商城移到本页；独立入口没有购物车环境，自持一份
    @State private var cart = CartStore()
    @State private var detailService: SKU?

    /// 从商城目录里拿医疗类 SKU，同样吃顶部搜索词
    private var filteredServices: [SKU] {
        let meds = ShopCatalog.all.filter { $0.category == .medical }
        guard !searchText.isEmpty else { return meds }
        return meds.filter {
            $0.name.lowercased().contains(searchText)
                || $0.subtitle.lowercased().contains(searchText)
        }
    }

    /// 搜索过滤：医院名 / 地址 / 服务项目
    private var filteredClinics: [VetClinic] {
        guard !searchText.isEmpty else { return SocialCatalog.clinics }
        return SocialCatalog.clinics.filter { c in
            c.name.lowercased().contains(searchText)
                || c.address.lowercased().contains(searchText)
                || c.services.contains { $0.lowercased().contains(searchText) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                vetHero
                if !store.appointments.isEmpty {
                    myAppointments
                }
                if !filteredServices.isEmpty {
                    medicalServicesSection
                }
                ForEach(filteredClinics) { clinic in
                    clinicCard(clinic)
                }
                if filteredClinics.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .padding(.top, 40)
                }
            }
            .padding()
        }
        .alert("取消预约", isPresented: Binding(
            get: { cancelingId != nil },
            set: { if !$0 { cancelingId = nil } }
        )) {
            Button(L("确认取消"), role: .destructive) {
                if let id = cancelingId {
                    withAnimation { store.cancelAppointment(id) }
                }
                cancelingId = nil
            }
            Button(L("保留预约"), role: .cancel) { cancelingId = nil }
        } message: {
            Text(L("取消后将全额退还费用"))
        }
        .sheet(item: $detailService) { sku in
            NavigationStack { ProductDetailView(sku: sku) }
                .environment(cart)
                .presentationDetents([.large])
        }
    }

    /// 顶部 hero：兽医查体实拍 + 标题叠层（与训猫/纪念页同一套横幅语言）
    private var vetHero: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.blue.opacity(0.1))
            .aspectRatio(2.2, contentMode: .fit)
            .overlay {
                Image("vet_hero")
                    .resizable()
                    .scaledToFill()
            }
            .overlay {
                LinearGradient(colors: [.black.opacity(0.55), .clear],
                               startPoint: .bottom, endPoint: .center)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("宠物医疗"))
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text(L("疫苗 · 体检 · 绝育，一站式预约"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: 医疗服务（原商城「疫苗/体检」类目整体迁入）

    private var medicalServicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("医疗服务"), systemImage: "cross.case.fill")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(filteredServices) { sku in
                    serviceCard(sku)
                }
            }
        }
    }

    private func serviceCard(_ sku: SKU) -> some View {
        Button {
            detailService = sku
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                // 底座定尺寸 → overlay 放图 → clipShape 裁溢出，横图不会撑爆两列网格
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(sku.category.color.opacity(0.12))
                    .aspectRatio(1.5, contentMode: .fit)
                    .overlay {
                        if let photo = sku.photo {
                            Image(photo)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: sku.icon)
                                .font(.system(size: 30))
                                .foregroundStyle(sku.category.color)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(sku.name)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text(sku.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack {
                    Text("¥\(Int(sku.price))")
                        .font(.callout.bold())
                        .foregroundStyle(.red)
                    Spacer()
                    Text(L("预约"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.blue)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    private var myAppointments: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("我的预约"), systemImage: "calendar.badge.checkmark")
                .font(.headline)

            ForEach(store.appointments) { appt in
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.green.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(appt.clinicName)
                            .font(.subheadline.weight(.bold))
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            Label(appt.slot, systemImage: "clock")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(appt.price)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.red)
                        }
                    }
                    Spacer()
                    Button {
                        cancelingId = appt.id
                    } label: {
                        Text(L("取消"))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.red.opacity(0.1))
                            )
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.green.opacity(0.2), lineWidth: 0.5)
                )
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func clinicCard(_ clinic: VetClinic) -> some View {
        NavigationLink(destination: SlotPickerView(clinic: clinic, store: store)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    if let pa = clinic.photoAsset {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.blue.opacity(0.10))
                            .frame(width: 52, height: 52)
                            .overlay {
                                Image(pa)
                                    .resizable()
                                    .scaledToFill()
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    Text(clinic.name).font(.headline)
                    Spacer()
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                        Text(String(format: "%.1f", clinic.rating)).font(.caption.bold())
                    }
                }
                Label(clinic.address, systemImage: "location.fill")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text(clinic.priceRange)
                        .font(.callout.bold())
                        .foregroundStyle(.red)
                    Spacer()
                    Text(L("立即预约"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.blue)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
                Divider()
                FlowLayout(spacing: 6) {
                    ForEach(clinic.services, id: \.self) { svc in
                        Text(svc)
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                }
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }
}

struct SlotPickerView: View {
    let clinic: VetClinic
    let store: SocialStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSlot: String?
    @State private var selectedDate: Date = .now.addingTimeInterval(86400)
    @State private var selectedService: String = "公猫绝育"
    @State private var showPayment = false
    @State private var showSuccess = false

    private var priceValue: String {
        // Extract first price from range like "¥1280-1680"
        let range = clinic.priceRange
        let nums = range.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
        return nums.first.map { "¥\($0)" } ?? clinic.priceRange
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Clinic info header
                clinicHeader

                // Service selection
                serviceSection

                // Date picker
                dateSection

                // Time slots
                slotSection

                // Order summary
                if selectedSlot != nil {
                    summarySection
                }

                Spacer(minLength: 80)
            }
            .padding()
        }
        .navigationTitle(L("预约绝育"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .fullScreenCover(isPresented: $showPayment) {
            VetPaymentView(
                clinicName: clinic.name,
                slot: selectedSlot ?? "",
                date: formatDate(selectedDate),
                service: selectedService,
                price: priceValue,
                onComplete: {
                    showPayment = false
                    let slot = "\(formatDate(selectedDate)) \(selectedSlot ?? "")"
                    _ = store.book(clinic, slot: slot, price: priceValue)
                    showSuccess = true
                },
                onCancel: {
                    showPayment = false
                }
            )
        }
        .navigationDestination(isPresented: $showSuccess) {
            VetBookingSuccessView(
                clinicName: clinic.name,
                service: selectedService,
                date: formatDate(selectedDate),
                slot: selectedSlot ?? "",
                price: priceValue
            )
        }
    }

    // MARK: - Sections

    private var clinicHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 50, height: 50)
                    Image(systemName: "cross.case.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(clinic.name)
                        .font(.headline)
                    Label(clinic.address, systemImage: "location.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 12) {
                HStack(spacing: 2) {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                    Text(String(format: "%.1f", clinic.rating)).font(.subheadline.weight(.bold))
                }
                Text(clinic.priceRange)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.red)
            }
            .font(.caption)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var serviceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("选择服务"), systemImage: "list.bullet.clipboard")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(clinic.services, id: \.self) { svc in
                    Button {
                        selectedService = svc
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: selectedService == svc ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedService == svc ? .blue : .secondary)
                                .font(.caption)
                            Text(svc)
                                .font(.subheadline)
                                .foregroundStyle(selectedService == svc ? .blue : .primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selectedService == svc ? Color.blue.opacity(0.1) : Color.secondary.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(selectedService == svc ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("选择日期"), systemImage: "calendar")
                .font(.headline)

            DatePicker("预约日期", selection: $selectedDate,
                       in: Date.now.addingTimeInterval(86400)...Date.now.addingTimeInterval(86400 * 14),
                       displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(.blue)
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var slotSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("选择时段"), systemImage: "clock")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                ForEach(clinic.slots, id: \.self) { slot in
                    // Extract just the time part
                    let timeStr = slot.components(separatedBy: " ").last ?? slot
                    Button {
                        withAnimation(.spring(response: 0.25)) {
                            selectedSlot = timeStr
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text(timeStr)
                                .font(.subheadline.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selectedSlot == timeStr ? Color.blue : Color.secondary.opacity(0.08))
                        )
                        .foregroundStyle(selectedSlot == timeStr ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("订单确认"), systemImage: "doc.text")
                .font(.headline)

            VStack(spacing: 8) {
                summaryRow("医院", value: clinic.name)
                Divider()
                summaryRow("服务", value: selectedService)
                Divider()
                summaryRow("日期", value: formatDate(selectedDate))
                Divider()
                summaryRow("时间", value: selectedSlot ?? "")
                Divider()
                HStack {
                    Text(L("费用"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(priceValue)
                        .font(.title3.bold())
                        .foregroundStyle(.red)
                }
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("费用"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(selectedSlot != nil ? priceValue : "--")
                    .font(.title2.bold())
                    .foregroundStyle(.red)
            }
            Spacer()
            Button {
                showPayment = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "creditcard.fill")
                    Text(L("支付预约"))
                        .font(.headline)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 28).padding(.vertical, 14)
                .background(
                    LinearGradient(colors: [.blue, .cyan],
                                   startPoint: .leading, endPoint: .trailing),
                    in: Capsule()
                )
                .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 4)
            }
            .disabled(selectedSlot == nil)
            .opacity(selectedSlot == nil ? 0.5 : 1)
        }
        .padding(.horizontal).padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M月d日 EEEE"
        f.locale = Locale(identifier: "zh_CN")
        return f.string(from: date)
    }
}

// MARK: - Vet Payment View

struct VetPaymentView: View {
    let clinicName: String
    let slot: String
    let date: String
    let service: String
    let price: String
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var phase: VetPayPhase = .ready
    @State private var progress: Double = 0
    @State private var ringRotation: Double = 0

    enum VetPayPhase { case ready, processing, success }

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Animation
                ZStack {
                    switch phase {
                    case .ready:
                        ZStack {
                            Circle().stroke(Color.white.opacity(0.1), lineWidth: 4)
                                .frame(width: 120, height: 120)
                            Image(systemName: "cross.case.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.white)
                        }
                    case .processing:
                        ZStack {
                            Circle().stroke(Color.white.opacity(0.1), lineWidth: 4)
                                .frame(width: 120, height: 120)
                            Circle().trim(from: 0, to: 0.3)
                                .stroke(LinearGradient(colors: [.blue, .cyan],
                                                       startPoint: .leading, endPoint: .trailing),
                                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .frame(width: 120, height: 120)
                                .rotationEffect(.degrees(ringRotation))
                            Text("\(Int(progress * 100))%")
                                .font(.title2.weight(.bold).monospacedDigit())
                                .foregroundStyle(.white)
                        }
                    case .success:
                        ZStack {
                            Circle().fill(Color.green)
                                .frame(width: 120, height: 120)
                                .shadow(color: .green.opacity(0.5), radius: 20)
                            Image(systemName: "checkmark")
                                .font(.system(size: 50, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(height: 160)

                // Info
                VStack(spacing: 8) {
                    Text(price)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(phase == .success ? "支付成功" : service)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                    if phase == .ready {
                        Text("\(clinicName)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                        Text("\(date) \(slot)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                Spacer()

                // Buttons
                if phase == .ready {
                    VStack(spacing: 12) {
                        Button { startPayment() } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "faceid").font(.title3)
                                Text(L("确认支付")).font(.headline)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(colors: [.blue, .cyan],
                                               startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                        }
                        Button(L("取消"), action: onCancel)
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.vertical, 8)
                    }
                    .padding(.horizontal, 40)
                }

                if phase == .success {
                    Button {
                        onComplete()
                    } label: {
                        Text(L("完成"))
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.green, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(.horizontal, 40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer().frame(height: 40)
            }
        }
    }

    private func startPayment() {
        withAnimation(.easeInOut(duration: 0.3)) { phase = .processing }
        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { ringRotation = 360 }
        Task {
            for i in 1...20 {
                try? await Task.sleep(for: .milliseconds(80))
                withAnimation(.easeOut(duration: 0.1)) { progress = Double(i) / 20.0 }
            }
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { phase = .success }
        }
    }
}

// MARK: - Vet Booking Success

struct VetBookingSuccessView: View {
    let clinicName: String
    let service: String
    let date: String
    let slot: String
    let price: String

    @State private var showCheck = false
    @State private var showDetails = false
    @State private var confettiOffset: [CGSize] = (0..<12).map { _ in .zero }

    var body: some View {
        ZStack {
            GlassPageBackground()

            VStack(spacing: 24) {
                Spacer()

                // Animated checkmark
                ZStack {
                    ForEach(0..<12, id: \.self) { i in
                        Circle()
                            .fill(confettiColor(i))
                            .frame(width: 8, height: 8)
                            .offset(confettiOffset[i])
                            .opacity(showCheck ? 0 : 1)
                    }

                    Circle()
                        .fill(LinearGradient(colors: [.blue, .cyan],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 100, height: 100)
                        .shadow(color: .blue.opacity(0.3), radius: 20)
                        .scaleEffect(showCheck ? 1.0 : 0.3)
                        .opacity(showCheck ? 1 : 0)

                    Image(systemName: "checkmark")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.white)
                        .scaleEffect(showCheck ? 1.0 : 0.3)
                        .opacity(showCheck ? 1 : 0)
                }
                .frame(height: 120)

                Text(L("预约成功"))
                    .font(.title.bold())
                    .opacity(showDetails ? 1 : 0)
                    .offset(y: showDetails ? 0 : 10)

                // Details card
                VStack(spacing: 12) {
                    detailRow(icon: "cross.case.fill", color: .blue, label: "医院", value: clinicName)
                    Divider()
                    detailRow(icon: "scissors", color: .purple, label: "服务", value: service)
                    Divider()
                    detailRow(icon: "calendar", color: .orange, label: "日期", value: date)
                    Divider()
                    detailRow(icon: "clock", color: .green, label: "时间", value: slot)
                    Divider()
                    HStack(spacing: 10) {
                        Image(systemName: "yensign.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.red)
                        Text(L("费用"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(price)
                            .font(.title3.bold())
                            .foregroundStyle(.red)
                    }
                    Divider()
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                        Text(L("支付状态"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(L("已支付"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.green)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.5), lineWidth: 0.5)
                )
                .opacity(showDetails ? 1 : 0)
                .offset(y: showDetails ? 0 : 20)

                Spacer()

            }
            .padding()
        }
        .navigationTitle(L("预约成功"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) {
                showCheck = true
                for i in 0..<12 {
                    let angle = Double(i) * (360.0 / 12.0) * .pi / 180
                    let dist: CGFloat = CGFloat.random(in: 60...100)
                    confettiOffset[i] = CGSize(width: cos(angle) * dist, height: sin(angle) * dist)
                }
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.4)) {
                showDetails = true
            }
        }
    }

    private func detailRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
        }
    }

    private func confettiColor(_ i: Int) -> Color {
        [Color.blue, .cyan, .green, .yellow, .purple, .pink][i % 6]
    }
}

// MARK: - 纪念

struct MemorialView: View {
    @Environment(SocialStore.self) private var store
    var searchText: String = ""
    @AppStorage("petProfileJson") private var petProfileJson: String = ""
    @State private var profile: PetProfile = .empty
    @State private var newMessage: String = ""
    @State private var candleAnimating: Bool = false

    /// 搜索过滤：留言人 / 留言内容
    private var filteredMessages: [MemorialMessage] {
        guard !searchText.isEmpty else { return store.memorialMessages }
        return store.memorialMessages.filter { m in
            m.author.lowercased().contains(searchText)
                || m.text.lowercased().contains(searchText)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if profile.isDeceased {
                    memorialContent
                } else {
                    toggleSection
                }
            }
            .padding()
        }
        .onAppear(perform: loadProfile)
    }

    // MARK: - Sub views

    /// 顶部 hero：暮色海岸 + 左下标题（与训猫/配种/医疗页同一套横幅语言），两种状态共用
    private var memorialHero: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.indigo.opacity(0.12))
            .aspectRatio(2.0, contentMode: .fit)
            .overlay {
                Image("memorial_sky")
                    .resizable()
                    .scaledToFill()
            }
            .overlay {
                LinearGradient(colors: [.black.opacity(0.55), .clear],
                               startPoint: .bottom, endPoint: .center)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("思念，不落幕"))
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text(L("为离开的它留一盏灯、存一页回忆"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(12)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "moon.stars.fill")
                    .font(.title3)
                    .foregroundStyle(.indigo)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var toggleSection: some View {
        VStack(spacing: 16) {
            memorialHero
            Text(L("纪念模式未开启"))
                .font(.title3.weight(.bold))
            Text(L("当宠物离开后，可在此为它建立纪念页\n保留照片、回忆和访客的祝福"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Toggle(isOn: Binding(
                get: { profile.isDeceased },
                set: { v in
                    profile.isDeceased = v
                    if v && profile.deceasedAt == nil { profile.deceasedAt = .now }
                    save()
                }
            )) {
                Text(L("开启纪念模式")).font(.callout)
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    private var memorialContent: some View {
        VStack(spacing: 20) {
            memorialHero
            // 黑白头像 + 名字 + 时间
            VStack(spacing: 10) {
                avatarView
                Text(profile.name.isEmpty ? "我的宠物" : profile.name)
                    .font(.title2.bold())
                if let bday = profile.birthday, let dday = profile.deceasedAt {
                    Text("\(format(bday)) — \(format(dday))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else if let dday = profile.deceasedAt {
                    Text(isEN ? "Left on \(format(dday))" : "于 \(format(dday)) 离开")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // 蜡烛
            candleSection

            // 留言
            messageSection

            // 关闭纪念模式
            Button(role: .destructive) {
                profile.isDeceased = false
                save()
            } label: {
                Label(L("关闭纪念模式"), systemImage: "moon.zzz")
                    .font(.caption)
            }
            .padding(.top, 4)
        }
    }

    private var avatarView: some View {
        Group {
            if let av = profile.avatarFilename, let img = PetMediaStore.loadImage(av) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .grayscale(0.9)
                    .opacity(0.85)
            } else {
                Image(systemName: "pawprint.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(20)
                    .foregroundStyle(.indigo.opacity(0.4))
            }
        }
        .frame(width: 140, height: 140)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 3))
    }

    private var candleSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.system(size: 50))
                .foregroundStyle(LinearGradient(colors: [.yellow, .orange],
                                                startPoint: .top, endPoint: .bottom))
                .scaleEffect(candleAnimating ? 1.3 : 1.0)
                .opacity(candleAnimating ? 0.6 : 1.0)
                .animation(.easeInOut(duration: 0.6), value: candleAnimating)

            Text(isEN ? "\(store.candlesLit) candles lit" : "已点亮 \(store.candlesLit) 盏灯")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))

            Button {
                store.lightCandle()
                candleAnimating = true
                Task {
                    try? await Task.sleep(for: .milliseconds(700))
                    candleAnimating = false
                }
            } label: {
                Label(L("点亮一盏灯"), systemImage: "flame")
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(LinearGradient(colors: [.yellow, .orange],
                                               startPoint: .leading, endPoint: .trailing),
                                in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            // 祈愿蜡烛实景打底，压暗保证白字可读
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black)
                .overlay {
                    Image("memorial_candle")
                        .resizable()
                        .scaledToFill()
                        .opacity(0.6)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        )
    }

    private var messageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L("访客留言"), systemImage: "text.quote").font(.headline)
                Spacer()
                Text(isEN ? "\(store.memorialMessages.count)" : "\(store.memorialMessages.count) 条")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                TextField("写下你的怀念…", text: $newMessage)
                    .textFieldStyle(.roundedBorder)
                Button {
                    submitMessage()
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .disabled(newMessage.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(filteredMessages) { msg in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(msg.author).font(.subheadline.weight(.bold))
                        Spacer()
                        Text(msg.when, style: .relative)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(msg.text).font(.callout).foregroundStyle(.primary)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - logic

    private func loadProfile() {
        if !petProfileJson.isEmpty,
           let data = petProfileJson.data(using: .utf8),
           let p = try? JSONDecoder().decode(PetProfile.self, from: data) {
            profile = p
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profile),
           let s = String(data: data, encoding: .utf8) {
            petProfileJson = s
        }
    }

    private func submitMessage() {
        let trimmed = newMessage.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        store.memorialMessages.insert(
            MemorialMessage(author: "我", text: trimmed, when: .now),
            at: 0
        )
        newMessage = ""
    }

    private func format(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd"
        return f.string(from: d)
    }
}

// MARK: - Helpers

extension Color {
    /// Hex without `#` 前缀，例如 "F8B5C0"。失败 fallback 灰色
    init(hex: String) {
        let s = hex.trimmingCharacters(in: .alphanumerics.inverted)
        guard s.count == 6, let v = UInt64(s, radix: 16) else {
            self = .gray
            return
        }
        self = Color(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}

/// 简单 FlowLayout（iOS 16+）— SwiftUI 没原生 wrap stack，借 Layout protocol 写一个
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var height: CGFloat = 0
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            if x + size.width > width {
                x = 0
                height += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
