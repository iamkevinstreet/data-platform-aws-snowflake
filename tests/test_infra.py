########################################################################
#                                                                      #
#                         tests/test_infra.py                          #
#                                                                      #
########################################################################
"""
Author:            Kevin Street
Created on:        2026-11-10
Last modified on:  2026-11-10

Tests the Terraform without a Snowflake account: every file parses,
every provider is pinned to a range, no user has a password or a key,
each service user trusts one repository's job, by name and id, every
warehouse suspends within a minute under the monthly quota, and each
role reaches only what its job needs. CI's terraform validate checks
the rest against the provider's own schema.
"""

########################################################################
#                                                                      #
#                               Imports                                #
#                                                                      #
########################################################################
# Standard library
from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Final

# Third-party
import hcl2
import pytest
from kds.args import required
from kds.logs import get_logger

# Local
from support import REPO

########################################################################
#                                                                      #
#                           Global constants                           #
#                                                                      #
########################################################################
log = get_logger(__name__)

########################################################################
#                                                                      #
#                           Local constants                            #
#                                                                      #
########################################################################
# log.debug("Sets the Terraform roots")
ROOTS: Final = ("snowflake",)
# log.debug("Sets the grants each role must have, each over its own schemas")
GRANTS: Final = (
    'for s in keys(merge(local.raw_schemas, local.load_schemas)) : "LOADER.${s}" => '
    '{role = "LOADER", schema = s, privileges = local.loading}',
    'for s in keys(local.raw_schemas) : "BUILDER.${s}" => '
    '{role = "BUILDER", schema = s, privileges = ["USAGE"]}',
    'for s in keys(merge(local.model_schemas, local.mart_schemas)) : "BUILDER.${s}" => '
    '{role = "BUILDER", schema = s, privileges = local.building}',
    'for s in keys(local.mart_schemas) : "READER.${s}" => '
    '{role = "READER", schema = s, privileges = ["USAGE"]}',
)
# log.debug("Sets the reads each role must have of what is made later")
READS: Final = (
    'for s in keys(local.raw_schemas) : "BUILDER.${s}.TABLES" => '
    '{role = "BUILDER", schema = s, kind = "TABLES"}',
    'for pair in setproduct(keys(local.mart_schemas), ["TABLES", "VIEWS"]) : '
    '"READER.${pair[0]}.${pair[1]}" => {role = "READER", schema = pair[0], kind = pair[1]}',
)


########################################################################
#                                                                      #
#                           Terraform tests                            #
#                                                                      #
########################################################################
# log.debug("Defines a parsed block without the parser's quotes and markers")
def _plain(value: Any = None) -> Any:
    """Returns the value without HCL's quotes or python-hcl2's markers.

    python-hcl2 keeps each string's own quotes and marks every block
    with __is_block__; this drops both.

    Args:
        value: A parsed value: a mapping, a list or a scalar.

    Returns:
        The same value, plain.
    """
    # log.debug("Cleans the value by its type")
    match value:
        case dict():
            # log.debug("Cleans each key and value, dropping the markers")
            return {_plain(k): _plain(v) for k, v in value.items() if not k.startswith("__")}
        case list():
            # log.debug("Cleans each item")
            return [_plain(v) for v in value]
        case str() if len(value) > 1 and value[0] == value[-1] == '"':
            # log.debug("Drops the quotes")
            return value[1:-1]
        case _:
            # log.debug("Returns anything else as it is")
            return value


# log.debug("Defines one root's parsed files")
def _root(name: str | None = None) -> dict[str, list[Any]]:
    """Returns every block of the root's files, merged by kind.

    Args:
        name: The root's folder under infra/. Required.

    Returns:
        Each kind of block (resource, data, terraform) and its blocks.
    """
    # log.debug("Takes the root, which the caller must give")
    name = required(name=name)
    # log.debug("Starts the merged blocks")
    blocks: dict[str, list[Any]] = {}
    # log.debug("Parses every file of the root")
    for path in sorted((REPO / "infra" / name).glob("*.tf")):
        # log.debug("Reads the file")
        with Path(path).open(encoding="utf-8") as handle:
            # log.debug("Adds its blocks")
            for kind, items in _plain(hcl2.load(handle)).items():
                # log.debug("Merges the kind's blocks")
                blocks.setdefault(kind, []).extend(items)
    # log.debug("Returns them")
    return blocks


