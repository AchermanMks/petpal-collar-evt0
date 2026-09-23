import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var state
    @AppStorage("isLoggedIn") private var isLoggedIn: Bool = false
    @AppStorage("userPhone") private var savedPhone: String = ""

    @State private var phone: String = ""
    @State private var code: String = ""
    @State private var countdown: Int = 0
    @State private var countdownTask: Task<Void, Never>?
    @State private var shakeTrigger: Int = 0
    @FocusState private var focusedField: Field?

    private enum Field { case phone, code }

    var body: some View {
        ZStack {
            StarrySkyBackground()

            VStack(spacing: 28) {
                Spacer(minLength: 40)

                VStack(spacing: 14) {
                    PetPalLogo(size: 110)
                    PetPalWordmark()
                    Text("让爱永远在线")
                        .font(.subheadline)
                        .foregroundStyle(PetPalTheme.inkPrimary.opacity(0.7))
                }

                Spacer(minLength: 12)

                loginCard
                    .modifier(Shake(animatableData: CGFloat(shakeTrigger)))

                Spacer()

                Button("游客模式 →") { enterAsGuest() }
                    .buttonStyle(PetPalGhostButtonStyle())

                Text("v1.0")
                    .font(.caption2)
                    .foregroundStyle(PetPalTheme.inkPrimary.opacity(0.5))
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 28)
        }
        .onAppear {
            if phone.isEmpty { phone = savedPhone }
        }
        .onDisappear { countdownTask?.cancel() }
    }

    private var loginCard: some View {
        PetPalCard {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "iphone")
                        .foregroundStyle(PetPalTheme.primary)
                        .frame(width: 22)
                    TextField("手机号", text: $phone)
                        .keyboardType(.numberPad)
                        .textContentType(.telephoneNumber)
                        .focused($focusedField, equals: .phone)
                        .onChange(of: phone) { _, new in
                            phone = String(new.filter(\.isNumber).prefix(11))
                        }
                }
                .petPalField()

                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(PetPalTheme.primary)
                        .frame(width: 22)
                    TextField("验证码", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($focusedField, equals: .code)
                        .onChange(of: code) { _, new in
                            code = String(new.filter(\.isNumber).prefix(6))
                        }
                    Button(action: requestCode) {
                        Text(countdown > 0 ? "\(countdown)s" : "获取验证码")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(canRequestCode ? PetPalTheme.primary : PetPalTheme.inkSecondary)
                    }
                    .disabled(!canRequestCode)
                }
                .petPalField()

                Button(action: login) {
                    Text("登 录")
                        .tracking(4)
                }
                .buttonStyle(PetPalPrimaryButtonStyle(enabled: canLogin))
                .disabled(!canLogin)
                .padding(.top, 4)

                HStack(spacing: 4) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.caption2)
                    Text("登录即代表同意《用户协议》和《隐私政策》")
                        .font(.caption2)
                }
                .foregroundStyle(PetPalTheme.inkSecondary.opacity(0.7))
            }
        }
    }

    private var canRequestCode: Bool {
        countdown == 0 && phone.count == 11
    }

    private var canLogin: Bool {
        phone.count == 11 && code.count >= 4
    }

    private func requestCode() {
        guard canRequestCode else { return }
        focusedField = .code
        countdownTask?.cancel()
        countdown = 60
        countdownTask = Task { @MainActor in
            while countdown > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                countdown -= 1
            }
        }
    }

    private func login() {
        guard canLogin else {
            withAnimation(.default) { shakeTrigger += 1 }
            return
        }
        savedPhone = phone
        countdownTask?.cancel()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            isLoggedIn = true
        }
    }

    private func enterAsGuest() {
        savedPhone = ""
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            isLoggedIn = true
        }
    }
}

private struct Shake: GeometryEffect {
    var amount: CGFloat = 8
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: amount * sin(animatableData * .pi * shakesPerUnit),
            y: 0
        ))
    }
}

#Preview {
    LoginView()
        .environment(AppState())
}
