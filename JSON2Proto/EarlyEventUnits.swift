// Historical event-unit corrections shared by all regions.
// Upstream events.json uses "none" for every event through #36.
// Keep #1–42 explicit, including mixed events; #43 onward uses upstream data.
// Titles identify the records for review. Units use the upstream wire values.
// Cross-checked against JP events.json and eventDeckBonuses.json:
// https://github.com/Sekai-World/sekai-master-db-diff
enum EarlyEventUnits {
    static let corrections: [Int: String] = [
        1: "light_sound", // 雨上がりの一番星
        2: "school_refusal", // 囚われのマリオネット
        3: "theme_park", // 全力！ワンダーハロウィン！
        4: "none", // 走れ！体育祭！～実行委員は大忙し～
        5: "idol", // ここからRE:START！
        6: "street", // いつか、背中あわせのリリックを
        7: "none", // KAMIKOU FESTIVAL！
        8: "theme_park", // 聖なる夜に、この歌声を
        9: "none", // セカイのハッピーニューイヤー！
        10: "light_sound", // 揺れるまま、でも君は前へ
        11: "idol", // Color of Myself！
        12: "street", // Period of NOCTURNE
        13: "none", // 響くトワイライトパレード
        14: "school_refusal", // 満たされないペイルカラー
        15: "theme_park", // スマイルオブドリーマー
        16: "none", // 天馬さんちのひな祭り
        17: "idol", // 届け！HOPEFUL STAGE♪
        18: "none", // 君と歌う、桜舞う世界で
        19: "school_refusal", // シークレット・ディスタンス
        20: "light_sound", // Resonate with you
        21: "street", // STRAY BAD DOG
        22: "none", // お悩み聞かせて！わくわくピクニック
        23: "idol", // 頑張るあなたにBreak Time！
        24: "none", // 純白の貴方へ、誓いの歌を！
        25: "theme_park", // ワンダーマジカルショウタイム！
        26: "school_refusal", // カーネーション・リコレクション
        27: "light_sound", // Unnamed Harmony
        28: "street", // Awakening Beat
        29: "none", // 夏祭り、鳴り響く音は
        30: "none", // きっと最高のsummer！
        31: "idol", // ハッピー・ラブリー・エブリデイ！
        32: "theme_park", // マーメイドにあこがれて
        33: "none", // ふたり、月うさぎ
        34: "light_sound", // Knock the Future!!
        35: "school_refusal", // 灯のミラージュ
        36: "none", // スクランブル・ファンフェスタ！
        37: "street", // Bout for Beside You
        38: "theme_park", // Revival my dream
        39: "school_refusal", // ボクのあしあと キミのゆくさき
        40: "light_sound", // 揺るがぬ想い、今言葉にして
        41: "none", // バディ・ファニー・スペンドタイム♪
        42: "none", // 交わる旋律 灯るぬくもり
    ]
}
