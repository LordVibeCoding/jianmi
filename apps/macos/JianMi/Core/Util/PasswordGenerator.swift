import Foundation

/// 强密码生成器（系统 CSPRNG：SystemRandomNumberGenerator → arc4random_buf）。
struct PasswordGenerator {
    struct Options {
        var length: Int = 20
        var upper = true
        var lower = true
        var digits = true
        var symbols = true
        /// 排除易混淆字符 0O1lI|
        var excludeAmbiguous = true
    }

    static func generate(_ opts: Options = Options()) -> String {
        var pools: [[Character]] = []
        func pool(_ s: String) -> [Character] {
            let ambiguous: Set<Character> = ["0", "O", "1", "l", "I", "|"]
            return s.filter { !opts.excludeAmbiguous || !ambiguous.contains($0) }
        }
        if opts.upper { pools.append(pool("ABCDEFGHIJKLMNOPQRSTUVWXYZ")) }
        if opts.lower { pools.append(pool("abcdefghijklmnopqrstuvwxyz")) }
        if opts.digits { pools.append(pool("0123456789")) }
        if opts.symbols { pools.append(pool("!@#$%^&*-_=+?~")) }
        guard !pools.isEmpty else { return "" }

        var rng = SystemRandomNumberGenerator()
        let all = pools.flatMap { $0 }
        var chars: [Character] = []

        // 保证每个选中的字符类至少出现一次
        for p in pools { chars.append(p.randomElement(using: &rng)!) }
        while chars.count < max(opts.length, pools.count) {
            chars.append(all.randomElement(using: &rng)!)
        }
        chars.shuffle(using: &rng)
        return String(chars.prefix(opts.length))
    }
}
