/chief-of-staff {{INPUT}}

I'm going AFK; finish the jobs I named above.
you only coordinate, so your context stays clean.
Make no judgment call yourself: ask a fresh advisor agent (the model CLAUDE.md names for an advisor, else Opus 5.5 at xhigh) and follow its answer; steps the repo's rules already settle need none.
Give it the question and the sources, not your conclusion; it judges the risk and returns its decision. Log it in wiki/afk-decisions.md, the risky ones under "Deferred to user", and never wait.
Tell every orchestrator you dispatch to do the same.
If a ticket fails the same way three times, mark it blocked and move on.
As retro result comeback, a fresh subagent applies the chosen fixes in its own worktree, merged only once the repo's own checks are green.
Before applying a retro fix, check whether it patches an earlier retro fix; if so, the earlier fix is most likely wrong or unnecessary, so revert or rewrite that one instead of stacking a second patch on top.
Never edit a skill, an agent definition, instead put those candidates in wiki/afk-decisions.md under "Deferred to user".
