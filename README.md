# afk agent farm

A small set of shell scripts that keeps a Claude Code session working on your tickets while you're away from the keyboard. One coordinator agent runs the `/chief-of-staff` skill and hands tickets out to subagents. The scripts watch it from outside. When the coordinator's context fills up, it writes a handoff and a fresh session picks up from there. When it stops halfway, goes idle or hits an API error, it gets nudged back to work. The run ends when the agent says the goal is done.

You start it with a list of tickets, go to sleep, and in the morning you read the merged work and a log of the decisions it made without you.

## Prerequisites

- **macOS.** The scripts use `tail -r` and `caffeinate`. Linux needs small patches (`tac` instead of `tail -r`, and no `caffeinate`).
- **[Claude Code](https://docs.claude.com/en/docs/claude-code)**, logged in, on a plan with enough usage for a long night.
- **[herdr](https://herdr.dev)**, the terminal multiplexer for agents: `brew install herdr`. The loop only runs inside a herdr pane.
- **jq** comes with macOS 15 and newer. On older macOS: `brew install jq`.
- A **git repo with an issue tracker** that the skills can read: GitHub issues, or the local-markdown tracker.

## Extremely suggested setup

This version only works with **[Matt Pocock's skills](https://github.com/mattpocock/skills) v1.3.2 or newer** plus the **`chief-of-staff`** skill, which you install separately.

- The master prompt (`afk.prompt.md`) starts with `/chief-of-staff`. That skill turns the session into a coordinator: subagents do all the work, and memory lives in a wiki instead of the context window.
- `chief-of-staff` lives in the repo's `in-progress/` folder, so it doesn't come with the regular plugin install. You have to add it yourself (see [How to set up](#how-to-set-up)).
- At each handoff, the stop hook tells the agent to follow the **`handoff`** skill from the same pack, and it reads it from a fixed path: `~/.agents/skills/handoff/SKILL.md`. If you installed the pack only as a Claude Code plugin, that file doesn't exist and handoffs come out worse. Either install it with `npx skills` as shown below, or edit that path in `finish-gate.sh`.
- The prompt also refers to the `retro` skill for the fixes it applies after a retro.

## Why? What is the recommended workflow

1. **Plan in daylight.** Use the [`wayfinder`](https://github.com/mattpocock/skills/tree/main/skills/engineering/wayfinder) skill from Matt's pack to turn a big, foggy idea into a map of decisions, then into specs and tickets. Make as many as you like: the more well-defined tickets there are, the longer the night run can go without you.
2. **Run it.** From your project, start `run-farmer.sh` with the tickets you want done.
3. **Walk away.** A single session can't run all night. Its context fills up and early decisions fade, subagents stop midway, the model stops to ask "should I continue?", and API errors leave it sitting idle. This small set of scripts handles each of those:
   - **Context fills up.** Past `SOFT` tokens, the coordinator gets no new work. It finishes what's running and writes a handoff, and a fresh session in the same pane continues from that handoff. Past `HARD`, running agents save their work as WIP and stop.
   - **It stops early or asks for permission.** The stop hook sends it back to work, up to `CONTINUE_LIMIT` times in a row.
   - **It goes quiet** (API error, rate limit, a hook that gave up). The outer loop retries after errors and nudges it when it's idle.
   - **It's really stuck.** You get a herdr notification instead of a night of burned tokens.

   The work keeps going from one segment to the next. It doesn't run forever, though: it stops when the agent emits `<promise>COMPLETE</promise>`, or after `MAX_SEGMENTS` segments (default 20) so a run that never converges can't burn tokens all night.
4. **Review in the morning.** Read `wiki/afk-decisions.md` in your project. Every judgment call made without you is there, each decided by a fresh advisor agent (model and effort from your CLAUDE.md), not by the coordinator. The ones the advisor calls risky, and any proposed changes to skills or agent definitions, sit under **"Deferred to user"**. Tickets that failed the same way three times are marked blocked rather than retried forever.

## How it works

1. **Take a look at `config.sh`.** The defaults are battle-tested. Change only what doesn't fit you; each setting has a comment explaining it.
2. **Take a look at `afk.prompt.md`.** These are the agent's rules for the night (don't wait for you, hand every judgment call to an advisor agent, log decisions, give up on a ticket after three identical failures). Edit them if you want different ones.
3. **Run `run-farmer.sh` inside herdr, from your project folder.** The agent opens in the pane next to it; `Ctrl-C` stops the loop, `/exit` in the pane stops the agent.
4. **Example prompt:**

   ```bash
   ~/tools/afk-agant-farm/run-farmer.sh "Implement every open ticket on the 'Billing v2' map. Merge each into main once the tests pass."
   ```

> **Heads-up:** the agent runs with `bypassPermissions`, so it won't ask before running a command.

## How to set up

**1. Install the tools**

```bash
brew install herdr
```

**2. Install Matt's skills (≥ 1.3.2) and `chief-of-staff`**

```bash
# the whole pack, into ~/.agents/skills (gives you handoff at the path the hook expects)
npx skills@latest add mattpocock/skills -g

# chief-of-staff is in-progress, so add it explicitly
npx skills@latest add mattpocock/skills --skill chief-of-staff -g
```

If you prefer the Claude Code plugin (`claude plugin install mattpocock-skills@claude-plugins-official`), you still need the `chief-of-staff` line above, and you need to point the handoff path in `finish-gate.sh` at the plugin's copy.

**3. Set up the skills in your project**

Open Claude Code in the target repo and run `/setup-matt-pocock-skills` once, so the skills know which issue tracker to use.

**4. Get this repo**

```bash
git clone https://github.com/itsfatodono/afk-agant-farm.git ~/tools/afk-agant-farm
chmod +x ~/tools/afk-agant-farm/*.sh
# optional: put it on your PATH (symlinks work, the script resolves its own folder)
ln -s ~/tools/afk-agant-farm/run-farmer.sh /usr/local/bin/afk
```

**5. Plan the work**

In your project, run `/wayfinder` and turn the result into tickets until you have a list of well-defined ones.

**6. Run it**

See [How it works](#how-it-works).

## Logs

Every run writes to `runs/<project>-<timestamp>-<pid>/`, next to the scripts:

- `run.log`: what the loop saw and did
- `prompt.txt`: the full prompt that was sent
- `seg-NN/hooks.log`: every hook decision with the context size at that point
- `seg-NN/handoff.md`: the handoff that started the next segment
- `seg-NN/transcript`: path to that segment's Claude Code transcript

## Under the hood

| File | Role |
|---|---|
| `run-farmer.sh` | The outer loop. Opens a herdr pane, starts Claude in it, watches for completion, handoff, idleness, dialogs and API errors, and restarts the session between segments. |
| `afk.prompt.md` | The standing orders. `{{INPUT}}` gets replaced by what you pass on the command line. |
| `config.sh` | Every setting. Sourced at start. `CONFIG=<file>` picks another one, e.g. per project. |
| `finish-gate.sh` | `Stop` hook. Decides whether the agent may stop, must keep going, or must write the handoff. |
| `soft-warn.sh` | `PostToolUse` hook. Warns the coordinator once its context passes `SOFT` / `HARD`. |
| `ctx.sh` | Reads the coordinator's current context size from its transcript. Subagents don't count. |
| `inflight.sh` | The one list of running work, for both the stop hook and the outer loop: background tasks recorded at the agent's last stop, plus subagents still running. A session waiting on any of them isn't treated as idle. |
| `overrides.sh` | Picks up live `/soft` and `/hard` changes during a run. |

Each segment gets its own `settings.json` holding the hooks, so the hooks are active only in the unattended session and never touch your normal Claude Code sessions.
