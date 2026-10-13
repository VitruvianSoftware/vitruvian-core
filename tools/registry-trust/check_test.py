# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

"""Every released version came from the workflow, or is the one recorded
exception. Registry answers are recorded files; nothing here uses the network."""

import copy
import io
import json
import os
import tempfile
import unittest

import check
import fixture_repo
import inventory

HERE = os.path.dirname(os.path.abspath(__file__))
PUBSUB = "@vitruviansoftware/foundation-pubsub"
KIT = "@vitruviansoftware/tool-kit"
CRATE = "vitruvian-tool-kit"


def recorded(name):
    with open(os.path.join(HERE, "testdata", name), encoding="utf-8") as handle:
        return json.load(handle)


def package(
    registry, name, repo="VitruvianSoftware/vitruvian-sdk", workflow="release.yml"
):
    owner, repo = repo.split("/")
    return inventory.Package(
        registry, name, "1.1.0", "x", "x", "x", owner, repo, workflow, "job", ""
    )


def row(registry, name, version):
    return check.Row(registry, name, version, "2026-10-13", "the first publish")


class Registry:
    """Answers by address, from what a test put there. An address no test put
    there is a test that would have used the network."""

    def __init__(self):
        self.answers = {}
        self.asked = []

    def put(self, url, body, status=200):
        self.answers[url] = (status, json.dumps(body).encode())

    def __call__(self, url):
        self.asked.append(url)
        if url not in self.answers:
            raise AssertionError(f"the check asked for {url}, which no test recorded")
        return self.answers[url]


def run(packages, rows, registry):
    out = io.StringIO()
    code = check.report(check.check(packages, rows, registry), out)
    return code, out.getvalue()


NPM = "https://registry.npmjs.org/"
CRATES = "https://crates.io/api/v1/crates/"
PYPI = "https://pypi.org/"


class NpmTest(unittest.TestCase):
    def setUp(self):
        self.registry = Registry()
        self.registry.put(
            NPM + "@vitruviansoftware%2Ffoundation-pubsub",
            recorded("npm-foundation-pubsub.json"),
        )
        self.registry.put(
            NPM + "@vitruviansoftware%2Ftool-kit", recorded("npm-tool-kit.json")
        )

    def test_a_workflow_s_versions_pass_and_recorded_history_is_said(self):
        code, out = run(
            [package("npm", PUBSUB)], [row("npm", PUBSUB, "0.2.0")], self.registry
        )
        self.assertEqual(code, 0, out)
        self.assertIn("1 by the workflow", out)
        self.assertIn("2 before the workflow took over", out)

    def test_a_person_s_version_with_no_row_is_named(self):
        code, out = run([package("npm", PUBSUB)], [], self.registry)
        self.assertEqual(code, 1)
        self.assertIn(f"npm {PUBSUB} 0.1.0", out)
        self.assertIn(f"npm {PUBSUB} 0.2.0", out)
        self.assertIn("ipv1337", out)
        self.assertNotIn(f"{PUBSUB} 0.4.1", out)

    def test_a_person_s_version_after_the_recorded_one_is_named(self):
        code, out = run(
            [package("npm", PUBSUB)], [row("npm", PUBSUB, "0.1.0")], self.registry
        )
        self.assertEqual(code, 1)
        self.assertIn(f"npm {PUBSUB} 0.2.0", out)
        self.assertNotIn(f"npm {PUBSUB} 0.1.0:", out)

    def test_an_earlier_person_s_version_is_history_of_the_recorded_one(self):
        # 0.0.0-stage went up a minute before 1.1.0, the recorded bootstrap.
        code, out = run(
            [package("npm", KIT)], [row("npm", KIT, "1.1.0")], self.registry
        )
        self.assertEqual(code, 0, out)
        self.assertIn("0 by the workflow", out)
        self.assertIn("2 before the workflow took over", out)

    def test_a_trusted_publisher_with_no_attestation_is_not_the_workflow(self):
        answer = recorded("npm-foundation-pubsub.json")
        del answer["versions"]["0.4.1"]["dist"]["attestations"]
        self.registry.put(NPM + "@vitruviansoftware%2Ffoundation-pubsub", answer)
        code, out = run(
            [package("npm", PUBSUB)], [row("npm", PUBSUB, "0.2.0")], self.registry
        )
        self.assertEqual(code, 1)
        self.assertIn(f"npm {PUBSUB} 0.4.1", out)

    def test_an_attestation_with_no_trusted_publisher_is_not_the_workflow(self):
        answer = recorded("npm-foundation-pubsub.json")
        del answer["versions"]["0.4.1"]["_npmUser"]["trustedPublisher"]
        self.registry.put(NPM + "@vitruviansoftware%2Ffoundation-pubsub", answer)
        code, out = run(
            [package("npm", PUBSUB)], [row("npm", PUBSUB, "0.2.0")], self.registry
        )
        self.assertEqual(code, 1)
        self.assertIn(f"npm {PUBSUB} 0.4.1", out)

    def test_a_row_for_a_version_the_registry_lacks_excuses_nothing(self):
        code, out = run(
            [package("npm", PUBSUB)], [row("npm", PUBSUB, "0.3.0")], self.registry
        )
        self.assertEqual(code, 1)
        self.assertIn("0.3.0, which npm does not have", out)

    def test_a_row_for_a_version_the_workflow_published_excuses_nothing(self):
        code, out = run(
            [package("npm", PUBSUB)], [row("npm", PUBSUB, "0.4.1")], self.registry
        )
        self.assertEqual(code, 1)
        self.assertIn("0.4.1, which the workflow published", out)

    def test_a_package_the_registry_does_not_have_is_said_and_is_not_a_failure(self):
        self.registry.put(NPM + "@vitruviansoftware%2Fnew", {"error": "Not found"}, 404)
        code, out = run([package("npm", "@vitruviansoftware/new")], [], self.registry)
        self.assertEqual(code, 0, out)
        self.assertIn("not yet on the registry", out)

    def test_an_answer_that_is_neither_there_nor_not_there_is_not_guessed(self):
        self.registry.put(NPM + "@vitruviansoftware%2Fnew", {}, 503)
        with self.assertRaises(check.RegistryError) as raised:
            run([package("npm", "@vitruviansoftware/new")], [], self.registry)
        self.assertIn("503", str(raised.exception))


