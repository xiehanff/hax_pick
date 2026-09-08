import AppKit
import CoreText

/// 应用内置字体:代码等宽 Google Sans Mono,中文正文 OPPO Sans 级联回退。
enum AppFont {
    private static var isRegistered = false

    /// 注册 bundle 内置字体(进程级)。SwiftPM 测试走 Bundle.module,
    /// App 运行走 Bundle.main;重复调用安全。
    static func registerBundledFonts() {
        guard !isRegistered else { return }
        isRegistered = true

#if SWIFT_PACKAGE
        let bundle = Bundle.module
#else
        let bundle = Bundle.main
#endif
        let urls = (bundle.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])
            + (bundle.urls(forResourcesWithExtension: "otf", subdirectory: "Fonts") ?? [])

        for url in urls {
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
    }

    /// 代码块/行内代码等宽字体;Google Sans Mono 未注册时回退系统等宽。
    static func mono(ofSize size: CGFloat) -> NSFont {
        registerBundledFonts()
        return NSFont(name: "GoogleSansMono-Regular", size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Markdown 正文字体:拉丁字符走 Google Sans Mono,中文经级联回退到 OPPO Sans。
    /// Google Sans Mono 只有 Regular 一个字重,粗体由系统合成。
    static func body(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        registerBundledFonts()
        var attributes: [NSFontDescriptor.AttributeName: Any] = [:]
        if weight.rawValue >= NSFont.Weight.semibold.rawValue {
            attributes[.traits] = [
                NSFontDescriptor.TraitKey.symbolic: NSFontDescriptor.SymbolicTraits.bold.rawValue,
            ]
        }
        var base = NSFont(name: "GoogleSansMono-Regular", size: size)
            ?? .systemFont(ofSize: size, weight: weight)
        if weight.rawValue >= NSFont.Weight.semibold.rawValue,
           let synthesized = NSFont(
               descriptor: base.fontDescriptor.addingAttributes(attributes),
               size: size
           ) {
            base = synthesized
        }
        guard let oppo = NSFont(name: "OPPOSans40", size: size) else { return base }
        let descriptor = base.fontDescriptor.addingAttributes([
            .cascadeList: [oppo.fontDescriptor],
        ])
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    /// 其他 UI(工具栏/输入框/建议胶囊/标题栏等)的中英文字体,全部使用 OPPO Sans。
    /// ttf 内含 Light/Regular/Medium/SemiBold/Bold 命名实例,按字重映射。
    static func ui(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        registerBundledFonts()
        let value = weight.rawValue
        let postScriptName: String
        if value < NSFont.Weight.medium.rawValue {
            postScriptName = "OPPOSans40_Light"
        } else if value < NSFont.Weight.semibold.rawValue {
            postScriptName = "OPPOSans40"
        } else if value < NSFont.Weight.bold.rawValue {
            postScriptName = "OPPOSans40_Medium"
        } else if value < NSFont.Weight.heavy.rawValue {
            postScriptName = "OPPOSans40_SemiBold"
        } else {
            postScriptName = "OPPOSans40_Bold"
        }
        return NSFont(name: postScriptName, size: size)
            ?? .systemFont(ofSize: size, weight: weight)
    }
}