# log.debug("Defines one named resource of a root")
def _resource(
    blocks: dict[str, list[Any]] | None = None, kind: str | None = None, name: str | None = None
) -> dict[str, Any]:
    """Returns the resource's body.

    Args:
        blocks: The root's blocks. Required.
        kind: The resource type, such as aws_iam_role. Required.
        name: Its name in the configuration. Required.

    Returns:
        The resource's arguments.
    """
    # log.debug("Takes the blocks, which the caller must give")
    blocks = required(blocks=blocks)
    # log.debug("Takes the type, which the caller must give")
    kind = required(kind=kind)
    # log.debug("Takes the name, which the caller must give")
    name = required(name=name)
    # log.debug("Finds it among the resources")
    return next(r[kind][name] for r in blocks["resource"] if kind in r and name in r[kind])


# log.debug("Defines one root's locals, merged")
def _locals(name: str | None = None) -> dict[str, Any]:
    """Returns every local value of the root, by name.

    Args:
        name: The root's folder under infra/. Required.

    Returns:
        Each local's name and its parsed value.
    """
    # log.debug("Takes the root, which the caller must give")
    name = required(name=name)
    # log.debug("Merges the root's locals blocks")
    return {key: value for block in _root(name)["locals"] for key, value in block.items()}


# log.debug("Defines the resources of one kind")
def _all(blocks: dict[str, list[Any]] | None = None, kind: str | None = None) -> list[Any]:
    """Returns the body of every resource of the kind.

    Args:
        blocks: The root's blocks. Required.
        kind: The resource type, such as snowflake_warehouse. Required.

    Returns:
        Each resource's arguments.
    """
    # log.debug("Takes the blocks, which the caller must give")
    blocks = required(blocks=blocks)
    # log.debug("Takes the type, which the caller must give")
    kind = required(kind=kind)
    # log.debug("Returns every body of that type")
    return [body for r in blocks["resource"] if kind in r for body in r[kind].values()]


# log.debug("Defines the test that every provider is pinned")
@pytest.mark.parametrize("root", ROOTS)
def test_every_root_pins_terraform_and_its_providers(root: str) -> None:
    """A provider without a range would change under a later init.

    Args:
        root: The root's folder.
    """
    # log.debug("Reads the root's terraform block")
    (settings,) = _root(root)["terraform"]
    # log.debug("Lists each provider's version range")
    ranges = [p["version"] for block in settings["required_providers"] for p in block.values()]
    # log.debug("Checks Terraform and each provider have a range")
    assert (bool(settings["required_version"]), all(ranges), bool(ranges)) == (True, True, True)


# log.debug("Defines the test that no user has a password or a key")
def test_every_user_signs_in_by_oidc_with_no_password_or_key() -> None:
    """Service users only, each by GitHub OIDC, none with a secret."""
    # log.debug("Reads the root")
    blocks = _root("snowflake")
    # log.debug("Lists the kinds of resource it makes")
    kinds = {kind for resource in blocks["resource"] for kind in resource}
    # log.debug("Reads the service users")
    users = _all(blocks, "snowflake_service_user")
    # log.debug("Serializes them to search them")
    text = json.dumps(users)
    # log.debug("Checks no other kind of user, no secret, and an OIDC identity each")
    assert (
        bool(kinds & {"snowflake_user", "snowflake_legacy_service_user"}),
        any(word in text for word in ("password", "rsa_public_key")),
        all("oidc" in json.dumps(u["default_workload_identity"]) for u in users),
        '"https://token.actions.githubusercontent.com"' in text,
    ) == (False, False, True, True)