class CratesTest(unittest.TestCase):
    def setUp(self):
        self.registry = Registry()
        self.registry.put(
            CRATES + "vitruvian-tool-kit/versions?per_page=100",
            recorded("crates-vitruvian-tool-kit.json"),
        )

    def test_the_recorded_first_publish_passes(self):
        code, out = run(
            [package("crates", CRATE)], [row("crates", CRATE, "1.1.0")], self.registry
        )
        self.assertEqual(code, 0, out)
        self.assertIn("1 before the workflow took over", out)

    def test_a_person_s_version_with_no_row_is_named(self):
        code, out = run([package("crates", CRATE)], [], self.registry)
        self.assertEqual(code, 1)
        self.assertIn(f"crates {CRATE} 1.1.0", out)
        self.assertIn("ipv1337", out)

    def test_a_trusted_upload_from_the_mirror_is_the_workflow(self):
        self.registry.put(CRATES + "bon/versions?per_page=100", self.one_page())
        code, out = run(
            [package("crates", "bon", repo="elastio/bon")], [], self.registry
        )
        self.assertEqual(code, 0, out)
        self.assertIn("2 by the workflow", out)

    def test_a_trusted_upload_from_another_repository_is_named(self):
        self.registry.put(CRATES + "bon/versions?per_page=100", self.one_page())
        code, out = run(
            [package("crates", "bon", repo="elastio/other")], [], self.registry
        )
        self.assertEqual(code, 1)
        self.assertIn("crates bon 3.10.2", out)
        self.assertIn("elastio/bon", out)

    def test_every_page_of_versions_is_read(self):
        first = recorded("crates-bon-page1.json")
        second = self.one_page()
        second["versions"] = [
            dict(
                second["versions"][0],
                num="3.10.0",
                trustpub_data=None,
                published_by={"login": "someone"},
            )
        ]
        self.registry.put(CRATES + "bon/versions?per_page=100", first)
        self.registry.put(CRATES + "bon/versions" + first["meta"]["next_page"], second)
        code, out = run(
            [package("crates", "bon", repo="elastio/bon")], [], self.registry
        )
        self.assertEqual(code, 1)
        self.assertIn("crates bon 3.10.0", out)
        self.assertIn("someone", out)

    @staticmethod
    def one_page():
        page = recorded("crates-bon-page1.json")
        page["meta"]["next_page"] = None
        return page


