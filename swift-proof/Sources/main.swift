import AppKit

// SciTextView.h is exposed via the bridging header passed to swiftc.
// SciMakeView returns an NSView; SciSetText/SciGetText/SciSetFont operate on it.

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var sciView: NSView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let frame = NSRect(x: 200, y: 200, width: 900, height: 600)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Scintilla on Swift — Path A proof"

        sciView = SciMakeView(NSRect(origin: .zero, size: frame.size))
        sciView.autoresizingMask = [.width, .height]
        window.contentView = sciView

        SciSetText(sciView, """
        // Scintilla + Lexilla running inside a Swift AppKit window.
        // If keywords / strings / numbers / comments are coloured, the
        // C-language lexer (loaded from liblexilla.dylib at runtime) is wired
        // up correctly. Try editing — highlighting should update as you type.

        #include <vector>
        #include <string>

        namespace demo {

        constexpr int kAnswer = 42;
        const char *kGreeting = "hello from C++";

        class Counter {
        public:
            explicit Counter(int start) : value_(start) {}
            int next() { return ++value_; }
        private:
            int value_;
        };

        template <typename T>
        T identity(T x) {
            return x;
        }

        }  // namespace demo

        int main() {
            demo::Counter c(0);
            for (int i = 0; i < 3; ++i) {
                std::vector<int> v = { c.next(), c.next() };
                (void)v;
            }
            return 0;
        }
        """)

        // Apply Lexilla's C/C++ lexer + colour scheme.
        let ok = SciApplyLexer(sciView, "cpp")
        if !ok {
            NSLog("SciApplyLexer(\"cpp\") failed — check that liblexilla.dylib is on the rpath.")
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