# log.debug("Defines the test that each service user trusts one repository's job")
def test_each_service_user_trusts_one_repository_s_job_by_name_and_id() -> None:
    """The subject names the repository by name and id, and the job."""
    # log.debug("Serializes the locals, where the subjects are built")
    built = json.dumps(_locals("snowflake")["job_users"])
    # log.debug("Checks the subject's format and that it reads the deployers")
    assert (
        "repo:%s@%d/%s@%d:environment:snowflake-%s" in built,
        "var.deployers" in built,
        "var.github_owner_id" in built,
    ) == (True, True, True)


# log.debug("Defines the test that every deployer is named by name and id")
def test_every_deployer_names_its_repository_and_id() -> None:
    """GitHub's immutable subject carries both a name and an id."""
    # log.debug("Reads the deployers variable")
    (deployers,) = [v["deployers"] for v in _root("snowflake")["variable"] if "deployers" in v]
    # log.debug("Lists the default deployers")
    listed = deployers["default"]
    # log.debug("Checks each has an owner/name and a numeric id")
    assert listed and all(
        d["repository"].count("/") == 1 and isinstance(d["id"], int) for d in listed
    )
    # log.debug("Checks each repository is listed once")
    assert len({d["id"] for d in listed}) == len(listed)


# log.debug("Defines the test that the warehouses stay small, idle-suspended and capped")
def test_every_warehouse_is_small_suspends_in_a_minute_and_is_capped() -> None:
    """X-Small, suspended after 60 s idle, under the monthly monitor."""
    # log.debug("Reads the warehouses")
    (warehouse,) = _all(_root("snowflake"), "snowflake_warehouse")
    # log.debug("Checks the size, the suspension and the monitor")
    assert (
        warehouse["warehouse_size"],
        warehouse["auto_suspend"] <= 60,
        warehouse["initially_suspended"],
        "snowflake_resource_monitor.monthly" in warehouse["resource_monitor"],
    ) == ("XSMALL", True, True, True)


# log.debug("Defines the test that each role reaches only what its job needs")
def test_loaders_write_raw_builders_write_models_and_readers_see_marts() -> None:
    """Loaders alone write raw, builders models; readers see marts."""
    # log.debug("Reads the locals")
    built = _locals("snowflake")
    # log.debug("Reads the schema grants, an expression")
    grants = built["schema_grants"]
    # log.debug("Reads the future reads, an expression")
    reads = built["future_reads"]
    # log.debug("Checks each role's schemas, and one entry each for loader and reader")
    assert (
        all(clause in grants for clause in GRANTS),
        grants.count('"LOADER.') + grants.count('"READER.'),
        all(clause in reads for clause in READS),
    ) == (True, 2, True)
    # log.debug("Checks loading writes and reading cannot")
    assert ("CREATE TABLE" in built["loading"], "CREATE VIEW" in built["building"]) == (True, True)


# log.debug("Defines the test that no one may see a personal field unmasked")
def test_the_role_that_sees_personal_fields_is_granted_to_no_one() -> None:
    """Only the role's own definition names it; no grant does."""
    # log.debug("Reads the root")
    blocks = _root("snowflake")
    # log.debug("Serializes every grant of a role")
    grants = json.dumps(_all(blocks, "snowflake_grant_account_role"))
    # log.debug("Checks it is defined and never granted")
    assert ("PERSONAL_DATA_READER" in json.dumps(blocks["locals"]), "PERSONAL" in grants) == (
        True,
        False,
    )


# log.debug("Defines the test that every schema has managed access")
def test_every_schema_has_managed_access() -> None:
    """Only this root, never a table's owner, grants on its tables."""
    # log.debug("Reads the schemas")
    (schema,) = _all(_root("snowflake"), "snowflake_schema")
    # log.debug("Checks managed access")
    assert schema["with_managed_access"] is True