class PyPITest(unittest.TestCase):
    FILES = [
        "vitruvian_tool_kit-0.10.0-py3-none-any.whl",
        "vitruvian_tool_kit-0.10.0.tar.gz",
        "vitruvian_tool_kit-1.0.0-py3-none-any.whl",
        "vitruvian_tool_kit-1.0.0.tar.gz",
        "vitruvian_tool_kit-1.1.0-py3-none-any.whl",
        "vitruvian_tool_kit-1.1.0.tar.gz",
    ]

    def setUp(self):
        self.registry = Registry()
        self.registry.put(
            PYPI + "pypi/vitruvian-tool-kit/json",
            recorded("pypi-vitruvian-tool-kit.json"),
        )
        for name in self.FILES:
            self.registry.put(
                self.provenance(name), {"message": "No provenance available"}, 404
            )

    @staticmethod
    def provenance(name):
        version = name.split("-")[1].removesuffix(".tar.gz")
        return f"{PYPI}integrity/vitruvian-tool-kit/{version}/{name}/provenance"

    def attest(
        self,
        version,
        repository="VitruvianSoftware/vitruvian-sdk",
        workflow="release.yml",
    ):
        answer = recorded("pypi-provenance-sampleproject.json")
        publisher = answer["attestation_bundles"][0]["publisher"]
        publisher["repository"], publisher["workflow"] = repository, workflow
        for name in self.FILES:
            if f"-{version}" in name:
                self.registry.put(self.provenance(name), copy.deepcopy(answer))

    def test_no_provenance_is_reported_as_not_verifiable_never_as_passed(self):
        code, out = run(
            [package("pypi", CRATE)], [row("pypi", CRATE, "1.1.0")], self.registry
        )
        self.assertEqual(code, 0, out)
        self.assertIn("3 not publicly verifiable", out)
        self.assertIn("0 by the workflow", out)
        self.assertIn("PyPI says nothing public about who published", out)

    def test_no_provenance_with_no_row_is_named(self):
        code, out = run([package("pypi", CRATE)], [], self.registry)
        self.assertEqual(code, 1)
        for version in ("0.10.0", "1.0.0", "1.1.0"):
            self.assertIn(f"pypi {CRATE} {version}", out)

    def test_no_provenance_after_the_recorded_version_is_named(self):
        code, out = run(
            [package("pypi", CRATE)], [row("pypi", CRATE, "1.0.0")], self.registry
        )
        self.assertEqual(code, 1)
        self.assertIn(f"pypi {CRATE} 1.1.0", out)
        self.assertNotIn(f"pypi {CRATE} 1.0.0:", out)

    def test_provenance_from_the_mirror_s_workflow_is_the_workflow(self):
        self.attest("1.1.0")
        code, out = run(
            [package("pypi", CRATE)], [row("pypi", CRATE, "1.0.0")], self.registry
        )
        self.assertEqual(code, 0, out)
        self.assertIn("1 by the workflow", out)
        self.assertIn("2 not publicly verifiable", out)

    def test_provenance_for_one_file_of_two_is_not_the_workflow(self):
        self.attest("1.1.0")
        self.registry.put(self.provenance(self.FILES[5]), {"message": "none"}, 404)
        code, out = run(
            [package("pypi", CRATE)], [row("pypi", CRATE, "1.0.0")], self.registry
        )
        self.assertEqual(code, 1)
        self.assertIn(f"pypi {CRATE} 1.1.0", out)

    def test_provenance_from_another_repository_is_named(self):
        self.attest("1.1.0", repository="someone/else")
        code, out = run(
            [package("pypi", CRATE)], [row("pypi", CRATE, "1.1.0")], self.registry
        )
        self.assertEqual(code, 1)
        self.assertIn(f"pypi {CRATE} 1.1.0", out)
        self.assertIn("someone/else", out)

    def test_provenance_from_another_workflow_is_named(self):
        self.attest("1.1.0", workflow="other.yml")
        code, out = run(
            [package("pypi", CRATE)], [row("pypi", CRATE, "1.1.0")], self.registry
        )
        self.assertEqual(code, 1)
        self.assertIn("other.yml", out)


