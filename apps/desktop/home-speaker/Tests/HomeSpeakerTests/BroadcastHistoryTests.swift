// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import Testing
@testable import HomeSpeakerCore

// Guards for the broadcast history, which the app, `HomeSpeaker --say`, the
// Stop hook's detached `--announce` and the Stop hook itself all add to:
// no writer loses another's entry, the list stays newest-first and 30 long,
// files written before BroadcastHistory existed still read, and a bad file
// never stops a broadcast being recorded.

private func scratchDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("homespeaker-history-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func item(_ text: String, source: String = "Test", at time: Date = Date()) -> BroadcastLogItem {
    BroadcastLogItem(timestamp: time, text: text, targetName: "Kitchen", source: source)
}

@Suite struct BroadcastHistoryFileTests {
    @Test func missingFileReadsEmptyAndFirstAppendCreatesIt() throws {
        let url = try scratchDir().appendingPathComponent("nested/speaker_history.json")
        let history = BroadcastHistory(fileURL: url)
        #expect(history.load().isEmpty)
        let written = try history.append(item("one"))
        #expect(written.map(\.text) == ["one"])
        #expect(BroadcastHistory(fileURL: url).load() == written)
    }

    @Test func newestFirst() throws {
        let history = BroadcastHistory(fileURL: try scratchDir().appendingPathComponent("h.json"))
        for text in ["first", "second", "third"] { try history.append(item(text)) }
        #expect(history.load().map(\.text) == ["third", "second", "first"])
    }

    @Test func keepsOnlyTheNewestThirty() throws {
        let history = BroadcastHistory(fileURL: try scratchDir().appendingPathComponent("h.json"))
        for i in 0..<45 { try history.append(item("n\(i)")) }
        let items = history.load()
        #expect(BroadcastHistory.limit == 30)
        #expect(items.count == 30)
        #expect(items.first?.text == "n44")
        #expect(items.last?.text == "n15")
    }

    /// The format ConfigManager wrote before this type existed: a default
    /// JSONEncoder array, dates as seconds since 2001. It must still read,
    /// and an append must keep its entries.
    @Test func readsAndKeepsAFileTheOldAppWrote() throws {
        let url = try scratchDir().appendingPathComponent("h.json")
        let old = #"[{"id":"7C9A1A6E-2F43-4C37-9E0B-6F1D3C2B9A11","timestamp":781912345.5,"text":"dinner is ready","targetName":"Kitchen","source":"Quick Announce"}]"#
        try Data(old.utf8).write(to: url)
        let history = BroadcastHistory(fileURL: url)
        let loaded = history.load()
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == UUID(uuidString: "7C9A1A6E-2F43-4C37-9E0B-6F1D3C2B9A11"))
        #expect(loaded.first?.timestamp == Date(timeIntervalSinceReferenceDate: 781912345.5))
        try history.append(item("new"))
        #expect(history.load().map(\.text) == ["new", "dinner is ready"])

        // And what it writes is what the old reader (a plain JSONDecoder) reads.
        let data = try Data(contentsOf: url)
        #expect(try JSONDecoder().decode([BroadcastLogItem].self, from: data).count == 2)
    }

    /// As before: a file that does not decode shows an empty list, and the
    /// next broadcast starts the list again rather than failing.
    @Test func aCorruptFileReadsEmptyAndIsReplacedByTheNextAppend() throws {
        let url = try scratchDir().appendingPathComponent("h.json")
        try Data("{not json".utf8).write(to: url)
        let history = BroadcastHistory(fileURL: url)
        #expect(history.load().isEmpty)
        try history.append(item("after"))
        #expect(history.load().map(\.text) == ["after"])
    }
}

@MainActor
@Suite struct ConfigManagerHistoryTests {
    private func manager(_ dir: URL) -> ConfigManager {
        ConfigManager(configPath: dir.appendingPathComponent("c.json"),
                      historyPath: dir.appendingPathComponent("h.json"),
                      secrets: SecretStore(fileURL: dir.appendingPathComponent("s.json")))
    }

    @Test func addLogItemKeepsWhatAnotherProcessWroteMeanwhile() throws {
        let dir = try scratchDir()
        let app = manager(dir)
        let cli = BroadcastHistory(fileURL: dir.appendingPathComponent("h.json"))
        app.addLogItem(item("app 1"))
        try cli.append(item("say 1", source: "Say"))      // app has not reloaded
        app.addLogItem(item("app 2"))
        try cli.append(item("hook 1", source: "Claude Code"))
        app.addLogItem(item("app 3"))
        let expected = ["app 3", "hook 1", "app 2", "say 1", "app 1"]
        #expect(app.recentBroadcasts.map(\.text) == expected)
        #expect(cli.load().map(\.text) == expected)
    }

