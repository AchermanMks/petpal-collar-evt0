import SwiftUI
import Observation

// MARK: - 数据模型

enum ShopCategory: String, Codable, CaseIterable, Identifiable {
    case food = "食品"
    case toy = "玩具"
    case apparel = "服装"
    case grooming = "洗澡"
    case accessory = "周边"
    case medical = "医疗"      // 诊疗服务：不在商城露出，收进「发现 · 医疗」页

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .food:        return "fish.fill"
        case .toy:         return "teddybear.fill"
        case .apparel:     return "tshirt.fill"
        case .grooming:    return "bubbles.and.sparkles.fill"
        case .accessory:   return "gift.fill"
        case .medical:     return "cross.case.fill"
        }
    }

    /// 商城展示的分类（医疗服务收进「发现 · 医疗」页，不在商城露出）
    static var shopCases: [ShopCategory] { allCases.filter { $0 != .medical } }

    var color: Color {
        switch self {
        case .food:        return .orange
        case .toy:         return .green
        case .apparel:     return .indigo
        case .grooming:    return .cyan
        case .accessory:   return .purple
        case .medical:     return .red
        }
    }
}

struct SKU: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let category: ShopCategory
    let name: String
    let subtitle: String
    let price: Double
    let originalPrice: Double?
    let icon: String
    let description: String
    let badges: [String]
    /// 商品实拍图（Assets 里的 shop_* 素材，CC0/公有领域）。没有时回落到 icon 图标。
    var photo: String? = nil
}

struct CartItem: Codable, Equatable, Identifiable {
    var id: String { skuId }
    let skuId: String
    var quantity: Int
}

struct Order: Identifiable, Codable, Equatable {
    let id: UUID
    let items: [CartItem]
    let totalPrice: Double
    let placedAt: Date
}

// MARK: - Catalog（demo 硬编码）