class LedgerTest(unittest.TestCase):
    GOOD = "npm\t@x/a\t1.0.0\t2026-10-13\tthe registry refuses a trusted publisher for a package that does not exist\n"

    def test_a_row_is_five_fields_and_comments_are_skipped(self):
        rows, problems = check.parse_ledger("# registry\tpackage\n\n" + self.GOOD)
        self.assertEqual(problems, [])
        self.assertEqual(
            rows, [check.Row("npm", "@x/a", "1.0.0", "2026-10-13", rows[0].why)]
        )

    def test_two_rows_for_one_package_is_a_problem(self):
        other = self.GOOD.replace("1.0.0", "1.1.0")
        rows, problems = check.parse_ledger(self.GOOD + other)
        self.assertEqual(len(problems), 1)
        self.assertIn("more than one row for npm @x/a", problems[0])

    def test_the_same_name_on_two_registries_is_two_packages(self):
        rows, problems = check.parse_ledger(
            self.GOOD + self.GOOD.replace("npm", "crates")
        )
        self.assertEqual(problems, [])
        self.assertEqual(len(rows), 2)

    def test_a_row_with_a_field_missing_is_a_problem(self):
        for bad in (
            "npm\t@x/a\t1.0.0\t2026-10-13\n",
            "npm\t@x/a\t1.0.0\t2026-10-13\t \n",
            "gems\t@x/a\t1.0.0\t2026-10-13\twhy\n",
            "npm\t@x/a\t1.0.0\tyesterday\twhy\n",
            "npm @x/a 1.0.0 2026-10-13 why\n",
        ):
            rows, problems = check.parse_ledger(bad)
            self.assertEqual(len(problems), 1, bad)
            self.assertIn("line 1", problems[0])

    def test_a_row_for_a_package_not_in_the_inventory_is_a_problem(self):
        rows, _ = check.parse_ledger(self.GOOD)
        problems = check.unknown_rows(rows, [package("npm", "@x/b")])
        self.assertEqual(len(problems), 1)
        self.assertIn("npm @x/a", problems[0])
        self.assertEqual(check.unknown_rows(rows, [package("npm", "@x/a")]), [])

    def test_the_real_ledger_is_well_formed_with_one_row_a_package(self):
        with open(os.path.join(HERE, "bootstrap.tsv"), encoding="utf-8") as handle:
            rows, problems = check.parse_ledger(handle.read())
        self.assertEqual(problems, [])
        keys = [(r.registry, r.package) for r in rows]
        self.assertEqual(len(keys), len(set(keys)))
        self.assertIn(
            ("npm", KIT, "1.1.0"), [(r.registry, r.package, r.version) for r in rows]
        )
        self.assertIn(
            ("crates", CRATE, "1.1.0"),
            [(r.registry, r.package, r.version) for r in rows],
        )


class RequestTest(unittest.TestCase):
    def test_a_request_says_who_is_asking_and_carries_nothing_else(self):
        request = check.request_for(
            "https://crates.io/api/v1/crates/x/versions?per_page=100"
        )
        self.assertIn(
            "VitruvianSoftware/vitruvian-core", request.get_header("User-agent")
        )
        self.assertIn("registry-trust", request.get_header("User-agent"))
        self.assertEqual(request.get_method(), "GET")
        self.assertFalse(request.has_header("Authorization"))

    def test_only_the_three_registries_are_ever_asked(self):
        with self.assertRaises(ValueError):
            check.request_for("https://example.com/x")


class FetchTest(unittest.TestCase):
    """The real fetch, with the opening of an address replaced."""

    class Answer:
        def __init__(self, status, body=b"{}"):
            self.status, self.body = status, body

        def __enter__(self):
            return self

        def __exit__(self, *_):
            return False

        def read(self):
            return self.body

    def fetch(self, statuses):
        import urllib.error

        asked, slept = [], []

        def opener(request, timeout):
            asked.append(request.full_url)
            status = statuses[len(asked) - 1]
            if status == "down":
                raise urllib.error.URLError("no route")
            if status >= 400:
                raise urllib.error.HTTPError(
                    request.full_url, status, "x", {}, io.BytesIO(b"{}")
                )
            return self.Answer(status)

        result = check.http_fetch(
            "https://registry.npmjs.org/x", opener=opener, sleep=slept.append
        )
        return result, asked, slept

    def test_a_registry_that_is_briefly_down_is_asked_again(self):
        (status, _), asked, slept = self.fetch([503, "down", 200])
        self.assertEqual(status, 200)
        self.assertEqual(len(asked), 3)
        self.assertEqual(len(slept), 2)

    def test_not_there_is_an_answer_and_is_not_asked_twice(self):
        (status, _), asked, _ = self.fetch([404])
        self.assertEqual((status, len(asked)), (404, 1))

    def test_a_registry_that_stays_down_is_an_error_not_a_guess(self):
        with self.assertRaises(check.RegistryError):
            self.fetch(["down", "down", "down", "down"])
        (status, _), asked, _ = self.fetch([503, 503, 503, 503])
        self.assertEqual((status, len(asked)), (503, 4))