    @Test func reloadHistoryShowsEntriesOthersWrote() throws {
        let dir = try scratchDir()
        let app = manager(dir)
        #expect(app.recentBroadcasts.isEmpty)
        try BroadcastHistory(fileURL: dir.appendingPathComponent("h.json")).append(item("from the CLI", source: "Say"))
        #expect(app.recentBroadcasts.isEmpty, "not until it reloads")
        app.reloadHistory()
        #expect(app.recentBroadcasts.map(\.source) == ["Say"])
    }

    @Test func addLogItemTrimsToThirty() throws {
        let app = manager(try scratchDir())
        for i in 0..<35 { app.addLogItem(item("n\(i)")) }
        #expect(app.recentBroadcasts.count == 30)
        #expect(app.recentBroadcasts.first?.text == "n34")
    }

    @Test func aCorruptFileAtLaunchShowsNothingAndDoesNotBlockRecording() throws {
        let dir = try scratchDir()
        try Data("garbage".utf8).write(to: dir.appendingPathComponent("h.json"))
        let app = manager(dir)
        #expect(app.recentBroadcasts.isEmpty)
        app.addLogItem(item("ok"))
        #expect(app.recentBroadcasts.map(\.text) == ["ok"])
    }
}

/// The lock really is what keeps writers apart. Each `BroadcastHistory`
/// call opens the lock file afresh, and a BSD flock belongs to an open file
/// description, so writers on separate threads contend for it exactly as
/// separate processes do. The last test uses a separate process too.
@Suite struct BroadcastHistoryContentionTests {
    @Test func concurrentAppendsFromSeparateWritersAreNeverLost() throws {
        let url = try scratchDir().appendingPathComponent("h.json")
        let writers = (0..<6).map { _ in BroadcastHistory(fileURL: url) }
        let items = (0..<BroadcastHistory.limit).map { item("t\($0)") }
        DispatchQueue.concurrentPerform(iterations: items.count) { i in
            _ = try? writers[i % writers.count].append(items[i])
        }
        let saved = BroadcastHistory(fileURL: url).load()
        #expect(saved.count == items.count, "every read-modify-write saw the one before it")
        #expect(Set(saved.map(\.id)) == Set(items.map(\.id)))
    }

    /// The app (on the main actor, through ConfigManager) and a background
    /// writer standing in for `--say`, interleaved for real.
    @MainActor
    @Test func appAndBackgroundWriterInterleavedLoseNothing() async throws {
        let dir = try scratchDir()
        let app = ConfigManager(configPath: dir.appendingPathComponent("c.json"),
                                historyPath: dir.appendingPathComponent("h.json"),
                                secrets: SecretStore(fileURL: dir.appendingPathComponent("s.json")))
        let cli = BroadcastHistory(fileURL: dir.appendingPathComponent("h.json"))
        let cliItems = (0..<15).map { item("cli \($0)", source: "Say") }
        let appItems = (0..<15).map { item("app \($0)") }
        let background = Task.detached {
            for i in cliItems { _ = try? cli.append(i); usleep(500) }
        }
        for i in appItems {
            app.addLogItem(i)
            await Task.yield()
        }
        await background.value
        let saved = cli.load()
        #expect(saved.count == 30)
        #expect(Set(saved.map(\.id)) == Set((cliItems + appItems).map(\.id)))
    }

    /// Held from another descriptor, the lock makes an append wait; let go,
    /// the append lands on top of what the holder wrote.
    @Test func anAppendWaitsForTheHolder() async throws {
        let url = try scratchDir().appendingPathComponent("h.json")
        let history = BroadcastHistory(fileURL: url)
        try history.append(item("before"))
        let fd = open(history.lockURL.path, O_RDWR | O_CREAT, 0o600)
        #expect(fd >= 0)
        #expect(flock(fd, LOCK_EX) == 0)
        let writer = Task.detached { try? BroadcastHistory(fileURL: url).append(item("waiter")) }
        try await Task.sleep(for: .milliseconds(300))
        #expect(history.load().map(\.text) == ["before"], "the append waits while the lock is held")
        let held = [item("holder")] + history.load()
        try JSONEncoder().encode(held).write(to: url, options: .atomic)
        flock(fd, LOCK_UN)
        close(fd)
        _ = await writer.value
        #expect(history.load().map(\.text) == ["waiter", "holder", "before"])
    }

