# AI Agent Framework (local Ollama)

This document describes the AI agent framework in `app/services/agent/`. It is a Ruby/Rails
implementation of the **GAME** architecture (Goals, Actions, Memory, Environment). It runs
entirely on a **local Ollama** server: no cloud API, no API key, no per-token cost.

It is a port of the earlier OpenAI-based framework in `~/Desktop/projects/openai_app`. The usage
is the same, with fixes to how the loop talks to the model (see
[Differences from openai_app](#11-differences-from-openai_app)).

---

## Contents

1. [What an agent is](#1-what-an-agent-is)
2. [Quick start](#2-quick-start)
3. [Architecture](#3-architecture)
4. [The agent loop, step by step](#4-the-agent-loop-step-by-step)
5. [Components reference](#5-components-reference)
6. [Built-in tools](#6-built-in-tools)
7. [Example agents](#7-example-agents)
8. [Building your own agent](#8-building-your-own-agent)
9. [Ollama configuration](#9-ollama-configuration)
10. [Testing](#10-testing)
11. [Differences from openai_app](#11-differences-from-openai_app)
12. [Troubleshooting](#12-troubleshooting)
13. [Design rules](#13-design-rules)

---

## 1. What an agent is

A chatbot answers once. An **agent** is a language model placed inside a **loop**, with **tools**
it can use, working towards **goals**:

```
 task ──► build prompt ──► LLM decides ──► run the tool(s) ──► save results in memory
              ▲                 │                                       │
              │                 └── terminal tool called? ──► STOP      │
              └─────────────────────── next iteration ◄─────────────────┘
```

The model never runs code. It only replies "call tool X with arguments Y" (this API feature is
called **tool calling** or **function calling**). The framework runs the Ruby code for that tool and
sends the result back to the model on the next turn. The loop ends when the model calls a
**terminal tool** (normally `terminate`) or when `max_iterations` is reached.

---

## 2. Quick start

Requirements: the Ollama service running on `http://localhost:11434` with `gemma4:12b` pulled.

```bash
curl -s localhost:11434/api/version     # check Ollama is up
bin/rails console
```

```ruby
result = Agent::Examples::SimpleMathAgent.run(task: "what is 15 + 27?")
result[:final_output]   # => "15 + 27 = 42"

result = Agent::Examples::ReadmeAgent.run
puts result[:final_output]   # a README written from the project files
```

Each example returns:

```ruby
{
  status: "completed",
  conversation: [ ...memory items... ],   # full history, useful for debugging
  final_output: "..."                     # result of the last tool (normally terminate)
}
```

---

## 3. Architecture

### GAME

| Letter | Concept | Question it answers | Class |
|---|---|---|---|
| **G** | Goals | What should the agent achieve? | `Agent::Goal` |
| **A** | Actions | What is it allowed to do? | `Agent::Action`, `Agent::ActionRegistry` |
| **M** | Memory | What has happened so far? | `Agent::Memory` |
| **E** | Environment | How are actions executed? | `Agent::Environment` |

Supporting parts:

| Part | Responsibility | Class |
|---|---|---|
| Tool catalogue | Global list of every registered tool, indexed by tag | `Agent::ToolRegistry` |
| Agent language | Turns goals + memory + actions into a prompt; turns the reply into tool invocations | `Agent::Languages::FunctionCalling` |
| LLM client | Sends the prompt to the model | `Agent::LLMClient` → `OllamaChat` |
| Runner | Runs the loop | `Agent::Runner` |

### Files

```
app/services/
├── ollama_chat.rb                    # HTTP client for Ollama /api/chat (no gems)
└── agent/
    ├── goal.rb                       # G
    ├── action.rb                     # A: one executable tool
    ├── action_registry.rb            # A: the tools one agent may use
    ├── memory.rb                     # M
    ├── environment.rb                # E
    ├── prompt.rb                     # messages + tools sent to the LLM
    ├── tool_registry.rb              # global tool catalogue
    ├── llm_client.rb                 # model settings, delegates to OllamaChat
    ├── runner.rb                     # the agent loop ⭐ start reading here
    ├── languages/
    │   ├── base.rb                   # interface for prompt strategies
    │   └── function_calling.rb       # native tool calling in Ollama format
    ├── tools/
    │   ├── system_tools.rb           # terminate, ask_user, think
    │   ├── file_tools.rb             # read_project_file, list_project_files
    │   └── access_log_tools.rb       # access-log security analysis (per-run, see SECURITY_CHECKS.md)
    └── examples/
        ├── simple_math_agent.rb
        ├── readme_agent.rb
        └── code_analyzer_agent.rb

test/services/agent/
├── runner_test.rb                    # loop behaviour, with a fake LLM
└── file_tools_test.rb                # path and secret-file restrictions
```

Rails autoloads everything (one class per file, Zeitwerk naming). The only extra configuration is the
`LLM` acronym in `config/initializers/inflections.rb`, which maps `llm_client.rb` to `Agent::LLMClient`.

### How the pieces connect

```
                       ┌──────────────────────────── Agent::Runner ───────────────────────────┐
                       │                                                                      │
 Goals ───────────────►│  FunctionCalling.construct_prompt(goals, memory, actions)            │
 ActionRegistry ──────►│        │                                                             │
 Memory ◄─────────────►│        ▼                                                             │
                       │  LLMClient.call(prompt) ──► OllamaChat.chat ──► POST /api/chat ──────┼──► Ollama
                       │        │                                                             │
                       │        ▼                                                             │
                       │  FunctionCalling.parse_response ──► [ {tool:, args:}, ... ]          │
                       │        │                                                             │
                       │        ▼                                                             │
                       │  Environment.execute_action (for each invocation)                    │
                       │        │                                                             │
                       │        ▼                                                             │
                       │  update_memory ──► terminal? stop : loop                             │
                       └──────────────────────────────────────────────────────────────────────┘
```

---

## 4. The agent loop, step by step

`Agent::Runner#run(user_input, memory: nil, max_iterations: 50)`:

1. **Start**: create a `Memory` (or continue the one passed in) and add the task as a `user` item.
2. **Build the prompt**: `FunctionCalling#construct_prompt` creates:
   - one `system` message with all goals, sorted by priority;
   - one message per memory item;
   - the `tools` list, built from the agent's `ActionRegistry`.
3. **Ask the model**: `LLMClient#call` sends it to Ollama and returns the assistant message
   `{ content:, tool_calls:, thinking: }`.
4. **Parse**: `FunctionCalling#parse_response` returns **every** tool call as `{ tool:, args: }`.
   If the model replied with plain text and no tool call, that text is treated as the final answer
   (a `terminate` invocation with the text as `message`).
5. **Execute**: each invocation runs through `Environment#execute_action`.
   - Unknown tool name → an error result listing the available tools (the model can retry).
   - Exception in the tool → an error result with the exception message (the model can recover).
6. **Remember**: one `assistant` item (the reply, including its tool calls), then one
   `environment` item per executed tool.
7. **Stop or repeat**: stop if a terminal action ran successfully; otherwise go to step 2. A terminal
   call that fails (bad arguments, a validation error) does not stop the loop, so the model can fix it.
   The loop also stops after `max_iterations` turns.

### Worked example

A typical run of `SimpleMathAgent.run(task: "what is 15 + 27?")` with gemma4:12b:

| Turn | Model does | Framework does |
|---|---|---|
| 1 | calls `sum_two_numbers(num1: 15, num2: 27)` | runs the lambda → `42.0`, stores it as a tool result |
| 2 | sees the result, calls `terminate(message: "15 + 27 = 42")` | runs `terminate`, which is terminal → loop ends |

`memory.final_output` → `"15 + 27 = 42"`.

### What the model actually receives on turn 2

```ruby
[
  { role: "system",    content: "Calculate Sum:\n-------------------\nCalculate the sum ... call terminate with the result\n-------------------\n" },
  { role: "user",      content: "what is 15 + 27?" },
  { role: "assistant", content: "", tool_calls: [ { function: { name: "sum_two_numbers", arguments: { num1: 15, num2: 27 } } } ] },
  { role: "tool",      tool_name: "sum_two_numbers", content: "{\"tool_executed\":true,\"result\":42.0}" }
]
```

The model has no memory between API calls, so **the full history is resent on every turn**. Long
runs therefore use more context each turn (see [Context size](#context-size)).

---

## 5. Components reference

### `Agent::Goal`

```ruby
Agent::Goal.new(priority: 1, name: "Research", description: "Read the models and controllers")
```

Goals are written into the system message, sorted by `priority` (lower number first). Write them
as instructions, and make the last one say **when to call the terminal tool and what to put in it**.

### `Agent::ToolRegistry`: the global catalogue

```ruby
Agent::ToolRegistry.register(name, function, description:, parameters:, terminal: false, tags: [])
Agent::ToolRegistry.get("terminate")                 # => metadata hash or nil
Agent::ToolRegistry.get_by_tags([ "math", "system" ]) # => tools having ANY of the tags
Agent::ToolRegistry.clear                            # remove everything (used in tests)
```

- `function`: a lambda (or anything responding to `call`) taking **keyword arguments**.
- `description`: what the model reads to choose the tool. Truncated to 1024 characters.
- `parameters`: a JSON Schema object. If omitted, it is generated from the lambda's keyword
  arguments with every type set to `"string"`. Writing it by hand gives the model better information.
- `terminal: true`: a successful call of this tool ends the loop (a failed call lets the model retry).
- `tags`: used to pick tools for an agent. Re-registering a name overwrites it.

The registry is class-level state, shared by the whole process. In development it is reset on code
reload, so call `register_all` again before running an agent (the examples already do this).

### `Agent::Action` and `Agent::ActionRegistry`: tools for one agent

`ToolRegistry` holds every tool that exists. `ActionRegistry` holds the subset one agent is allowed
to use, which is how you restrict an agent (for example, a read-only agent).

```ruby
registry = Agent::ActionRegistry.from_tags([ "file_operations", "system" ])
registry.get_action("read_project_file")  # => Agent::Action
registry.get_actions                      # => [Agent::Action, ...]
```

Or by hand:

```ruby
registry = Agent::ActionRegistry.new
registry.register(Agent::Action.new(name: "x", function: ->() { 1 }, description: "...", parameters: {}, terminal: false))
```

### `Agent::Memory`

An ordered list of hashes:

| `type` | Keys | Sent to the model as |
|---|---|---|
| `user` | `content` | `role: "user"` |
| `assistant` | `content`, `tool_calls` | `role: "assistant"` with `tool_calls` |
| `environment` | `content` (result JSON), `tool_name` | `role: "tool"` with `tool_name` |
| `system` | `content` | `role: "system"` |

```ruby
memory.get_memories               # all items
memory.get_memories(limit: 10)    # the 10 most recent
memory.copy_without_system_memories
memory.final_output               # result (or error) of the last executed tool
```

Pass a memory to `run` to continue a conversation: `agent.run("now do Y", memory: memory)`.

### `Agent::Environment`

Executes an action with symbolized keyword arguments and wraps the outcome:

```ruby
{ tool_executed: true,  result: 42.0 }
{ tool_executed: false, error: "ArgumentError: missing keyword: :city" }
```

Errors are logged with a short backtrace in the Rails log and never raised, so a bad tool call does
not crash the agent. Subclass it to add checks, auditing or rate limits:

```ruby
class ConfirmingEnvironment < Agent::Environment
  def execute_action(action, args)
    return { tool_executed: false, error: "Not allowed" } if action.name.start_with?("delete_")
    super
  end
end

Agent::Runner.new(environment: ConfirmingEnvironment.new, ...)
```

### `Agent::Languages::FunctionCalling`

Formats goals, memory and actions into Ollama's native tool-calling format, and parses replies.
Tool arguments are accepted both as an object (Ollama) and as a JSON string (OpenAI-style).

`Agent::Languages::Base` defines the interface (`construct_prompt`, `parse_response`). Write another
subclass to support a different prompting style, for example tools described in plain text with a
JSON reply format for models without native tool calling. `parse_response` must return an array of
`{ tool:, args: }` hashes.

### `Agent::LLMClient`

```ruby
Agent::LLMClient.new(
  model: "gemma4:12b",    # any model from `ollama list` with the "tools" capability
  num_ctx: 262_144,       # context window in tokens
  temperature: nil,       # nil = model default
  think: nil,             # true/false = model's built-in reasoning on/off; nil = model default
  ollama_chat: nil        # inject a custom OllamaChat (e.g. another URL)
)
```

### `OllamaChat`

A small `Net::HTTP` client for `POST /api/chat` with `stream: false`.

```ruby
OllamaChat.new(base_url: "http://localhost:11434", read_timeout: 600)
  .chat(messages: [...], tools: [...], model: "gemma4:12b", num_ctx: 262_144)
# => { role: "assistant", content: "...", tool_calls: [...] }
```

- The URL comes from `ENV["OLLAMA_URL"]` when it is set.
- Raises `OllamaChat::Error` when the API returns an error or Ollama is not reachable.
- The read timeout is 10 minutes, because the first call may need to load the model into GPU memory.

### `Agent::Runner`

```ruby
agent = Agent::Runner.new(
  goals: goals,
  agent_language: Agent::Languages::FunctionCalling.new,
  action_registry: registry,
  llm_client: Agent::LLMClient.new,
  environment: Agent::Environment.new   # optional
)
memory = agent.run("task", max_iterations: 20)
```

Every iteration is logged to the Rails log with the `[Agent]` prefix: the decision, each tool call
and its (truncated) result. Run `tail -f log/development.log` to watch an agent work.

---

## 6. Built-in tools

### `Agent::Tools::SystemTools`

| Tool | Tags | Purpose |
|---|---|---|
| `terminate(message:)` | `system`, `control`, `terminal` | **Terminal.** Ends the run; `message` becomes `final_output`. |
| `ask_user(question:)` | `system`, `interaction`, `user` | In an interactive console, prints the question and waits for your answer. Elsewhere (jobs, `rails runner`) it tells the model nobody is available and to assume something reasonable. |
| `think(thoughts:)` | `debug`, `logging` | Writes reasoning to the log. **Not** in the `system` tag; include the `debug` tag to enable it. |

Every agent needs a terminal tool. Select the `system` tag unless the agent has its own.

### `Agent::Tools::FileTools`

| Tool | Tags | Purpose |
|---|---|---|
| `read_project_file(name:)` | `file_operations`, `read` | Reads a file by path relative to the project root. Truncated at 100 KB. |
| `list_project_files(pattern: "**/*")` | `file_operations`, `list` | Lists files matching a glob, relative to the project root. At most 500 paths. |

Safety rules (in `FileTools.safe_path` and the constants at the top of the file):

- Paths outside `Rails.root` are refused (`../`, absolute paths).
- Secret-looking files are refused: `*.key` (including `master.key`), `.env*`, anything with
  `credentials` in the path, `.kamal/secrets`.
- Listing skips `.git`, `tmp`, `log`, `storage`, `node_modules`, `vendor`, `public/assets` and
  `app/assets/builds`.

Refusals are raised as `ArgumentError`, which the Environment turns into an error result for the model.

### `Agent::Tools::AccessLogTools`

Tools for checking one web-server access log for attacks: `log_overview`, `read_log_lines`, `search_log`,
`ip_activity` and the terminal `submit_security_report`. They are **not** in the global `ToolRegistry`:
`AccessLogTools.action_registry(scanner, language:)` builds an `ActionRegistry` bound to the lines one check
has already read, so the model never picks a file path and parallel checks can't see each other's data.
See [SECURITY_CHECKS.md](SECURITY_CHECKS.md).

---

## 7. Example agents

| Agent | Tools (tags) | Max iterations | Demonstrates |
|---|---|---|---|
| `SimpleMathAgent.run(task:)` | `math`, `system` | 10 | The smallest complete agent: one custom tool and `terminate` |
| `ReadmeAgent.run(user_input)` | `file_operations`, `system` | 30 | Multi-step research: lists and reads files, then writes a README |
| `CodeAnalyzerAgent.run(task:)` | `code_analysis`, `file_operations` | 30 | Several custom tools and a **custom terminal tool** (`complete_analysis`) instead of `terminate` |

`CodeAnalyzerAgent` registers:

- `search_code(pattern:, file_pattern:)`: regex search with line numbers;
- `analyze_models`: associations, validations and scopes from `app/models`;
- `check_dependencies`: gems from the `Gemfile` and the Ruby version;
- `complete_analysis(summary:)`: terminal.

Measured on this machine (RTX 5070, gemma4:12b, 256k context):

| Run | Turns | Time |
|---|---|---|
| SimpleMathAgent, two sums | 3 | 9 s |
| ReadmeAgent on this project | 10 (1 list + 8 reads + answer) | 57 s |

---

## 8. Building your own agent

### Step 1: write tools

Put related tools in one class under `app/services/agent/tools/`, following the existing pattern:

```ruby
# app/services/agent/tools/weather_tools.rb
module Agent
  module Tools
    class WeatherTools
      def self.register_all
        register_get_weather
      end

      def self.register_get_weather
        ToolRegistry.register(
          "get_weather",
          lambda do |city:|
            WeatherService.current(city)   # your code; return a String, Hash or Array
          end,
          description: "Get the current weather for one city. Call it once per city.",
          parameters: {
            type: "object",
            properties: {
              city: { type: "string", description: "City name, e.g. Tbilisi" }
            },
            required: [ "city" ]
          },
          tags: [ "weather", "api" ]
        )
      end
    end
  end
end
```

Tool checklist:

- [ ] The name and description explain **when** to use the tool, not only what it does.
- [ ] Every parameter has a type and a description; required ones are listed in `required`.
- [ ] The tool returns JSON-friendly data (String, Number, Hash, Array). It is sent to the model with `to_json`.
- [ ] Large outputs are truncated or limited (they fill the context).
- [ ] Invalid input raises an exception with a helpful message (the model will see it).
- [ ] Tools that change data are tagged `mutation` and are protected before being given to an agent.

### Step 2: define the agent

```ruby
# app/services/agent/examples/weather_agent.rb
module Agent
  module Examples
    class WeatherAgent
      def self.run(task)
        Tools::WeatherTools.register_all
        Tools::SystemTools.register_all

        goals = [
          Goal.new(priority: 1, name: "Collect",
                   description: "Get the weather for every city the user mentions"),
          Goal.new(priority: 2, name: "Report",
                   description: "Call terminate with a short report covering every city")
        ]

        agent = Runner.new(
          goals: goals,
          agent_language: Languages::FunctionCalling.new,
          action_registry: ActionRegistry.from_tags([ "weather", "system" ]),
          llm_client: LLMClient.new
        )

        memory = agent.run(task, max_iterations: 10)
        { status: "completed", conversation: memory.get_memories, final_output: memory.final_output }
      end
    end
  end
end
```

### Step 3: run it

```ruby
Agent::Examples::WeatherAgent.run("Weather in Tbilisi and Batumi?")[:final_output]
```

### Using an agent from the web app

Agent runs take seconds to minutes, so do not run them inside a request. Run them in a background
job (Solid Queue is already configured) and store or broadcast the result:

```ruby
class AgentJob < ApplicationJob
  def perform(task)
    result = Agent::Examples::ReadmeAgent.run(task)
    Rails.logger.info result[:final_output]
    # save to a model and broadcast with Turbo Streams, as openai_app does with AiMessaging
  end
end
```

`ask_user` cannot reach a person from a job, so it replies that nobody is available.

---

## 9. Ollama configuration

| Setting | Value | Where |
|---|---|---|
| URL | `http://localhost:11434` | `OllamaChat::DEFAULT_URL`, override with `OLLAMA_URL` |
| Model | `gemma4:12b` | `OllamaChat::DEFAULT_MODEL`, override with `LLMClient.new(model:)` |
| Context | 262,144 tokens | `OllamaChat::DEFAULT_NUM_CTX`, override with `LLMClient.new(num_ctx:)` |
| Endpoint | native `/api/chat` | the OpenAI-compatible `/v1` endpoint cannot set the context per request |

### Context size

The Ollama server default is only 4,096 tokens. That is too small for agents, because the whole
history is resent on every turn and Ollama drops the oldest part of the prompt (possibly the goals)
when it overflows. The framework therefore sends `num_ctx` with every request.

Measured with gemma4:12b on this machine (12 GB GPU memory), all fully on the GPU:

| `num_ctx` | GPU memory | Generation speed |
|---|---|---|
| 65,536 | ~11.0 GB | ~170 tokens/s |
| 131,072 | ~11.5 GB | ~74 tokens/s |
| 262,144 (default) | ~11.7 GB | ~41 tokens/s |

Use a smaller `num_ctx` when speed matters more than long tasks.

### Models

| Model | Tool calling | Notes |
|---|---|---|
| `gemma4:12b` | ✅ tested, including several calls per turn | Default. Fits on the GPU. |
| `qwen3.8:latest` (27B) | ✅ tested | Does not fit in GPU memory: runs mostly on the CPU at 9–12 tokens/s, needs ~19 GB of RAM at a 32k context, ~77 s to load. Keep `num_ctx` ≤ 32,768. |

Check a model's capabilities with `ollama show <model>`; it must list `tools`.

---

## 10. Testing

```bash
bin/rails test test/services
```

The tests use a `FakeLLMClient` that returns scripted replies, so they run in milliseconds and do
not need Ollama. They cover:

- several tool calls in one turn are all executed, then `terminate` stops the loop;
- tool results are sent back as `role: "tool"` messages after the assistant's tool calls;
- arguments given as a JSON string are parsed;
- a plain-text reply becomes the final answer;
- unknown tools and tool exceptions are reported to the model, and the run recovers;
- `max_iterations` stops a model that never terminates;
- FileTools refuse paths outside the project and secret files.

To test a new agent's logic, script the model's replies with the same fake client
(`test/services/agent/runner_test.rb`). To check real model behaviour, run the agent in the console.

---

## 11. Differences from openai_app

| Area | openai_app | khisfari |
|---|---|---|
| Model provider | OpenAI API (`openai` gem) | Local Ollama, no gem (`OllamaChat`, `Net::HTTP`) |
| Tool calls per turn | only the first one ran | all of them run |
| Failed terminal call | ended the loop | the loop continues, so the model can correct its arguments |
| Tool results | sent back as `assistant` messages | sent back as `role: "tool"` messages with `tool_name` |
| Unknown tool | loop stopped | error returned to the model, which can retry |
| Context size | not set | `num_ctx: 262144` on every request |
| `temperature` | accepted but never sent | sent when set |
| `Memory#get_memories(limit:)` | returned the oldest items | returns the most recent items |
| Final result | `extract_final_output` copied into each example | `Memory#final_output` |
| Building a registry | loop copied into each example | `ActionRegistry.from_tags` |
| `think` tool | in the `system` tag | in the `debug` tag (opt-in); gemma wasted turns on it |
| `ask_user` | placeholder only | really asks in an interactive console |
| File tools | any path; listing only `*.rb` in the current directory | restricted to the project; secrets blocked; any glob |
| Result format | included a timestamp and full traceback | compact; the backtrace goes to the log only |
| File layout | several classes in `core.rb`, loaded with `require_relative` | one class per file, autoloaded |
| Database tools | `DatabaseTools`, `MessageAnalyzerAgent` | not ported (khisfari has no models yet) |

---

## 12. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `OllamaChat::Error: Cannot reach Ollama at http://localhost:11434` | Service not running | `systemctl status ollama`; start it with `sudo systemctl start ollama` |
| `Ollama API error: model "..." not found` | Model not pulled | `ollama list`, then `ollama pull <model>` |
| First call is slow (tens of seconds) | The model is loading into GPU memory | Normal. It stays loaded for 5 minutes after the last call. |
| `... does not support tools` | The model has no tool-calling capability | Use a model that lists `tools` in `ollama show` |
| `NameError: uninitialized constant Agent::LlmClient` | Inflection missing | Keep `inflect.acronym "LLM"` in `config/initializers/inflections.rb` |
| Agent stops after `max_iterations` without an answer | The goals do not say when to finish | Make the last goal say "call terminate with ..."; check the terminal tool is in the registry |
| Error `Unknown tool 'terminate'` in memory | The model answered in plain text, but the agent has no `terminate` (e.g. `CodeAnalyzerAgent`) | Expected: the model then calls the agent's own terminal tool |
| A tool is missing from the agent | Not registered, or its tags were not selected | Call its `register_all`; check `ToolRegistry.get_by_tags([...]).map { _1[:name] }` |
| Answers get worse during long runs | Too much history, or tool outputs are too large | Truncate tool output; keep `num_ctx` high; lower `max_iterations` |

---

## 13. Design rules

1. **Descriptions are prompts.** The model chooses tools from their names and descriptions only.
2. **Always have a terminal tool**, and say in the goals when to call it.
3. **Always limit iterations.** Agents can loop.
4. **Return errors, don't crash.** An error message lets the model fix its own mistake.
5. **Give each agent the fewest tools it needs.** It makes better choices and is safer.
6. **Keep tool output small.** Every result is resent on every later turn.
7. **Guard powerful tools.** Anything that writes, deletes, sends or spends needs checks in the tool
   or in a custom `Environment` before an agent gets it.
8. **Run agents in background jobs**, not inside web requests.
