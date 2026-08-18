# Notion quick task (optional)

Press **F4** (default) to open a compact task popup. Other features work without Notion.

## Setup

1. Create a [Notion integration](https://www.notion.so/my-integrations) and copy the **Internal integration secret**.
2. Share your tasks database with that integration (⋯ on the database → **Connections**).
3. Copy the database ID from the database URL (`notion.so/.../<32-char-id>?...`).
4. In Umbrella Helper **Settings → Notion**, paste the token and database ID.

## Expected database schema

The app introspects your database and looks for properties by type and common names:

| Field | Property type | Notes |
|-------|---------------|--------|
| Title | `title` | Required |
| Status | `status` | Defaults to “Not started” when present |
| Category | `select` | Optional; name containing “category” |
| Priority | `select` | Optional; name containing “prio” / “priority” |
| Due date | `date` | Optional; name containing “due” |

If a field is missing, the popup still creates a page with the properties it finds. Category/priority are sent as Notion `select` values (not `multi_select`).

## Privacy

The integration token is stored in the macOS Keychain. Task text is sent to Notion’s API only when you submit from the Notion task popup.
