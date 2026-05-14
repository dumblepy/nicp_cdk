# AI Agent Instructions

This is an Internet Computer (ICP) project built with icp-cli.

Documentation: https://cli.internetcomputer.org/llms.txt

## Skills

Tested implementation patterns for ICP development are available as agent skills.
Fetch the skills index and remember each skill's name and description:
https://skills.internetcomputer.org/.well-known/skills/index.json

When a task matches a skill's description, use it if already loaded in your
context. Otherwise, fetch its content on-demand from the registry:
https://skills.internetcomputer.org/.well-known/skills/{name}/{file}

Skills contain correct dependency versions, configuration formats, and common pitfalls that prevent build failures.
Always prefer skill guidance over general documentation when both cover the same topic.
