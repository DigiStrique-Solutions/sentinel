# Performance Optimization

## Model Selection Strategy

Most AI coding assistants offer tiered models. Choose the right tier for the task:

**Small / Fast models** (e.g., Claude Haiku, GPT-4o mini, Gemini Flash, Grok mini):
- Lightweight agents with frequent invocation
- Pair programming and code generation
- Worker agents in multi-agent systems
- Tasks where latency matters more than depth

**Mid-tier models** (e.g., Claude Sonnet, GPT-4o, Gemini Pro, Grok):
- Main development work
- Orchestrating multi-agent workflows
- Complex coding tasks
- Best balance of speed and capability

**Frontier models** (e.g., Claude Opus, GPT-o3, Gemini Ultra, Grok 3):
- Complex architectural decisions
- Maximum reasoning requirements
- Research and analysis tasks
- Tasks requiring deep multi-step reasoning

> **Tip:** Default to mid-tier for most work. Upgrade to frontier when you need deeper reasoning. Downgrade to small for high-volume, low-complexity agent work.

## Context Window Management

Avoid last 20% of context window for:
- Large-scale refactoring
- Feature implementation spanning multiple files
- Debugging complex interactions

Lower context sensitivity tasks:
- Single-file edits
- Independent utility creation
- Documentation updates
- Simple bug fixes

## Deep Reasoning

For complex tasks requiring deep reasoning:
1. Enable extended thinking / reasoning mode if your model supports it
2. Use plan mode or structured planning for multi-step approaches
3. Use multiple critique rounds for thorough analysis
4. Use split role sub-agents for diverse perspectives

## Build Troubleshooting

If build fails:
1. Use **build-resolver** agent
2. Analyze error messages
3. Fix incrementally
4. Verify after each fix
