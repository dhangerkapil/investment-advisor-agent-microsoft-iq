# Contributing

Contributions are welcome: bug fixes, clearer docs, new story scenarios, better evaluations.

1. Open an issue first for anything larger than a small fix.
2. Keep the story fictional: no real people, clients, tenants or data.
3. Run the checks before a pull request:

   ```powershell
   uv sync --frozen --extra dev --extra ui; uv run python -m pytest -q
   .\scripts\Test-StoryDates.ps1
   npm --prefix ui ci; npm --prefix ui test
   terraform fmt -check -recursive terraform
   ```

   Without local Python packages, `.\scripts\Test-AgentInAcr.ps1 -Tests tests` runs the tests in Azure Container
   Registry.
4. Agent behavior changes go in `.agent_configs/baseline` (instructions, skills, model). Show the evaluation
   before and after ([docs/QUALITY-LOOP.md](docs/QUALITY-LOOP.md)) in the pull request.
