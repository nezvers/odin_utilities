#+build !js
// The two helps of amsg. A person gets the commands of the terminal (spawn, dismiss, group messages, trust, ...); an agent gets the tools of
// the channel and nothing else, so that what is meant for the person at the keyboard is never in front of the agent. `amsg --help` decides
// by the environment: the agent process is started with AMSG_AGENT=1 (agent.odin), so a program that the agent runs sees the agent's help,
// and `amsg` itself refuses to start a second member from there.
package ai_messaging

import "core:os"
import "core:strings"
import "core:testing"

// Is this program running inside an agent (started by an agent, or by a tool the agent was given)?
HelpInAgent :: proc() -> bool {
    return os.get_env("AMSG_AGENT", context.temp_allocator) != ""
}

HelpUser :: proc() -> string {
    return `amsg: a member of a channel of people and AI agents, no server.

  amsg <channel> [--name N] [--dir received] [--auto-accept] [--host | --guest] [--no-lan] [--stun] [--max-mb N] [--json] [--password P]
                 [--exclude name]... [--include-git] [--keep-exec] [--derp [N] | --derp-host name] [--derp-only] [--auto-reconnect]
                 [--agent [model]] [--agent-model M] [--agent-cmd claude] [--agent-tools Read,Glob] [--agent-dir agent_files]
                 [--listen mentions|all|none] [--agent-trust ask|members|name,name] [--allow-remote-agent]

Lines you type (only a line that starts with "--" and a letter is a command; a space in front makes any line a plain message):
  text                          to your agent when you have one, else to everybody
  /command                      a slash command of Claude Code, to your agent untouched (/context, /compact, /clear, ...)
  --group_msg text              to everybody (--group is the short form)
  --to bob text                 private, to one member
  --send bob path               a file or a whole folder to bob (--send all path: everybody); the receiver accepts or declines
  --yes 3 / --no 3              answer the offer number 3        --cancel 3      stop transfer 3
  --who  --code  --reconnect  --quit
Your agent (Claude Code, one per terminal, private to you):
  --spawn [model]               start it (haiku, sonnet, opus or a full model id)         --dismiss     end it
  --agents                      yours and who else has one       --listen mentions|all|none   what the channel passes to it
  --trust ask|members|bob,carol how far it believes what other members write
Other members' agents (they decide, you only ask):
  --spawn bob [model]           ask bob to start their agent     --dismiss bob   ask them to end it
  --cmd bob /compact            ask bob to run a slash command on their agent (--private is the same)
  --subscribe_idle bob          get bob's agent's last message (its report) whenever it finishes its work and goes idle, passed to your
                                agent without spending its tokens; bob agrees first.   --unsubscribe_idle bob   stop
  --subscribe_spawned           tell your agent whenever an agent of the channel starts or ends (or its member leaves), and who has one now,
                                so it can reorganize the work; no consent needed, it is public.   --unsubscribe_spawned   stop
  --yes agent / --no agent      what you answer when somebody asks that of you
Remote control of a device (this one to a member, or theirs to you):
  --remote bob                  bob may run commands on THIS device (with your rights) and give orders to its agent; bob is told
  --remote_disable [bob]        take it back from bob (from everybody); they are told and a running command is stopped
  --run bob <command>           run one command on bob's device when bob gave you remote control (output comes back, 60 s at most)
  amsg <channel> --headless --password P --remote bob ...   a device without a keyboard: bob is trusted whenever he joins (--remote-dir, --remote-timeout)
Only the host (the member that opened the channel) can give orders:
  --kick bob                    dismiss bob's agent now, without asking (bob stays and can start another one)
  --ban bob                     remove bob: their program is told to close (its agent too), the link is cut a moment later, and the name
                                cannot join again while this host runs
  --close_group                 end the group: every member's program closes (agents too), then this one
`
}

// Only the tools of the channel, as the agent uses them, and how its messages arrive.
HelpAgent :: proc() -> string {
    return `You are an agent in a channel of people and agents. You act in it only through your channel tools:
  say(text)          a message to everybody
  tell(to, text)     a message to one member
  send(to, path)     a file or folder from your own folder to a member (or "all")
  inbox()            what the channel said since you last looked
  who()              the members, and which of them have an agent
  run(to, command)   one shell command on the device of a member who gave you remote control; the result comes back as "[run name] exit N: output"
Your person's lines arrive as "[name] text". Messages of others arrive as "[group name] text" or "[private name] text". Answer your person
in your normal reply; use the tools to speak to the channel. Be brief.
`
}

// The help for whoever is asking.
HelpFor :: proc() -> string {
    return HelpAgent() if HelpInAgent() else HelpUser()
}

// The words that only a person at the keyboard has. Nothing of the agent side may contain them.
USER_ONLY_WORDS :: [?]string{"--subscribe_idle", "--unsubscribe_idle", "--subscribe_spawned", "--unsubscribe_spawned", "--remote", "--run ", "--headless", "--kick", "--ban", "--close_group", "--spawn", "--dismiss", "--group_msg", "--group ", "--trust", "--listen", "--agents", "--allow-remote-agent", "--agent-trust", "--agent-model", "--cmd", "--private", "--yes", "--no ", "--quit", "--send", "--to "}

@(test)
HelpSplitTest :: proc(t: ^testing.T) {
    user: string = HelpUser()
    for word in USER_ONLY_WORDS {
        testing.expectf(t, strings.contains(user, word), "the help of a person lacks %q", word)
    }
    // the agent's help names the tools and none of the commands of the keyboard
    agent: string = HelpAgent()
    for tool in ([?]string{"say(", "tell(", "send(", "inbox(", "who(", "run("}) {
        testing.expectf(t, strings.contains(agent, tool), "the help of an agent lacks %q", tool)
    }
    for word in USER_ONLY_WORDS {
        testing.expectf(t, !strings.contains(agent, word), "the help of an agent shows %q", word)
    }
    // and nothing else the agent reads: its tool descriptions, its prompt
    for word in USER_ONLY_WORDS {
        testing.expectf(t, !strings.contains(MCP_TOOLS, word), "an MCP tool description shows %q", word)
    }
    session: ^Session = new(Session)
    defer free(session)
    for mode in ([?]TrustMode{.ASK, .MEMBERS, .LISTED}) {
        session.config.trust = mode
        session.config.trusted = "bob"
        prompt_text: string = SessionTrustPrompt(session, "alice")
        for word in USER_ONLY_WORDS {
            testing.expectf(t, !strings.contains(prompt_text, word), "the trust paragraph shows %q", word)
        }
    }
}
