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

import XCTest

import HomeSpeakerCore
import HomeSpeakerToolCore

final class DriverTests: XCTestCase {
    func testEachJobIsHomeSpeakersOwnFlag() {
        XCTAssertEqual(ProcessDriver.arguments(for: .say("dinner is ready")), ["--say", "dinner is ready"])
        XCTAssertEqual(ProcessDriver.arguments(for: .volume), ["--volume"])
        XCTAssertEqual(ProcessDriver.arguments(for: .setVolume(140)), ["--set-volume", "100"], "held to 0 to 100")
        XCTAssertEqual(ProcessDriver.arguments(for: .setVolume(-3)), ["--set-volume", "0"])
        XCTAssertEqual(ProcessDriver.arguments(for: .mute), ["--mute"])
        XCTAssertEqual(ProcessDriver.arguments(for: .unmute), ["--unmute"])
    }

    func testSetupJobsAreHomeSpeakersOwnFlagsToo() {
        XCTAssertEqual(ProcessDriver.arguments(for: .signIn(chatOnly: false)), ["--sign-in"])
        XCTAssertEqual(ProcessDriver.arguments(for: .signIn(chatOnly: true)), ["--sign-in", "--chat"])
        XCTAssertEqual(ProcessDriver.arguments(for: .app(.signOut(chatOnly: false))), ["--sign-out"])
        XCTAssertEqual(ProcessDriver.arguments(for: .app(.discover(save: false, home: nil))), ["--discover"])
        XCTAssertEqual(ProcessDriver.arguments(for: .app(.discover(save: true, home: "h1"))), ["--discover", "--save", "--home", "h1"])
        XCTAssertEqual(ProcessDriver.arguments(for: .app(.loginItem(.status))), ["--login-item", "status"])
        XCTAssertEqual(ProcessDriver.arguments(for: .app(.testMediaPause)), ["--test-media-pause"])
    }

    func testDiscoveryPrintsHomesAndTheirSpeakers() {
        let output = """
        home: Lake House (h1)
          kitchen\tSpeakerDevice\tKitchen · Kitchen (main)\td1
          all\tStructure\tWhole Home\tstructure@h1
        home: Mum's (old) flat (structures/abc-2)
        home: Cabin (h3)

        """
        XCTAssertEqual(ProcessDriver.homes(in: output), [HomeStructure(id: "h1", name: "Lake House"),
                                                        HomeStructure(id: "structures/abc-2", name: "Mum's (old) flat"),
                                                        HomeStructure(id: "h3", name: "Cabin")],
                       "split at the last bracket, so a name keeps its own; the speaker lines under each are not homes")
        XCTAssertEqual(ProcessDriver.homes(in: "  home: Indented (h1)\nhome: no id\nhome: Empty ()\nsaved 1 target(s)"), [],
                       "an indented line, a line without an id and an empty id are no homes")
        XCTAssertEqual(ProcessDriver.result(of: .app(.discover(save: false, home: nil)), status: 0, output: output, error: ""),
                       .homes(ProcessDriver.homes(in: output)))
        XCTAssertEqual(ProcessDriver.result(of: .app(.discover(save: false, home: nil)), status: 1, output: "",
                                            error: "error: no homes visible to this account\n"),
                       .failed("no homes visible to this account"))
        XCTAssertEqual(ProcessDriver.result(of: .app(.discover(save: true, home: nil)), status: 0,
                                            output: "home: Cabin (h3)\nsaved 2 target(s) from Cabin\n", error: ""),
                       .done(["home: Cabin (h3)", "saved 2 target(s) from Cabin"]))
    }

    func testTheLoginItemsStateIsRead() {
        for state in [LoginItemState.enabled, .notRegistered, .requiresApproval, .notFound] {
            XCTAssertEqual(ProcessDriver.result(of: .app(.loginItem(.status)), status: 0, output: "login item: \(state.rawValue)\n", error: ""),
                           .loginItem(state))
        }
        XCTAssertEqual(ProcessDriver.result(of: .app(.loginItem(.enable)), status: 1, output: "login item: not found\n",
                                            error: "error: the login item is not found after enable; run HomeSpeaker from its .app bundle\n"),
                       .loginItem(.notFound, problem: "the login item is not found after enable; run HomeSpeaker from its .app bundle"))
        XCTAssertEqual(ProcessDriver.result(of: .app(.loginItem(.enable)), status: 1, output: "",
                                            error: "error: could not enable the login item: denied\n"),
                       .failed("could not enable the login item: denied"), "no state printed: a plain failure")
        XCTAssertEqual(ProcessDriver.result(of: .app(.loginItem(.status)), status: 0, output: "what?", error: ""),
                       .failed("HomeSpeaker did not say what the login item is"))
    }

