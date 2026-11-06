# live-context: live repository state and response contract

The `live-context` plugin injects a fresh snapshot of Git and GitHub state plus
your response contract before every model invocation:

1. **Live Git/GitHub state supersedes memory**: Never restate pull request or
   branch status from earlier turns if the injected live context snapshot shows
   that a pull request has since merged, closed, or changed.
2. **Response contract shape**:
   - Scale to the question: answer simple or factual questions in one or two
     sentences without headers or boilerplate.
   - For substantive engineering work: lead with the **GIST** (one or two plain
     sentences), then **DETAIL** (evidence, file links, caveats). Put any
     surprising or contradictory finding at the very top.
   - End after the detail unless there is a concrete decision or follow-up action.
     Never close with filler phrases such as `"Nothing needed from you."` or
     `"No action needed."`
