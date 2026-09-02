from databricks.sdk import WorkspaceClient
from databricks.sdk.service.iam import ServicePrincipal

DISPLAY_NAME = "capstone-etl-pipeline"


def get_or_create(w: WorkspaceClient, display_name: str):
    """Return the service principal, creating it only if absent.

    Made idempotent so the script can be re-run during development without
    accumulating duplicate identities, which would make the grant state
    ambiguous.
    """
    for sp in w.service_principals.list():
        if sp.display_name == display_name:
            print(f"Service principal already exists: {display_name}")
            return sp

    sp = w.service_principals.create(display_name=display_name, active=True)
    print(f"Created service principal: {display_name}")
    return sp


def main():
    w = WorkspaceClient()
    sp = get_or_create(w, DISPLAY_NAME)

    print("-" * 60)
    print(f"Display name  : {sp.display_name}")
    print(f"Numeric ID    : {sp.id}")
    print(f"Application ID: {sp.application_id}")
    print("-" * 60)
    print("Use the APPLICATION ID in GRANT statements, wrapped in backticks:")
    print(f"  GRANT USE CATALOG ON CATALOG capstone_gov TO `{sp.application_id}`;")


if __name__ == "__main__":
    main()