    func testOtherSetupJobsAreDoneOrFailed() {
        XCTAssertEqual(ProcessDriver.result(of: .signIn(chatOnly: false), status: 0, output: "opening browser: accounts.google.com\nsigned in as a@b.c\n", error: ""),
                       .done(["opening browser: accounts.google.com", "signed in as a@b.c"]))
        XCTAssertEqual(ProcessDriver.result(of: .app(.signOut(chatOnly: false)), status: 1, output: "", error: ""),
                       .failed("HomeSpeaker stopped with status 1"))
        XCTAssertEqual(ProcessDriver.result(of: .app(.testMediaPause), status: 1, output: "could not pause Safari\n", error: ""),
                       .failed("could not pause Safari"), "the report is what it printed")
    }

    func testAMissingProgramFailsASetupJob() {
        let done = expectation(description: "answered")
        ProcessDriver(binary: nil).run(.signIn(chatOnly: false)) { result in
            XCTAssertEqual(result, .failed("HomeSpeaker is not installed"))
            done.fulfill()
        }
        wait(for: [done], timeout: 1)
    }

    func testWhatSayPrintsIsReadAsHomeSpeakerMeansIt() {
        XCTAssertEqual(ProcessDriver.result(of: .say("x"), status: 0, output: "sent to Kitchen\n", error: ""), .spoke("sent to Kitchen"))
        XCTAssertEqual(ProcessDriver.result(of: .say("x"), status: 0, output: "", error: "Quiet hours active until 07:00. Nothing spoken.\n"),
                       .notSpoken("Quiet hours active until 07:00. Nothing spoken."))
        XCTAssertEqual(ProcessDriver.result(of: .say("x"), status: 1, output: "", error: "broadcasting is switched off\n"),
                       .notSpoken("broadcasting is switched off"))
        XCTAssertEqual(ProcessDriver.result(of: .say("x"), status: 1, output: "error: timed out", error: ""), .notSpoken("error: timed out"))
    }

    func testTheVolumeJSONIsReadAndItsRefusalsAreWords() {
        let read = ProcessDriver.result(of: .volume, status: 0,
                                        output: #"{"available":true,"muted":false,"online":true,"percent":40,"speaker":"Kitchen"}"#, error: "")
        XCTAssertEqual(read, .volume(Volume(speaker: "Kitchen", percent: 40, muted: false, online: true)))
        XCTAssertEqual(ProcessDriver.result(of: .setVolume(20), status: 1,
                                            output: #"{"available":false,"reason":"no default speaker; open HomeSpeaker and pick one"}"#, error: ""),
                       .unavailable("no default speaker; open HomeSpeaker and pick one"))
        XCTAssertEqual(ProcessDriver.result(of: .mute, status: 1, output: "", error: "crashed"), .unavailable("crashed"))
        XCTAssertEqual(ProcessDriver.result(of: .unmute, status: 0, output: "", error: ""), .unavailable("HomeSpeaker printed no answer"))
    }

    func testHomeSpeakerIsFoundByLaunchServicesThenInTheUsualPlaces() {
        let known = URL(fileURLWithPath: "/Users/me/Apps/HomeSpeaker.app")
        let executables: Set<String> = ["/Users/me/Apps/HomeSpeaker.app/Contents/MacOS/HomeSpeaker",
                                        "/Users/me/Applications/HomeSpeaker.app/Contents/MacOS/HomeSpeaker"]
        XCTAssertEqual(ProcessDriver.locate(environment: [:], known: { known }, home: "/Users/me", isExecutable: executables.contains)?.path,
                       "/Users/me/Apps/HomeSpeaker.app/Contents/MacOS/HomeSpeaker")
        XCTAssertEqual(ProcessDriver.locate(environment: [:], known: { nil }, home: "/Users/me", isExecutable: executables.contains)?.path,
                       "/Users/me/Applications/HomeSpeaker.app/Contents/MacOS/HomeSpeaker")
        XCTAssertNil(ProcessDriver.locate(environment: [:], known: { nil }, home: "/Users/nobody", isExecutable: { _ in false }))
        // The environment names a build, or, empty, no HomeSpeaker at all.
        XCTAssertEqual(ProcessDriver.locate(environment: ["HOMESPEAKER_PROGRAM": "/tmp/HomeSpeaker"], known: { known },
                                            home: "/Users/me", isExecutable: { $0 == "/tmp/HomeSpeaker" })?.path, "/tmp/HomeSpeaker")
        XCTAssertNil(ProcessDriver.locate(environment: ["HOMESPEAKER_PROGRAM": ""], known: { known }, home: "/Users/me",
                                          isExecutable: executables.contains), "set and empty: this Mac's HomeSpeaker is not used")
        XCTAssertFalse(ProcessDriver(binary: nil).isInstalled)
    }

    func testAMissingProgramAnswersWithoutStartingAnything() {
        let done = expectation(description: "answered")
        ProcessDriver(binary: nil).run(.volume) { result in
            XCTAssertEqual(result, .unavailable("HomeSpeaker is not installed"))
            done.fulfill()
        }
        wait(for: [done], timeout: 1)
    }
}
