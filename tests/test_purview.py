"""Microsoft Purview on the agent's turns (ADVISOR_PURVIEW): the advisor's object ID for Purview, the gate that answers
a blocked prompt with the policy message, and the layers' place in the agent (test_app.py)."""

from __future__ import annotations

import pytest
from agent_framework import Message, MiddlewareTermination, ResponseStream

from workplace_agent.purview import BLOCKED_PROMPT, AdvisorUserStamp, PurviewGate, purview_middleware


class Context:
    def __init__(self) -> None:
        self.messages = [Message(role="user", contents=["hello"])]


@pytest.mark.parametrize("user, stamped", [("44444444-4444-4444-8444-444444444444", True), ("opaque-key", False)])
async def test_purview_gets_the_advisors_object_id_only_when_the_platform_gives_one(user: str, stamped: bool):
    from azure.ai.agentserver.core import FoundryAgentRequestContext, reset_request_context, set_request_context

    token = set_request_context(FoundryAgentRequestContext(user_id=user))
    try:
        context = Context()
        calls = []

        async def call_next():
            calls.append(1)

        await AdvisorUserStamp().process(context, call_next)
    finally:
        reset_request_context(token)
    assert calls == [1]
    assert (context.messages[0].additional_properties.get("user_id") == user) is stamped


def test_purview_is_off_unless_turned_on(monkeypatch: pytest.MonkeyPatch):
    assert purview_middleware(object(), enabled=False) == []
    monkeypatch.setenv("AZURE_TENANT_ID", "11111111-1111-4111-8111-111111111111")
    middleware = purview_middleware(lambda: "token", enabled=True)
    assert [type(m).__name__ for m in middleware] == ["AdvisorUserStamp", "PurviewGate"]
    assert type(middleware[1].inner).__name__ == "PurviewPolicyMiddleware"


class Run:
    def __init__(self, stream: bool) -> None:
        self.messages = [Message(role="user", contents=["My client's SSN is 524-77-3612."])]
        self.stream = stream
        self.result = None


class Policy:
    """Stands in for Purview's middleware: blocks before the run, terminates after it, or lets it through."""

    def __init__(self, mode: str) -> None:
        self.mode = mode

    async def process(self, context, call_next):
        if self.mode == "block":
            raise MiddlewareTermination
        await call_next()
        if self.mode == "terminate-later":
            raise MiddlewareTermination


@pytest.mark.parametrize("stream", [True, False])
async def test_a_prompt_purview_blocks_gets_the_policy_message_and_the_agent_never_runs(stream: bool):
    context, ran = Run(stream), []

    async def call_next():
        ran.append(1)

    await PurviewGate(Policy("block")).process(context, call_next)
    assert ran == []
    if stream:
        assert isinstance(context.result, ResponseStream)
        texts = [update.text async for update in context.result]
        assert "".join(texts) == BLOCKED_PROMPT
        final = await context.result.get_final_response()
    else:
        final = context.result
    assert [m.role for m in final.messages] == ["assistant"] and final.text == BLOCKED_PROMPT


async def test_the_purview_gate_passes_other_runs_and_later_terminations_through():
    context, ran = Run(True), []

    async def call_next():
        ran.append(1)

    await PurviewGate(Policy("allow")).process(context, call_next)
    assert ran == [1] and context.result is None
    with pytest.raises(MiddlewareTermination):
        await PurviewGate(Policy("terminate-later")).process(Run(True), call_next)
