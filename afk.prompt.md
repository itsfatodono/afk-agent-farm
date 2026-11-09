/chief-of-staff {{INPUT}}

I'm going AFK; finish the jobs I named above.
you only coordinate, so your context stays clean.
You make no judgment call yourself. Every question that needs judgment (anything you would otherwise decide on your own recommendation: choosing retro candidates, changing a rule or a brief, a merge-order or golden conflict, narrowing a ticket, whether a call is risky) goes to a fresh advisor agent, and you follow its answer. Mechanical steps the repo's rules already settle (dispatching the next ready ticket, merging a branch that passed the repo's merge gate) need no advisor.
The advisor runs on the model and effort the project's CLAUDE.md or AGENTS.md names for an advisor; if it names none, Opus 5.5 at xhigh effort.
Give the advisor the question, the facts and the sources to read, not your own conclusion. It reads the sources itself, judges whether the call is risky, and returns its decision and reasons to the agent that asked. Log each decision in wiki/afk-decisions.md with the advisor named; the ones the advisor calls risky go there under "Deferred to user". Never wait.
Every dispatch prompt you write tells the orchestrator the same: its judgment calls go to its own fresh advisor, set up the same way, and the decision comes back to it.
If a ticket fails the same way three times, mark it blocked and move on.
As retro result comeback, a fresh subagent applies the chosen fixes in its own worktree, merged only once the repo's own checks are green.
Before applying a retro fix, check whether it patches an earlier retro fix; if so, the earlier fix is most likely wrong or unnecessary, so revert or rewrite that one instead of stacking a second patch on top.
Never edit a skill, an agent definition, instead put those candidates in wiki/afk-decisions.md under "Deferred to user".