class SummaryTest(unittest.TestCase):
    def test_the_summary_counts_each_kind_apart(self):
        registry = Registry()
        registry.put(
            NPM + "@vitruviansoftware%2Ffoundation-pubsub",
            recorded("npm-foundation-pubsub.json"),
        )
        registry.put(
            PYPI + "pypi/vitruvian-tool-kit/json",
            recorded("pypi-vitruvian-tool-kit.json"),
        )
        for name in PyPITest.FILES:
            registry.put(PyPITest.provenance(name), {}, 404)
        code, out = run(
            [package("npm", PUBSUB), package("pypi", CRATE)],
            [row("npm", PUBSUB, "0.2.0"), row("pypi", CRATE, "1.1.0")],
            registry,
        )
        self.assertEqual(code, 0, out)
        last = out.strip().split("\n")[-1]
        self.assertIn("2 package(s)", last)
        self.assertIn("1 version(s) by the workflow", last)
        self.assertIn("2 before the workflow took over", last)
        self.assertIn("3 not publicly verifiable", last)
        self.assertNotIn("passed", out.lower())


class MainTest(unittest.TestCase):
    """The command: the inventory of a repository, its ledger, the registries."""

    ROW = "{}\t{}\t1.1.0\t2026-10-13\tthe first publish\n"

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(dir=os.environ.get("TEST_TMPDIR"))
        self.addCleanup(self._tmp.cleanup)
        self.root = fixture_repo.make(self._tmp.name)
        self.registry = Registry()
        for name in ("@example%2Fa", "@example%2Fb", "@example%2Fkit"):
            self.registry.put(NPM + name, recorded("npm-tool-kit.json"))
        self.registry.put(
            CRATES + "example-kit/versions?per_page=100",
            recorded("crates-vitruvian-tool-kit.json"),
        )
        self.registry.put(PYPI + "pypi/example-kit/json", {"releases": {}})
        self.ledger(
            "".join(
                self.ROW.format("npm", n)
                for n in ("@example/a", "@example/b", "@example/kit")
            )
            + self.ROW.format("crates", "example-kit")
        )

    def ledger(self, text):
        fixture_repo.write(self.root, check.LEDGER, text)

    def main(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        code = check.main(
            list(argv), fetch=self.registry, out=out, err=err, root=self.root
        )
        return code, out.getvalue(), err.getvalue()

    def test_every_package_of_the_inventory_is_asked_about(self):
        code, out, err = self.main()
        self.assertEqual(code, 0, out + err)
        self.assertIn("5 package(s)", out)
        self.assertEqual(len(self.registry.asked), 5)

    def test_a_person_s_publish_is_exit_1(self):
        self.ledger(self.ROW.format("crates", "example-kit"))
        code, out, _ = self.main()
        self.assertEqual(code, 1)
        self.assertIn("npm @example/a 1.1.0", out)

    def test_two_rows_for_a_package_is_exit_2_and_no_registry_is_asked(self):
        self.ledger(self.ROW.format("npm", "@example/a") * 2)
        code, _, err = self.main()
        self.assertEqual(code, 2)
        self.assertIn("more than one row for npm @example/a", err)
        self.assertEqual(self.registry.asked, [])

    def test_a_row_for_a_package_that_is_not_released_is_exit_2(self):
        self.ledger(self.ROW.format("npm", "@example/gone"))
        code, _, err = self.main()
        self.assertEqual(code, 2)
        self.assertIn("@example/gone", err)

    def test_no_ledger_is_exit_2(self):
        os.remove(os.path.join(self.root, check.LEDGER))
        code, _, err = self.main()
        self.assertEqual(code, 2)
        self.assertIn("bootstrap.tsv is missing", err)

    def test_a_registry_that_cannot_be_read_is_exit_2_not_a_pass(self):
        self.registry.put(NPM + "@example%2Fb", {}, 502)
        code, out, err = self.main()
        self.assertEqual(code, 2)
        self.assertIn("502", err)
        self.assertNotIn("registry-trust:", out)

    def test_a_broken_inventory_is_exit_2(self):
        os.remove(os.path.join(self.root, "tools/copybara/copy.bara.sky"))
        code, _, err = self.main()
        self.assertEqual(code, 2)
        self.assertEqual(self.registry.asked, [])

    def test_an_argument_is_exit_2(self):
        self.assertEqual(self.main("--fix")[0], 2)


if __name__ == "__main__":
    unittest.main()
