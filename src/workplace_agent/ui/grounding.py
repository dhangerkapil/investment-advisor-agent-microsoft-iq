"""Ground cited Microsoft 365 items in what Work IQ actually returned, and repair IDs the model mis-copied.

Language models occasionally drop or change a character when they copy a 150-character Outlook ID into the
references block. Every real ID is in the conversation's tool output, so a cited ID that is not there but is clearly
closest to one ID that is, gets that ID. Use this only after Microsoft Graph can't find the cited item, with the
whole conversation's tool output: sibling Outlook IDs differ by a single character, so repairing a valid ID against
partial evidence could pick the wrong item.
"""

from __future__ import annotations

import json
import re
from collections.abc import Iterable, Sequence
from difflib import SequenceMatcher
from urllib.parse import unquote

from .entities import parse_entity_url
from .models import Reference

OUTLOOK_ID = re.compile(r"A[AQ]Mk[A-Za-z0-9\-_+=%]{16,700}")
CHAT_MESSAGE = re.compile(r"/chats/(19(?::|%3[Aa])[^/\s\"'\\]{1,300})/messages/(\d{1,32})")
DRIVE_ITEM = re.compile(r"/drives/([A-Za-z0-9!\-_]{1,256})/items/([A-Za-z0-9!\-_]{1,256})")
ESCAPES = {"\\u003d": "=", "\\u003D": "=", "\\u002b": "+", "\\u002B": "+"}
MIN_SIMILARITY = 0.97
# Sibling Outlook IDs can differ by a single character, so require a clear winner rather than a unique match.
MIN_MARGIN = 0.002
MAX_SCAN = 2_000_000


def output_text(output: object) -> str:
    text = output if isinstance(output, str) else json.dumps(output)
    text = text[:MAX_SCAN]
    for escape, character in ESCAPES.items():
        text = text.replace(escape, character)
    return text


def closest(value: str, candidates: Iterable[str]) -> str | None:
    """The candidate clearly closest to ``value``; None when none is close or two are equally close."""
    scored = sorted(
        ((SequenceMatcher(None, value, candidate, autojunk=False).ratio(), candidate) for candidate in set(candidates)),
        reverse=True,
    )
    if not scored or scored[0][0] < MIN_SIMILARITY:
        return None
    if len(scored) > 1 and scored[0][0] - scored[1][0] < MIN_MARGIN:
        return None
    return scored[0][1]


def graph_id(value: str) -> str:
    """Outlook item IDs in OWA links use '+' where Microsoft Graph IDs use '_'."""
    return unquote(value).replace("+", "_")


class Evidence:
    """Item IDs that appeared in tool output (Work IQ retrieve hits, fetch results, inspect_document evidence)."""

    def __init__(self) -> None:
        self.outlook_ids: set[str] = set()
        self.chat_messages: set[tuple[str, str]] = set()
        self.drive_items: set[tuple[str, str]] = set()

    @classmethod
    def from_items(cls, items: Sequence[object]) -> Evidence:
        evidence = cls()
        for item in items:
            if isinstance(item, dict) and item.get("type") == "function_call_output":
                evidence.record(item.get("output"))
        return evidence

    def record(self, output: object) -> None:
        text = output_text(output)
        self.outlook_ids.update(graph_id(match.group(0)) for match in OUTLOOK_ID.finditer(text))
        self.chat_messages.update((unquote(chat), message) for chat, message in CHAT_MESSAGE.findall(text))
        self.drive_items.update(DRIVE_ITEM.findall(text))

    def repair(self, reference: Reference) -> Reference:
        """The reference with its item IDs matched to the tool output; unchanged when nothing matches."""
        if reference.entity_url:
            entity = parse_entity_url(reference.entity_url)
            if entity.kind in ("email", "event"):
                prefix = "/me/messages/" if entity.kind == "email" else "/me/events/"
                identifier = graph_id(entity.ids["id"])
                match = identifier if identifier in self.outlook_ids else closest(identifier, self.outlook_ids)
                if match is None or f"{prefix}{match}" == reference.entity_url:
                    return reference
                return reference.model_copy(update={"entity_url": f"{prefix}{match}"})
            if entity.kind == "chat":
                chat, message = entity.ids["chat"], entity.ids["message"]
                if (chat, message) in self.chat_messages:
                    return reference
                chats = {found for found, found_message in self.chat_messages if found_message == message}
                if len(chats) != 1:
                    return reference
                return reference.model_copy(update={"entity_url": f"/chats/{chats.pop()}/messages/{message}"})
        if reference.kind == "file" and reference.drive_id and reference.item_id:
            if (reference.drive_id, reference.item_id) in self.drive_items:
                return reference
            item = closest(reference.item_id, (found for _, found in self.drive_items))
            drives = {drive for drive, found in self.drive_items if found == item}
            if item is None or len(drives) != 1:
                return reference
            drive = drives.pop()
            return reference.model_copy(update={
                "drive_id": drive, "item_id": item,
                "entity_url": f"/drives/{drive}/items/{item}" if reference.entity_url else None,
            })
        return reference