enum ShopCatalog {
    static let all: [SKU] = [
        // 猫粮
        SKU(id: "food-dry-01", category: .food, name: "全价无谷干粮 2kg",
            subtitle: "成猫主粮 / 鸡肉配方", price: 168, originalPrice: 198,
            icon: "fish.fill",
            description: "鸡肉为第一原料，添加 omega-3 鱼油。无谷物、无副产物，适合敏感肠胃成猫。",
            badges: ["热销"], photo: "shop_food_dry"),
        SKU(id: "food-wet-01", category: .food, name: "主食罐头 80g × 12",
            subtitle: "高肉低淀粉 / 慕斯状", price: 96, originalPrice: nil,
            icon: "cup.and.saucer.fill",
            description: "12 罐组合装，4 种口味。85% 肉含量，幼猫成猫通用。",
            badges: [], photo: "shop_food_wet"),
        SKU(id: "food-treat-01", category: .food, name: "冻干鸡胸 100g",
            subtitle: "零食 / 训练奖励", price: 58, originalPrice: 68,
            icon: "leaf.fill",
            description: "纯鸡胸冻干，无添加。适合零食和训练奖励，3 个月以上猫咪。",
            badges: ["新品"], photo: "shop_food_treat"),
        SKU(id: "food-treat-02", category: .food, name: "营养猫条 30 支",
            subtitle: "零食 / 手喂互动", price: 45, originalPrice: 59,
            icon: "hand.point.up.left.fill",
            description: "鸡肉金枪鱼双拼，无诱食剂。手喂增进感情，也可拌粮。",
            badges: ["热销"], photo: "shop_food_treat2"),
        SKU(id: "food-grass-01", category: .food, name: "猫草盆栽",
            subtitle: "小麦草 / 助吐毛球", price: 15, originalPrice: nil,
            icon: "leaf.fill",
            description: "新鲜小麦草盆栽，帮助排出毛球、补充纤维素。收货后放阳台可养 2-3 周。",
            badges: [], photo: "shop_food_grass2"),

        // 玩具
        SKU(id: "toy-wand-01", category: .toy, name: "羽毛逗猫棒",
            subtitle: "铃铛羽毛 / 可替换头", price: 29, originalPrice: nil,
            icon: "wand.and.rays",
            description: "碳纤维杆身轻巧耐甩，羽毛头带铃铛，附赠 2 个替换头。",
            badges: [], photo: "shop_toy_wand"),
        SKU(id: "toy-post-01", category: .toy, name: "剑麻猫抓柱",
            subtitle: "天然剑麻 / 稳固底盘", price: 89, originalPrice: 109,
            icon: "cylinder.split.1x2.fill",
            description: "整柱天然剑麻缠绕，加重底盘不易翻倒。保护沙发，磨爪必备。",
            badges: [], photo: "shop_toy_post"),
        SKU(id: "toy-tree-01", category: .toy, name: "多层猫爬架",
            subtitle: "跳台 / 猫窝 / 抓柱一体", price: 399, originalPrice: 459,
            icon: "building.columns.fill",
            description: "1.5 米多层猫爬架，含观景跳台、封闭猫窝、双剑麻抓柱。承重 20kg。",
            badges: ["包安装"], photo: "shop_toy_tree"),

        // 服装
        SKU(id: "apparel-bowtie-01", category: .apparel, name: "领结蝴蝶结",
            subtitle: "英伦风 / 魔术贴穿戴", price: 19, originalPrice: nil,
            icon: "bowtie",
            description: "手工缝制小领结，魔术贴设计 3 秒穿戴。拍照出片神器。",
            badges: [], photo: "shop_apparel_bowtie"),
        SKU(id: "apparel-harness-01", category: .apparel, name: "外出胸背带套装",
            subtitle: "防挣脱 / 含 1.5m 牵绳", price: 69, originalPrice: 89,
            icon: "figure.walk",
            description: "工字型防挣脱胸背带，透气网布。含 1.5 米牵引绳，遛猫散步安心。",
            badges: ["新品"], photo: "shop_apparel_harness"),

        // 疫苗
        SKU(id: "vax-tri-01", category: .medical, name: "猫三联疫苗",
            subtitle: "预防猫瘟 / 鼻支 / 杯状", price: 158, originalPrice: nil,
            icon: "syringe.fill",
            description: "美国进口辉瑞妙三多，预防三大主要传染病。需要在医院注射，购买后预约。",
            badges: ["医院预约"], photo: "shop_vax_tri"),
        SKU(id: "vax-rabies-01", category: .medical, name: "狂犬疫苗",
            subtitle: "灭活疫苗 / 1 年期", price: 88, originalPrice: nil,
            icon: "shield.lefthalf.filled",
            description: "国产灭活狂犬疫苗，1 年一次。需在猫满 3 月龄后注射。",
            badges: [], photo: "shop_vax_rabies"),

        // 洗澡
        SKU(id: "groom-std-01", category: .grooming, name: "标准洗护套餐",
            subtitle: "短毛猫 / 含挤肛门腺", price: 128, originalPrice: 158,
            icon: "bubbles.and.sparkles.fill",
            description: "洗澡 + 吹干 + 修剪指甲 + 清耳 + 挤肛门腺。短毛猫推荐。",
            badges: ["上门可选"], photo: "shop_groom_std"),
        SKU(id: "groom-deep-01", category: .grooming, name: "长毛深度护理",
            subtitle: "包含开结 / 局部修剪", price: 198, originalPrice: nil,
            icon: "comb.fill",
            description: "适合长毛猫种。含开结、局部修剪、专业除毛球护理油。",
            badges: [], photo: "shop_groom_deep"),

        // 体检
        SKU(id: "check-basic-01", category: .medical, name: "基础体检套餐",
            subtitle: "血常规 / 生化 / 体重", price: 268, originalPrice: 328,
            icon: "stethoscope",
            description: "血常规 + 血液生化 + 体重 + 体温 + 触诊。建议成猫每年一次。",
            badges: ["推荐"], photo: "shop_check_basic"),
        SKU(id: "check-senior-01", category: .medical, name: "老年专项体检",
            subtitle: "肾功能 / 甲状腺 / 心脏", price: 588, originalPrice: nil,
            icon: "heart.text.square.fill",
            description: "针对 7 岁以上老年猫，加做肾功能、甲状腺激素、心脏超声。",
            badges: [], photo: "shop_check_senior"),

        // 周边
        SKU(id: "acc-toy-01", category: .toy, name: "电动逗猫棒",
            subtitle: "智能感应 / 可充电", price: 79, originalPrice: 99,
            icon: "wand.and.stars",
            description: "感应式电动逗猫棒，多模式切换。USB-C 充电，单次续航 4 小时。",
            badges: [], photo: "shop_toy"),
        SKU(id: "acc-collar-01", category: .accessory, name: "PetPel 项圈替换扣件",
            subtitle: "硅胶 / 一组 2 个", price: 28, originalPrice: nil,
            icon: "circle.hexagongrid.fill",
            description: "PetPel 智能项圈专用替换扣件，硅胶材质，亲肤防过敏。",
            badges: [], photo: "shop_collar"),
        SKU(id: "acc-bed-01", category: .accessory, name: "四季通用猫窝",
            subtitle: "加厚软垫 / 可拆洗", price: 129, originalPrice: 159,
            icon: "bed.double.fill",
            description: "高回弹加厚软垫，四周围挡带来安全感。内垫可拆洗，四季通用。",
            badges: [], photo: "shop_acc_bed2"),
    ]

