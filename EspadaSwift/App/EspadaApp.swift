import SwiftUI
import UIKit

@main
struct EspadaApp: App {
    @State private var store = ModuleStore()
    @State private var session = StudySession()
    @State private var themes = ThemeManager()
    @State private var chrome = ChromeScrollController()
    /// Cold start only: parchment splash until first chapter is ready.
    @State private var showColdSplash = true

    /// Keep splash up long enough to see the scroll open/close (animation ~1.55s).
    private static let coldSplashMinimumSeconds: TimeInterval = 2.4
    private static let coldSplashFadeSeconds: TimeInterval = 0.55

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environment(store)
                    .environment(session)
                    .environment(themes)
                    .environment(chrome)
                    .preferredColorScheme(themes.theme.preferredColorScheme)
                    .tint(themes.theme.accent)

                if showColdSplash {
                    ScrollLoadingView()
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
            .onAppear { themes.applySystemChrome() }
            .onChange(of: themes.theme) { _, _ in
                themes.applySystemChrome()
            }
            .task {
                // Point 3: cold-start phase timing (Console / Instruments signposts)
                LaunchProfiler.begin()
                let splashStarted = Date()

                // --- Cold-start critical path (first paint + first chapter) ---
                // 1) Fast catalog from disk cache (no SQLite Details for known files)
                await store.rescan()
                LaunchProfiler.mark("catalog_rescan")

                // 2) Restore last modules + open the last chapter ASAP
                session.applyDefaultModules(from: store)
                LaunchProfiler.mark("modules_restored")

                await session.reloadChapterSafely()
                LaunchProfiler.mark("first_chapter")

                // Hold splash until minimum duration even if load finished early
                let elapsed = Date().timeIntervalSince(splashStarted)
                let remaining = Self.coldSplashMinimumSeconds - elapsed
                if remaining > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                }
                withAnimation(.easeOut(duration: Self.coldSplashFadeSeconds)) {
                    showColdSplash = false
                }

                // --- Deferred work (battery + RAM): after first chapter is on screen ---
                await Task.yield()
                await session.reloadCompanionSpanishChapter()
                LaunchProfiler.mark("companion_spanish")

                await session.restoreStudyQueries()
                LaunchProfiler.mark("study_queries")

                await Task.yield()
                await store.ensurePreferredSpanishBibles()
                LaunchProfiler.mark("seed_import")
                LaunchProfiler.end()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                store.handleMemoryPressure()
                session.handleMemoryPressure()
            }
        }
    }
}

struct RootView: View {
    @Environment(StudySession.self) private var session
    @Environment(ThemeManager.self) private var themes
    @Environment(ChromeScrollController.self) private var chrome
    @State private var tab: AppTab = .bible

    var body: some View {
        TabView(selection: $tab) {
            BibleView()
                .tabItem { Label(AppTab.bible.title, systemImage: AppTab.bible.systemImage) }
                .tag(AppTab.bible)

            CommentaryView()
                .tabItem { Label(AppTab.commentary.title, systemImage: AppTab.commentary.systemImage) }
                .tag(AppTab.commentary)

            DictionaryView()
                .tabItem { Label(AppTab.dictionary.title, systemImage: AppTab.dictionary.systemImage) }
                .tag(AppTab.dictionary)

            LexiconView()
                .tabItem { Label(AppTab.lexicon.title, systemImage: AppTab.lexicon.systemImage) }
                .tag(AppTab.lexicon)

            LibraryView()
                .tabItem { Label(AppTab.library.title, systemImage: AppTab.library.systemImage) }
                .tag(AppTab.library)
        }
        // Tab dock: hide SwiftUI fill so UIKit `UIGlassEffect` (Liquid Glass) shows.
        .toolbarBackground(.hidden, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(themes.theme.preferredColorScheme, for: .tabBar)
        .espadaChromeVisibility(chrome)
        .onChange(of: tab) { _, _ in
            // Always restore dock when switching resources
            chrome.show()
        }
        .onChange(of: session.focusToken) { _, _ in
            chrome.show()
            tab = session.focusedTab
        }
        .onChange(of: session.activePeek?.id) { _, _ in
            // Peek / pickers: keep chrome visible so actions stay reachable
            chrome.show()
        }
        // Global popup: tap Strong / verse inside dict · lex · commentary text
        .sheet(item: Binding(
            get: { session.activePeek },
            set: { session.activePeek = $0 }
        )) { peek in
            StudyPeekSheet(peek: peek)
        }
    }
}

