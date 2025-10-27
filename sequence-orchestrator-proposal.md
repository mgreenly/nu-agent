# Sequence Orchestrator

## Problem

When users request multi-step workflows (e.g., "Find the 5 biggest code smells and fix them"), the current orchestrator executes everything in a single context. This leads to:

- **Context bloat**: Each step adds to the conversation, making later steps slower and more expensive
- **Reduced quality**: By step 5, the agent is working with 50k+ tokens of history
- **Poor user visibility**: No clear view of the planned steps before execution begins
- **No course correction**: Can't review or adjust the plan before committing resources

## Solution

A **SequenceOrchestrator** that detects multi-step requests, plans the work, shows the plan for approval, then executes steps in fresh contexts.

## User Experience

```
User: "What are the 5 biggest code smells. Let's create a list and fix them."

Agent: I've detected this is a multi-step sequence. Let me plan the work...

Agent: Here's my execution plan:

□ Analyze codebase to identify 5 biggest code smells
□ Fix code smell 1: [description]
□ Fix code smell 2: [description]
□ Fix code smell 3: [description]
□ Fix code smell 4: [description]
□ Fix code smell 5: [description]
□ Summary of all fixes

Proceed? [Yes / No]

User: Yes

Agent: [Executes checklist, each fix in fresh context]
```

## Why This Matters

1. **Efficiency**: Fresh context for each step = faster, cheaper execution
2. **Transparency**: User sees the full plan before work begins
3. **Control**: User can abort and refine the request before resources are spent
4. **Scalability**: Enables complex workflows without context explosion
5. **Foundation**: Infrastructure for future automation (e.g., `/for-each` commands)

## High-Level Architecture

### Components

**SequenceOrchestrator**
- Detects when a request is multi-step vs single-task
- Delegates to sub-agents for analysis and planning
- Generates execution plan as a checklist
- Presents plan to user for approval
- Executes approved steps, spawning fresh agents as needed

**Sub-Agents (via existing orchestrator capabilities)**
- Detection: "Is this a sequence or single task?"
- Planning: "Break this into discrete, executable steps"
- Execution: "Complete this specific step" (fresh context per step)

### Phases

**Phase 1: Detection & Planning** (stays in current context)
- User makes request
- Sub-agent analyzes: sequence or not?
- If sequence: sub-agent creates execution plan
- Show checklist to user
- User approves or aborts (can iterate on request if aborting)

**Phase 2: Execution** (fresh contexts)
- For each step in approved plan
- Spawn fresh agent with self-contained prompt
- Track completion
- Update checklist
- Collect results

**Phase 3: Synthesis** (return to orchestrator context)
- Aggregate results from all steps
- Present summary to user

## Scope

### In Scope (Initial)
- Linear sequences (step 1 → step 2 → step 3)
- User approval before execution
- Fresh context per step
- Checklist progress tracking

### Out of Scope (Future)
- Parallel execution
- Conditional branching (if/else logic)
- Complex dependencies between steps
- Automatic detection (start with explicit trigger)

## Success Criteria

- User can see full execution plan before work begins
- Each step executes in fresh context (no context bloat)
- Checklist shows real-time progress
- User can abort before execution starts
- Failed steps don't break the entire sequence

## Open Questions

- How should step results be passed between agents? (if needed)
- What level of detail in the checklist?
- Should user be able to modify plan, or just approve/abort?
- Explicit trigger (`/sequence`) or automatic detection?