    static func byCategory(_ c: ShopCategory) -> [SKU] {
        all.filter { $0.category == c }
    }

    static func sku(_ id: String) -> SKU? {
        all.first { $0.id == id }
    }
}

// MARK: - Cart Store

@MainActor
@Observable
final class CartStore {
    var items: [CartItem] = []

    private let key = "cartItemsJson"

    init() { load() }

    func add(_ skuId: String, quantity: Int = 1) {
        if let i = items.firstIndex(where: { $0.skuId == skuId }) {
            items[i].quantity += quantity
        } else {
            items.append(CartItem(skuId: skuId, quantity: quantity))
        }
        save()
    }

    func remove(_ skuId: String) {
        items.removeAll { $0.skuId == skuId }
        save()
    }

    func setQuantity(_ skuId: String, _ q: Int) {
        guard let i = items.firstIndex(where: { $0.skuId == skuId }) else { return }
        if q <= 0 { items.remove(at: i) } else { items[i].quantity = q }
        save()
    }

    func clear() { items.removeAll(); save() }

    var total: Double {
        items.reduce(0) { sum, item in
            let p = ShopCatalog.sku(item.skuId)?.price ?? 0
            return sum + p * Double(item.quantity)
        }
    }

    var totalCount: Int { items.reduce(0) { $0 + $1.quantity } }

    private func load() {
        guard let json = UserDefaults.standard.string(forKey: key),
              let data = json.data(using: .utf8),
              let arr = try? JSONDecoder().decode([CartItem].self, from: data) else { return }
        items = arr
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items),
           let s = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(s, forKey: key)
        }
    }
}

// MARK: - Order Store

@MainActor
@Observable
final class OrderStore {
    var orders: [Order] = []

    private let key = "ordersJson"

    init() { load() }

    func place(items: [CartItem], total: Double) -> Order {
        let order = Order(id: UUID(), items: items, totalPrice: total, placedAt: .now)
        orders.insert(order, at: 0)  // 最新在前
        save()
        return order
    }

    private func load() {
        guard let json = UserDefaults.standard.string(forKey: key),
              let data = json.data(using: .utf8),
              let arr = try? JSONDecoder().decode([Order].self, from: data) else { return }
        orders = arr
    }

    private func save() {
        if let data = try? JSONEncoder().encode(orders),
           let s = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(s, forKey: key)
        }
    }
}

