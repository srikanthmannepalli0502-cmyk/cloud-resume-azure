import json
from unittest.mock import MagicMock

import azure.functions as func
import pytest
from azure.cosmos.exceptions import CosmosResourceExistsError, CosmosResourceNotFoundError

import function_app


def make_request():
    return func.HttpRequest(method="POST", url="/api/visitors", body=b"")


def call_visitors(req):
    handler = function_app.visitors
    # Depending on the azure-functions version, the decorator returns either the
    # function itself or a FunctionBuilder wrapping it.
    if hasattr(handler, "build"):
        handler = handler.build().get_user_function()
    return handler(req)


def test_increment_existing_counter():
    container = MagicMock()
    container.patch_item.return_value = {"id": "visitors", "count": 42}

    assert function_app.increment_count(container) == 42
    container.patch_item.assert_called_once_with(
        item="visitors",
        partition_key="visitors",
        patch_operations=[{"op": "incr", "path": "/count", "value": 1}],
    )
    container.create_item.assert_not_called()


def test_first_visit_creates_counter():
    container = MagicMock()
    container.patch_item.side_effect = CosmosResourceNotFoundError()
    container.create_item.return_value = {"id": "visitors", "count": 1}

    assert function_app.increment_count(container) == 1
    container.create_item.assert_called_once_with({"id": "visitors", "count": 1})


def test_concurrent_first_visit_falls_back_to_patch():
    container = MagicMock()
    container.patch_item.side_effect = [CosmosResourceNotFoundError(), {"id": "visitors", "count": 2}]
    container.create_item.side_effect = CosmosResourceExistsError()

    assert function_app.increment_count(container) == 2
    assert container.patch_item.call_count == 2


def test_http_returns_count(monkeypatch):
    container = MagicMock()
    container.patch_item.return_value = {"id": "visitors", "count": 7}
    monkeypatch.setattr(function_app, "get_container", lambda: container)

    resp = call_visitors(make_request())

    assert resp.status_code == 200
    assert resp.mimetype == "application/json"
    assert json.loads(resp.get_body()) == {"count": 7}


def test_http_returns_500_when_database_fails(monkeypatch):
    def broken():
        raise RuntimeError("cosmos is down")

    monkeypatch.setattr(function_app, "get_container", broken)

    resp = call_visitors(make_request())

    assert resp.status_code == 500
    assert "error" in json.loads(resp.get_body())