    /// A second process (perl, which ships with macOS and calls the same
    /// flock(2)) does the same locked read-modify-write while this process
    /// appends from two threads. Nothing is lost on either side.
    @Test func anotherProcessWritingAtTheSameTimeLosesNothing() async throws {
        let dir = try scratchDir()
        let url = dir.appendingPathComponent("h.json")
        let history = BroadcastHistory(fileURL: url)
        let perlIDs = (0..<10).map { _ in UUID() }
        let script = #"""
        use strict; use warnings; use Fcntl qw(:flock); use JSON::PP; use Time::HiRes qw(usleep);
        my ($file, @ids) = @ARGV;
        my $json = JSON::PP->new;
        my $n = 0;
        for my $id (@ids) {
            open(my $lock, '>>', "$file.lock") or die "lock: $!";
            flock($lock, LOCK_EX) or die "flock: $!";
            my $items = [];
            if (open(my $in, '<', $file)) { local $/; my $raw = <$in>; close $in; $items = eval { $json->decode($raw) } || []; }
            unshift @$items, { id => $id, timestamp => 0.0 + $n, text => "perl $n", targetName => "Perl", source => "Perl" };
            splice(@$items, 30) if @$items > 30;
            open(my $out, '>', "$file.perl.tmp") or die "tmp: $!"; print $out $json->encode($items); close $out;
            rename("$file.perl.tmp", $file) or die "rename: $!";
            flock($lock, LOCK_UN); close $lock;
            $n++;
            usleep(1000);
        }
        """#
        let scriptURL = dir.appendingPathComponent("writer.pl")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        let perl = Process()
        perl.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        perl.arguments = [scriptURL.path, url.path] + perlIDs.map(\.uuidString)
        let stderr = Pipe()
        perl.standardError = stderr
        try perl.run()

        let swiftItems = (0..<20).map { item("swift \($0)") }
        await withTaskGroup(of: Void.self) { group in
            for half in [Array(swiftItems.prefix(10)), Array(swiftItems.suffix(10))] {
                group.addTask {
                    for i in half { _ = try? BroadcastHistory(fileURL: url).append(i); usleep(700) }
                }
            }
        }
        perl.waitUntilExit()
        let perlErrors = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(perl.terminationStatus == 0, "perl writer failed: \(perlErrors)")

        let saved = history.load()
        #expect(saved.count == 30)
        #expect(Set(saved.map(\.id)) == Set(swiftItems.map(\.id) + perlIDs))
    }
}

/// The Stop hook's own broadcast (home speakers only; the Mac speaking goes
/// through `--announce`, which records itself) is recorded once, and only
/// when it was sent.
@Suite struct ClaudeStopHookHistoryTests {
    private struct Fixture {
        let input: Data
        let manager: ConfigManager
        let history: BroadcastHistory
    }

    @MainActor
    private func fixture() throws -> Fixture {
        let dir = try scratchDir()
        // Unique, so the hook's /tmp de-duplication lock never silences a run.
        let reply = "The build is green and the change is ready \(UUID().uuidString)."
        let transcript = [
            #"{"message":{"role":"user","content":"is it done?"}}"#,
            #"{"message":{"role":"assistant","content":[{"type":"text","text":"\#(reply)"}]}}"#,
        ].joined(separator: "\n")
        let transcriptURL = dir.appendingPathComponent("t.jsonl")
        try transcript.write(to: transcriptURL, atomically: true, encoding: .utf8)
        let input = try JSONSerialization.data(withJSONObject: ["transcript_path": transcriptURL.path])
        let manager = ConfigManager(configPath: dir.appendingPathComponent("c.json"),
                                    historyPath: dir.appendingPathComponent("app-h.json"),
                                    secrets: SecretStore(fileURL: dir.appendingPathComponent("s.json")))
        manager.config.enabled = true
        manager.config.effectiveSpeakHome = true
        manager.config.effectiveSpeakLocal = false
        manager.config.structureId = "s1"
        manager.config.targets = ["kitchen": SpeakerDevice(id: "d1", type: "SPEAKER", name: "Kitchen speaker")]
        manager.config.defaultTarget = "kitchen"
        return Fixture(input: input, manager: manager,
                       history: BroadcastHistory(fileURL: dir.appendingPathComponent("h.json")))
    }

    @Test func aSentBroadcastIsRecorded() async throws {
        let f = try await fixture()
        await ClaudeStopHook.run(input: f.input, configManager: f.manager, history: f.history) { _, _, _, _ in true }
        let saved = f.history.load()
        #expect(saved.count == 1)
        #expect(saved.first?.source == "Claude Code")
        #expect(saved.first?.targetName == "Kitchen speaker")
        #expect(saved.first?.text.contains("build is green") == true)
    }

    @Test func aFailedBroadcastIsNotRecorded() async throws {
        let f = try await fixture()
        await ClaudeStopHook.run(input: f.input, configManager: f.manager, history: f.history) { _, _, _, _ in
            throw BroadcastError.noSpeaker
        }
        #expect(f.history.load().isEmpty)
    }

    @Test func aBroadcastThatSaidNothingIsNotRecorded() async throws {
        let f = try await fixture()
        await ClaudeStopHook.run(input: f.input, configManager: f.manager, history: f.history) { _, _, _, _ in false }
        #expect(f.history.load().isEmpty)
    }
}