// MARK: - Helpers

func formatYuan(_ v: Double) -> String {
    if v == v.rounded() {
        return "¥\(Int(v))"
    }
    return String(format: "¥%.2f", v)
}

// MARK: - Shop Main View

struct ShopView: View {
    @State private var cart = CartStore()
    @State private var orderStore = OrderStore()
    @State private var selectedCategory: ShopCategory = .food

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                adBanner
                categoryTabs
                productGrid
            }
            .padding()
        }
        .navigationTitle("猫咪商城")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: CartView().environment(cart).environment(orderStore)) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "cart.fill")
                        if cart.totalCount > 0 {
                            Text("\(cart.totalCount)")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Color.red, in: Capsule())
                                .offset(x: 8, y: -6)
                        }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: OrdersView().environment(orderStore)) {
                    Image(systemName: "doc.text.fill")
                }
            }
        }
    }

    // MARK: - Cards

    private var adBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "megaphone.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.2), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("外部广告对接位").font(.headline).foregroundStyle(.white)
                Text("品牌方位 / SDK 接入 / CPM 计费").font(.caption2).foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [.pink, .orange],
                           startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 14)
        )
    }

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ShopCategory.shopCases) { c in
                    Button {
                        selectedCategory = c
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: c.icon).font(.caption)
                            Text(c.rawValue).font(.subheadline.weight(.bold))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(
                            selectedCategory == c
                                ? c.color
                                : Color.secondary.opacity(0.12),
                            in: Capsule()
                        )
                        .foregroundStyle(selectedCategory == c ? .white : .primary)
                    }
                }
            }
        }
    }

    private var productGrid: some View {
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: cols, spacing: 12) {
            ForEach(ShopCatalog.byCategory(selectedCategory)) { sku in
                NavigationLink(destination: ProductDetailView(sku: sku).environment(cart).environment(orderStore)) {
                    SKUCard(sku: sku, onAddToCart: {
                        cart.add(sku.id)
                    })
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - SKU Card

struct SKUCard: View {
    let sku: SKU
    var onAddToCart: (() -> Void)? = nil
    @State private var showAdded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(sku.category.color.opacity(0.12))
                    .aspectRatio(1, contentMode: .fit)
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
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .bottomTrailing) {
                        if let onAddToCart {
                            Button {
                                onAddToCart()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    showAdded = true
                                }
                                Task {
                                    try? await Task.sleep(for: .seconds(1))
                                    withAnimation { showAdded = false }
                                }
                            } label: {
                                Image(systemName: showAdded ? "checkmark" : "plus")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(
                                        Circle().fill(showAdded ? Color.green : sku.category.color)
                                    )
                                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                            }
                            .buttonStyle(.plain)
                            .padding(6)
                            .scaleEffect(showAdded ? 1.2 : 1.0)
                        }
                    }

                if !sku.badges.isEmpty {
                    Text(sku.badges[0])
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.red, in: Capsule())
                        .foregroundStyle(.white)
                        .padding(6)
                }
            }
            Text(sku.name)
                .font(.subheadline.weight(.bold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(sku.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(formatYuan(sku.price))
                    .font(.callout.bold())
                    .foregroundStyle(.red)
                if let orig = sku.originalPrice {
                    Text(formatYuan(orig))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .strikethrough()
                }
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Product Detail

struct ProductDetailView: View {
    let sku: SKU
    @Environment(CartStore.self) private var cart
    @Environment(\.dismiss) private var dismiss
    @State private var quantity: Int = 1
    @State private var showAddedToast: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroImage
                priceRow
                badgesRow
                description
                Spacer(minLength: 60)
            }
            .padding()
        }
        .navigationTitle(sku.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .overlay(alignment: .top) {
            if showAddedToast {
                Text("已加入购物车")
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var heroImage: some View {
        Rectangle()
            .fill(sku.category.color.opacity(0.12))
            .aspectRatio(1.4, contentMode: .fit)
            .overlay {
                if let photo = sku.photo {
                    Image(photo)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: sku.icon)
                        .font(.system(size: 100))
                        .foregroundStyle(sku.category.color)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var priceRow: some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(formatYuan(sku.price))
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.red)
            if let orig = sku.originalPrice {
                Text(formatYuan(orig))
                    .font(.callout)
                    .strikethrough()
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Stepper("数量: \(quantity)", value: $quantity, in: 1...99)
                .labelsHidden()
                .overlay(
                    Text("\(quantity)")
                        .font(.callout.monospacedDigit())
                        .padding(.horizontal, 8)
                        .offset(x: -54),
                    alignment: .center
                )
        }
    }

    private var badgesRow: some View {
        HStack {
            ForEach(sku.badges, id: \.self) { b in
                Text(b)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(sku.category.color.opacity(0.15), in: Capsule())
                    .foregroundStyle(sku.category.color)
            }
        }
    }

    private var description: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("商品介绍").font(.headline)
            Text(sku.description).font(.body).foregroundStyle(.primary)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button {
                cart.add(sku.id, quantity: quantity)
                withAnimation(.spring(duration: 0.3)) { showAddedToast = true }
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    withAnimation { showAddedToast = false }
                }
            } label: {
                Text("加入购物车")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(sku.category.color.opacity(0.18), in: Capsule())
                    .foregroundStyle(sku.category.color)
            }
            NavigationLink {
                CartView()
                    .environment(cart)
                    .onAppear {
                        cart.add(sku.id, quantity: quantity)
                    }
            } label: {
                Text("立即购买")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(sku.category.color, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .padding()
        .background(.bar)
    }
}

// MARK: - Cart View

struct CartView: View {
    @Environment(CartStore.self) private var cart
    @Environment(OrderStore.self) private var orderStore
    @Environment(\.dismiss) private var dismiss
    @State private var showCheckoutAlert: Bool = false
    @State private var showPayment: Bool = false
    @State private var checkoutSuccess: Bool = false
    @State private var latestOrder: Order?

    var body: some View {
        Group {
            if cart.items.isEmpty && !checkoutSuccess {
                emptyView
            } else {
                contentList
            }
        }
        .navigationTitle("购物车")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !cart.items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清空") {
                        withAnimation { cart.clear() }
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }
        }
        .alert("确认支付", isPresented: $showCheckoutAlert) {
            Button("取消", role: .cancel) {}
            Button("确认支付 \(formatYuan(cart.total))") {
                showPayment = true
            }
        } message: {
            Text("确认后将生成订单")
        }
        .fullScreenCover(isPresented: $showPayment) {
            PaymentProcessingView(
                total: cart.total,
                onComplete: {
                    let order = orderStore.place(items: cart.items, total: cart.total)
                    latestOrder = order
                    cart.clear()
                    showPayment = false
                    checkoutSuccess = true
                },
                onCancel: {
                    showPayment = false
                }
            )
        }
        .navigationDestination(isPresented: $checkoutSuccess) {
            OrderSuccessView(order: latestOrder)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "cart")
                .font(.system(size: 60))
                .foregroundStyle(.secondary.opacity(0.4))
            Text("购物车空空如也")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("去逛逛商城，给毛孩子挑点好东西吧")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contentList: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    // Item count header
                    HStack {
                        Text("共 \(cart.totalCount) 件商品")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(PetPalTheme.inkSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 4)

                    ForEach(cart.items) { item in
                        if let sku = ShopCatalog.sku(item.skuId) {
                            cartRow(item: item, sku: sku)
                        }
                    }
                }
                .padding()
            }
            checkoutBar
        }
    }

    private func cartRow(item: CartItem, sku: SKU) -> some View {
        HStack(spacing: 12) {
            // Product icon
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(sku.category.color.opacity(0.12))
                    .frame(width: 60, height: 60)
                if let photo = sku.photo {
                    Image(photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Image(systemName: sku.icon)
                        .font(.title2)
                        .foregroundStyle(sku.category.color)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(sku.name)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(2)
                Text(sku.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(formatYuan(sku.price))
                        .font(.subheadline.bold())
                        .foregroundStyle(.red)
                    if let orig = sku.originalPrice {
                        Text(formatYuan(orig))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .strikethrough()
                    }
                }
            }

            Spacer()

            // Quantity control
            HStack(spacing: 0) {
                Button {
                    withAnimation(.spring(response: 0.25)) {
                        cart.setQuantity(item.skuId, item.quantity - 1)
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(item.quantity <= 1 ? .red : PetPalTheme.inkSecondary)
                        .frame(width: 30, height: 30)
                }

                Text("\(item.quantity)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .frame(width: 32)

                Button {
                    withAnimation(.spring(response: 0.25)) {
                        cart.setQuantity(item.skuId, item.quantity + 1)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(sku.category.color)
                        .frame(width: 30, height: 30)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.gray.opacity(0.15), lineWidth: 0.5)
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
    }

    private var checkoutBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("合计")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatYuan(cart.total))
                    .font(.title2.bold())
                    .foregroundStyle(.red)
            }
            Spacer()
            Button {
                showCheckoutAlert = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "creditcard.fill")
                    Text("结算 (\(cart.totalCount))")
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
        }
        .padding(.horizontal).padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Payment Processing (Full Screen Animation)

struct PaymentProcessingView: View {
    let total: Double
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var phase: PaymentPhase = .ready
    @State private var progress: Double = 0
    @State private var ringRotation: Double = 0

    enum PaymentPhase {
        case ready, processing, success
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer()

                // Animation area
                ZStack {
                    switch phase {
                    case .ready:
                        readyView
                    case .processing:
                        processingView
                    case .success:
                        successView
                    }
                }
                .frame(height: 200)

                // Price
                Text(formatYuan(total))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                // Status text
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                // Buttons
                if phase == .ready {
                    VStack(spacing: 12) {
                        Button {
                            startPayment()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "faceid")
                                    .font(.title3)
                                Text("确认支付")
                                    .font(.headline)
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

                        Button("取消", action: onCancel)
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.vertical, 8)
                    }
                    .padding(.horizontal, 40)
                }

                if phase == .success {
                    Button {
                        onComplete()
                    } label: {
                        Text("完成")
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

    private var statusText: String {
        switch phase {
        case .ready: return "请确认支付"
        case .processing: return "支付处理中..."
        case .success: return "支付成功"
        }
    }

    private var readyView: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 4)
                .frame(width: 120, height: 120)
            Image(systemName: "creditcard.fill")
                .font(.system(size: 48))
                .foregroundStyle(.white)
        }
    }

    private var processingView: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 4)
                .frame(width: 120, height: 120)

            // Animated arc
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(
                    LinearGradient(colors: [.blue, .cyan],
                                   startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .frame(width: 120, height: 120)
                .rotationEffect(.degrees(ringRotation))

            // Progress
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.cyan.opacity(0.3), lineWidth: 2)
                .frame(width: 100, height: 100)
                .rotationEffect(.degrees(-90))

            Text("\(Int(progress * 100))%")
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
        }
    }

    private var successView: some View {
        ZStack {
            Circle()
                .fill(Color.green)
                .frame(width: 120, height: 120)
                .shadow(color: .green.opacity(0.5), radius: 20)

            Image(systemName: "checkmark")
                .font(.system(size: 50, weight: .bold))
                .foregroundStyle(.white)
        }
        .transition(.scale.combined(with: .opacity))
    }

    private func startPayment() {
        withAnimation(.easeInOut(duration: 0.3)) {
            phase = .processing
        }

        // Spinning animation
        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
            ringRotation = 360
        }

        // Simulate progress
        Task {
            for i in 1...20 {
                try? await Task.sleep(for: .milliseconds(80))
                withAnimation(.easeOut(duration: 0.1)) {
                    progress = Double(i) / 20.0
                }
            }

            // Brief pause at 100%
            try? await Task.sleep(for: .milliseconds(300))

            // Success!
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                phase = .success
            }
        }
    }
}

