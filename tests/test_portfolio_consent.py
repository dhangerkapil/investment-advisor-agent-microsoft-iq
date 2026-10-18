"""Fabric IQ consent: the portfolio tool shows the user's consent link instead of hiding it behind "unavailable"."""

import json

import pytest
from agent_framework.exceptions import ToolExecutionException
from mcp.shared.exceptions import McpError
from mcp.types import ErrorData

from workplace_agent import portfolio
from workplace_agent.advisor import FaultSwitch, InMemoryItemStore

LINK = "https://logic-apis-eastus2.consent.azure-apim.net/login?data=abc"


def toolbox_error(code: str, message: str) -> ToolExecutionException:
    details = {"errors": [{"name": "fabric_portfolio", "type": "mcp", "error": {"code": code, "message": message}}]}
    return ToolExecutionException("Failed to enter context manager.", McpError(ErrorData(
        code=-32006,
        message="tools/list failed for 1 tool source(s), succeeded for 0 tool source(s) " + json.dumps(details),
    )))


def text_of(result) -> str:
    if isinstance(result, str):
        return result
    if isinstance(result, list):
        return "".join(getattr(item, "text", "") or "" for item in result)
    return str(result)


def faults() -> FaultSwitch:
    store = InMemoryItemStore()

    async def factory():
        return store

    return FaultSwitch(factory)


def test_consent_link_is_found_only_for_consent_errors():
    assert portfolio.fabric_consent_link(toolbox_error("CONSENT_REQUIRED", LINK)) == LINK
    assert portfolio.fabric_consent_link(toolbox_error("CapacityNotActive", "The capacity is paused")) is None
    assert portfolio.fabric_consent_link(RuntimeError("boom")) is None
    assert portfolio.fabric_consent_link(toolbox_error("CONSENT_REQUIRED", "not a link")) is None


@pytest.mark.parametrize(("error", "status"), [
    (toolbox_error("CONSENT_REQUIRED", LINK), "FABRIC_CONSENT_REQUIRED"),
    (toolbox_error("CapacityNotActive", "The capacity is paused"), "PORTFOLIO_DATA_UNAVAILABLE"),
])
async def test_portfolio_tool_shows_consent_link_or_degrades(monkeypatch, error, status):
    class FailingToolbox:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            raise error

        async def __aexit__(self, *exc):
            return False

    monkeypatch.delenv("DEMO_FAULTS", raising=False)
    monkeypatch.setattr(portfolio, "FoundryToolbox", FailingToolbox)
    tool = portfolio.portfolio_tool(object(), "https://example.services.ai.azure.com/toolboxes/fabric/mcp", faults())
    result = json.loads(text_of(await tool.invoke(arguments={"question": "Michael Scott: NVDA weight"})))
    assert result["status"] == status
    if status == "FABRIC_CONSENT_REQUIRED":
        assert result["consent_link"] == LINK and "Markdown link" in result["instruction"]
    else:
        assert "consent_link" not in result
