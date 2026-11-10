# Settings for run-farmer.sh. This file is bash, sourced once when a run starts: write
# KEY=value with no spaces around "=", and quote values that contain spaces. Editing it
# during a run changes nothing; /soft N and /hard N in the herdr window are the only live knobs.
# For a one-off change, set an environment variable with the same name instead of editing:
#   SOFT=600000 ./run-farmer.sh "S09 S10"
# CONFIG=other.sh ./run-farmer.sh ... uses another file, e.g. per project.

# --- What the agent is told and who runs it --------------------------------------------

# The standing orders. What you type when starting a run is usually just the job list
# ("S09 S10 S12"). This file wraps it with the rules for working alone: don't wait for
# answers, log decisions, give up on a ticket after three identical failures. To change how
# the agent behaves overnight, edit afk.prompt.md, not this setting. Set it to "" when you
# want to write the whole prompt yourself. The path is relative to this folder.
MASTER="afk.prompt.md"

# The main agent only coordinates: it hands out tickets, reads reports and merges. Subagents
# do the actual work and pick their own model and effort for each task, so these two
# settings don't reach them. Raise EFFORT if the coordinator makes poor calls; lower it to
# save tokens over a long night. Opus 5.5 medium is perfect for the job.
MODEL=opus
EFFORT=medium

# Anything else you'd pass on the claude command line, as a bash array: one item per
# argument, quote an item that contains spaces, e.g.
#   CLAUDE_ARGS=(--append-system-prompt "Keep reports short.")
# As an environment variable it is a plain string, split on spaces.
CLAUDE_ARGS=()

# --- Context: when to start a fresh session ---------------------------------------------
# A session gets worse as its context fills: early decisions fade, every turn costs more,
# and automatic compaction drops details unpredictably. So the run works in segments. When
# the main agent's context gets big, it wraps up, writes a handoff, and a fresh session in
# the same pane continues from that handoff. Subagents have their own context; only the
# main agent's counts here.

# Past this many tokens the agent starts no new work, lets running agents finish, then
# writes the handoff. Lower it if the coordinator gets sloppy late in a session; raise it
# if handoffs come so often that too much gets lost between segments.
SOFT=200000

# The emergency brake. After SOFT, agents that are still running keep reporting back, and
# every report adds to the context. At HARD the agent stops waiting: running agents save
# their work as WIP and stop, so the handoff gets written while there's still room. Leave
# enough gap above SOFT for the reports of everything that might be running.
HARD=500000

# Guards against a run that never converges, where each segment hands off to the next
# without finishing and burns tokens all night. A normal night needs a handful at most.
MAX_SEGMENTS=20

# --- When the agent stops early or gets stuck -------------------------------------------

# Models like to stop halfway, summarise, or ask "should I continue?". Nobody is there to
# answer, so the stop hook sends it back to work. If it keeps stopping with nothing running
# in between, it's stuck, and sending it back forever only burns tokens. After this many
# stops in a row the hook lets it stop and the idle nudges below take over. The count starts
# over whenever agents run again, so one long night doesn't use it up.
CONTINUE_LIMIT=10

# During wind-down the agent sometimes ends its turn without writing the handoff. Without it
# the next segment would start blind, so the hook asks again. If it still hasn't written one
# after this many asks, more asking won't help; the session goes idle and falls to the
# nudges, then to you.
HANDOFF_LIMIT=5

# The stop hook only runs when the agent ends a turn. If the session goes quiet for another
# reason (an API error, or the hook already gave up), nothing would wake it. The loop watches
# from outside: if nothing has happened for this many seconds and no agents are running, it
# retries after an API error or nudges the agent. Long subagent work doesn't count as idle,
# so this can stay short.
STALL=600

# Background tasks (a shell command, a monitor) are seen only by the stop hook, which records
# them at each stop so the idle check above counts them too. Finishing one wakes the agent and
# its next stop updates the record. Should that wake never come, a record older than this many
# seconds stops counting, so the nudges can still fire. Keep it above your longest background
# command (a full test run, say); subagents are tracked separately and never time out.
TASK_MAX=3600

# If this many nudges in a row didn't get it moving, another won't. The loop stops nudging
# and sends you a notification. The count starts over once agents run again.
MAX_NUDGES=3

# Rate limits and overloaded errors usually clear up on their own, so the loop waits and
# retries. With the defaults it rides out an hour of errors (6 x 600 s). Past that it's
# probably an outage or a spent quota, and the run waits for you with the session still open
# in its pane. If your usage limits take longer to reset, raise RETRY_WAIT.
MAX_RETRIES=6
RETRY_WAIT=600

# Seconds between the loop's checks: is the goal done, is the handoff written, is the session
# idle, is it waiting on a dialog. Checks are cheap; this only sets how quickly the loop notices.
POLL=15