// MARK: - Order Success

struct OrderSuccessView: View {
    let order: Order?
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
                    // Confetti particles
                    ForEach(0..<12, id: \.self) { i in
                        Circle()
                            .fill(confettiColor(i))
                            .frame(width: 8, height: 8)
                            .offset(confettiOffset[i])
                            .opacity(showCheck ? 0 : 1)
                    }

                    Circle()
                        .fill(
                            LinearGradient(colors: [.green, .mint],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 100, height: 100)
                        .shadow(color: .green.opacity(0.3), radius: 20)
                        .scaleEffect(showCheck ? 1.0 : 0.3)
                        .opacity(showCheck ? 1 : 0)

                    Image(systemName: "checkmark")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.white)
                        .scaleEffect(showCheck ? 1.0 : 0.3)
                        .opacity(showCheck ? 1 : 0)
                }
                .frame(height: 120)

                Text("支付成功")
                    .font(.title.bold())
                    .opacity(showDetails ? 1 : 0)
                    .offset(y: showDetails ? 0 : 10)

                if let order {
                    VStack(spacing: 16) {
                        // Amount
                        Text(formatYuan(order.totalPrice))
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.red)

                        // Order info card
                        VStack(spacing: 12) {
                            infoRow("订单号", value: String(order.id.uuidString.prefix(8)).uppercased())
                            Divider()
                            infoRow("下单时间", value: formatDate(order.placedAt))
                            Divider()
                            infoRow("商品数量", value: "\(order.items.reduce(0) { $0 + $1.quantity }) 件")
                            Divider()
                            infoRow("支付方式", value: "PetPel Pay")

                            // Item list
                            Divider()
                            ForEach(order.items) { item in
                                if let sku = ShopCatalog.sku(item.skuId) {
                                    HStack(spacing: 10) {
                                        Image(systemName: sku.icon)
                                            .font(.caption)
                                            .foregroundStyle(sku.category.color)
                                            .frame(width: 24, height: 24)
                                            .background(sku.category.color.opacity(0.12), in: Circle())
                                        Text(sku.name)
                                            .font(.caption)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("x\(item.quantity)")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                        Text(formatYuan(sku.price * Double(item.quantity)))
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.red)
                                    }
                                }
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
                    }
                    .opacity(showDetails ? 1 : 0)
                    .offset(y: showDetails ? 0 : 20)
                }

                Spacer()

            }
            .padding()
        }
        .navigationTitle("支付成功")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Confetti burst
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

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }

    private func confettiColor(_ i: Int) -> Color {
        let colors: [Color] = [.pink, .orange, .yellow, .green, .blue, .purple]
        return colors[i % colors.count]
    }
}

// MARK: - Orders List

struct OrdersView: View {
    @Environment(OrderStore.self) private var orderStore

    var body: some View {
        Group {
            if orderStore.orders.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text").font(.system(size: 60)).foregroundStyle(.secondary)
                    Text("还没有订单").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(orderStore.orders) { o in
                        orderCard(o)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("我的订单")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func orderCard(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(order.placedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                Text(order.placedAt, style: .time).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("已完成").font(.caption.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Color.green.opacity(0.15), in: Capsule())
                    .foregroundStyle(.green)
            }
            ForEach(order.items) { item in
                if let sku = ShopCatalog.sku(item.skuId) {
                    HStack {
                        Image(systemName: sku.icon).foregroundStyle(sku.category.color)
                        Text(sku.name).font(.subheadline).lineLimit(1)
                        Spacer()
                        Text("× \(item.quantity)").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            HStack {
                Text("总计").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(formatYuan(order.totalPrice))
                    .font(.callout.bold())
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 6)
    }
}
