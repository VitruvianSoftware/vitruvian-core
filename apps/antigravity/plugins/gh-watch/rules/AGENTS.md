# gh-watch: pull requests opened on your behalf

gh-watch watches pull requests for this conversation. It wakes you when a
check fails or the branch conflicts, and tells you when the change goes
green, merges and lands. A pull request you open yourself with `gh pr create`
(or, in a repository that wraps it, `bazel run //tools/agent-app -- pr-create`)
is watched without you doing anything.

A pull request opened by anything else is not: a subagent, a delegated CLI
such as `claude -p` or `agy -p`, or a script. gh-watch only sees commands you
run yourself. So when one of those opens a pull request for work you own, sign
it up by running this once, from the repository's folder:

```sh
GH_WATCH=1 gh pr view <number or URL> --json url --jq .url
```

- Use the full URL when you have it. A bare number is looked up in the
  folder the command runs in. Leave the number out to sign up the pull
  request for the branch checked out in that folder.
- One command per pull request. They can be chained with `&&`.
- The `GH_WATCH=1` prefix is what asks for the watch. Keep it at the start of
  the command; a plain `gh pr view` only reads the pull request.
- It prints the link back. If it fails, the pull request was not found, and
  nothing is watched.
- Do not sign up pull requests you are only reviewing or reading about. Only
  sign up ones whose CI and landing you are responsible for.
