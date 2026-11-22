import SwiftUI

/// Both documents stay readable without opening the school website or verifying an account.
struct PrivacyPolicyView: View {
    @State private var english = AppLanguage.isEnglish

    var body: some View {
        SettingsForm {
            if let publishedPolicy = URL(string: "https://mantatche.com/tschedule/privacy/#\(english ? "en" : "zh-hans")") {
                Section {
                    Link(destination: publishedPolicy) {
                        Label("查看在线隐私政策", systemImage: "arrow.up.right.square")
                    }
                    .accessibilityIdentifier("settings-published-privacy-policy")
                }
            }
            if let copy = PolicyCopy.bundled {
                Section {
                    NavigationLink {
                        SettingsForm {
                            PolicySections(copy: copy, document: copy.terms, english: $english)
                        }
                        .navigationTitle(copy.terms.title.text(english))
                    } label: {
                        Text(verbatim: copy.terms.title.text(english))
                    }
                    .accessibilityIdentifier("settings-terms-page")
                }
                PolicySections(copy: copy, document: copy.privacy, english: $english)
            } else {
                Text("当前安装包缺少隐私与条款文档。")
            }
        }
        .navigationTitle(Text(verbatim: english ? "Privacy" : "隐私说明"))
    }
}

private struct PolicySections: View {
    let copy: PolicyCopy
    let document: PolicyCopy.Document
    @Binding var english: Bool

    var body: some View {
        Section {
            Picker(selection: $english) {
                Text(verbatim: "简体中文").tag(false)
                Text(verbatim: "English").tag(true)
            } label: { Text(verbatim: english ? "Document language" : "文档语言") }
            .pickerStyle(.segmented)
            Text(verbatim: document.intro.text(english))
        } footer: {
            if let publisher = copy.publisher, let date = copy.effectiveDate {
                Text(verbatim: english ? "Publisher: \(publisher) · Effective: \(date)" : "发布者：\(publisher) · 生效日期：\(date)")
            } else {
                Text(verbatim: copy.draftNotice.text(english))
            }
        }
        ForEach(document.sections.indices, id: \.self) { index in
            let section = document.sections[index]
            Section {
                Text(verbatim: section.body.text(english))
            } header: {
                Text(verbatim: section.heading.text(english))
            }
        }
        Section {
            if let address = URL(string: "mailto:\(copy.contact)") {
                Link(destination: address) { Text(verbatim: copy.contact) }
            }
            LabeledContent { Text(verbatim: copy.revised) } label: { Text(verbatim: english ? "Last revised" : "最近修订") }
        } header: {
            Text(verbatim: english ? "Contact" : "联系维护者")
        }
    }
}

/// The static review pages are rendered from this same app resource; never fetch policy copy at launch.
private struct PolicyCopy: Decodable {
    struct Wording: Decodable {
        let zh: String
        let en: String
        func text(_ english: Bool) -> String { english ? en : zh }
    }

    struct Paragraph: Decodable {
        let heading: Wording
        let body: Wording
    }

    struct Document: Decodable {
        let title: Wording
        let intro: Wording
        let sections: [Paragraph]
    }

    let privacy: Document
    let terms: Document
    let revised: String
    let publisher: String?
    let effectiveDate: String?
    let contact: String
    let draftNotice: Wording

    static let bundled: Self? = {
        guard let url = Bundle.main.url(forResource: "PolicyCopy", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PolicyCopy.self, from: data)
    }()
}
