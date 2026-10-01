import json
import logging
import os

import azure.functions as func
from azure.cosmos import CosmosClient
from azure.cosmos.exceptions import CosmosResourceExistsError, CosmosResourceNotFoundError
from azure.identity import DefaultAzureCredential

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

COUNTER_ID = "visitors"
INCREMENT = [{"op": "incr", "path": "/count", "value": 1}]

_container = None


def get_container():
    """Return a cached Cosmos DB container client.

    Authenticates with the Function App's managed identity in Azure and with
    your `az login` session locally, so no keys or connection strings are needed.
    """
    global _container
    if _container is None:
        client = CosmosClient(os.environ["COSMOS_ENDPOINT"], credential=DefaultAzureCredential())
        _container = client.get_database_client(os.environ["COSMOS_DATABASE"]).get_container_client(
            os.environ["COSMOS_CONTAINER"]
        )
    return _container


def increment_count(container) -> int:
    """Atomically add one to the counter and return the new value."""
    try:
        # Server-side increment: safe when two visitors arrive at the same time.
        item = container.patch_item(item=COUNTER_ID, partition_key=COUNTER_ID, patch_operations=INCREMENT)
    except CosmosResourceNotFoundError:
        # First visit ever: create the counter document.
        try:
            item = container.create_item({"id": COUNTER_ID, "count": 1})
        except CosmosResourceExistsError:
            # Another request created it in the meantime.
            item = container.patch_item(item=COUNTER_ID, partition_key=COUNTER_ID, patch_operations=INCREMENT)
    return item["count"]


def _json(body: dict, status_code: int = 200) -> func.HttpResponse:
    return func.HttpResponse(json.dumps(body), status_code=status_code, mimetype="application/json")


@app.route(route="visitors", methods=["POST"])
def visitors(req: func.HttpRequest) -> func.HttpResponse:
    try:
        count = increment_count(get_container())
    except Exception:
        logging.exception("Failed to update visitor count")
        return _json({"error": "Could not update visitor count"}, status_code=500)
    return _json({"count": count})
