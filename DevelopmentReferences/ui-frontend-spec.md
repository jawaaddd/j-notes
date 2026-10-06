# notes-app — MVP Feature & UI Spec

Oct 6, 2026 · Tanvir Jawad

## Overview

notes-app is a personal Kanban tracker with four MVP views: Board, Inbox, Calendar, and the Card Modal. Cards live in separate boards and are fed by scrapers, voice capture, a syllabus importer, and manual entry, all through one ingest API. The design source is the [notes-app Figma file](https://www.figma.com/design/vDCH8yz6Q2XcSZBR92Uzrq/notes-app). The database is defined in `schema.sql` and the API in `backend-api-spec.md`.

**Core concepts**

- **Board:** a fully separate set of cards, e.g. "Fall 2026", "Personal", "Projects". Each board has a name, an *item noun* used as the page title ("Assignments", "Tasks"), and a *special tag label* for its sidebar section ("Classes", "Areas").
- **Card:** a single item on a board, e.g. an assignment or an errand. Every card sits in exactly one list.
- **List:** a board's column. New boards start with To Do, In Progress, and Done; each board's lists can be renamed, added, removed, and reordered. Every list is either *open* or *done* in kind, so the app knows what counts as finished even after a rename.
- **Special tags:** a board's frequently used tags, e.g. DiffEq, Robotics, AI Policy on Fall 2026, or Home, Errands, Money on Personal. Each board has its own set, and a card has at most one. They appear in the sidebar list, where clicking one filters the board, and as the text chip on each card.
- **Regular tags:** any other tag, e.g. Urgent, Exam prep, "expensive". A card can have any number. They appear as colored dots on cards and only in the Filter popover, never in the sidebar.
- **Tags are per board:** every board has its own special and regular tags; nothing is shared across boards.
- **Urgent:** a regular tag every board starts with. It is filtered like any other tag, from the Filter popover, and is applied manually only; overdue or due-soon cards are not auto-tagged in the MVP.
- **Tag colors:** every tag, special or regular, picks one color from a fixed palette.
- **Sources:** where a card came from (webwork, autolab, voice, syllabus, manual). Stored on every card, shown only in the Card Modal. Source health is shown in the sidebar.
- **Inbox:** holds only what needs a human decision: low-confidence voice entries, scraper changes to existing cards, and likely duplicates. Confident voice entries and newly scraped cards go straight to the board.

**Conventions in this spec**

- Each view lists its elements as a table: what the user can do with the element, and the data it displays.
- "(derived)" marks a value computed from other fields rather than stored.
- "Not designed" marks an element that exists in the frames but has no designed flow yet. These are collected under Open decisions.

## Global shell

Every view sits in the same 1440×900 desktop window: title bar on top, sidebar on the left, the view's main area, and a status bar along the bottom.

| Element | Interaction | Data shown |
| --- | --- | --- |
| Window title | None | `notes-app — {board name or view name}`, e.g. "notes-app — Board", "notes-app — Inbox", "notes-app — Calendar" |
| Window controls (—, □, ✕) | Minimize, maximize, close. Native window behavior. | Static |
| Status bar, left | None | Summary for the current board and view (derived): open count, overdue count, due-tomorrow count or urgent count, e.g. "5 open · 1 overdue · 1 due tomorrow". Inbox shows "{n} to review · {n} open on board". Calendar shows "{n} due in {month} · {n} overdue". |
| Status bar, right | None | API host and time since the last successful sync of any source, e.g. "api: localhost:8080 · last sync 12m ago" |

## Sign-in and setup

Each server has one user and one password (see Auth in `backend-api-spec.md`). These screens are not designed yet; they appear before the global shell.

| Screen | When | Elements |
| --- | --- | --- |
| Connect | No server saved yet | Server address field, default `http://localhost:8080`; Connect button. The app calls `GET /api/auth/status`. |
| First-run setup | `setupRequired: true` | Setup code field (with a hint that the code is in the server's log), new password, confirm password, Set password button |
| Sign in | A password exists and the app has no valid session | Password field, Sign in button. Wrong password shows an inline error; 429 shows "Too many attempts, try again in {n}s". |

The session token is kept in the OS keychain. Any 401 from a normal route returns the app to Sign in. Settings (not designed) will hold Sign out, Change password, and the API token list, where the user creates a token for each scraper and copies it once.

## Sidebar

The sidebar is one shared component (Figma: **Sidebar**) on every view. Its `Active` variant (Board, Inbox, Calendar) sets which row is highlighted. Its `Board Name` and `Special Tag Label` text follow the selected board.

| Element | Interaction | Data shown |
| --- | --- | --- |
| App name "notes" | None | Static text |
| BOARD section label | None | Static text |
| Board switcher | Click opens the Board menu. Highlighted (filled row) when the Board view is active. Selecting it from another view returns to the Board view. | Selected board's name, e.g. "Fall 2026"; caret; open card count for that board (derived) |
| Board menu (dropdown) | Click a board to switch to it. Same width, x position and 6px radius as the switcher; item text aligns with the switcher text. Closes on selection, Esc, or outside click. | Array of boards `[{id, name, openCount, overdueCount}]`, each shown as name plus a subline like "5 open · 1 overdue"; checkmark on the current board |
| "+ New board" (in menu) | Opens the create-board flow (not designed) | Static |
| "Manage boards" (in menu) | Opens the Manage boards view (not designed; see Managing boards and lists) | Static |
| Inbox | Navigates to the Inbox view | Count of Inbox items awaiting review |
| Calendar | Navigates to the Calendar view | None |
| Archive | Navigates to the Archive view (not designed) | None |
| Special tag section label | None | Current board's special tag label in caps, e.g. "CLASSES" or "AREAS" |
| Special tag rows | Hover: the row gets a faint highlight and its dot changes from neutral gray to the tag's palette color. Click: filters the board by that special tag; clicking the selected row again clears it. This is the only special tag filter; the Board view has no special tag chips. | Current board's special tags `[{id, name, color, openCardCount}]`, e.g. DiffEq / Robotics / AI Policy, or Home / Errands / Money. Each row shows a dot on the left (neutral by default), the name, and the open card count. Regular tags such as "expensive" never appear here. |
| SOURCES section label | None | Static text |
| Source rows | None in MVP (re-login or resync from here is a later addition) | Sources `[{name, health, statusText}]`. Dot is Indicator green when healthy and Danger red when broken. The status subline reads, e.g., "synced 12m ago", "needs re-login" (in Danger), "1 new entry", "imported Sep 2". A source that has never synced shows a red dot and "not set up". |
| Settings (gear icon + label) | Opens Settings (not designed) | Static |

## Card

The Card component (Figma: **Card**) is the only way a card appears on the board. It shows the card's special tag, its regular tags as dots, its title, and its due date. Source is never shown on the card.

| Element | Interaction | Data shown |
| --- | --- | --- |
| Card body | Click opens the Card Modal. Drag to move it: within its list or into another list at a chosen spot (Custom sort), or into another list (other sorts). | Whole card |
| Special tag chip (top left) | None | Name of the card's special tag in mono text, e.g. "DiffEq", "Home". No color on the card. Hidden when the card has none. |
| Tag dots (top right) | Hover a dot shows a tooltip with the tag name (planned) | The card's regular tags, up to 4 dots, each in its tag's palette color, e.g. Urgent (Accent yellow) + Group work (cyan). Hidden when the card has none. |
| Title | None | Card title, wraps to multiple lines |
| Due line | None | Due text (derived from `dueAt`, the list's kind, and today): "Due Thu, Oct 8", "Due tomorrow", "Overdue · 1 day", "No due date", or "Done Oct 5" once completed |

**States** (combine; e.g. overdue + dimmed)

| State | When | Appearance |
| --- | --- | --- |
| Normal | Default | Card Background fill, Card Border outline, due text in Muted |
| Due soon | Due today or tomorrow, in an open list | Due text in Accent |
| Overdue | `dueAt` is in the past, in an open list | Due text in Danger and a Danger border |
| Done | In a done-kind list | Whole card at 55% opacity |
| Dimmed | A filter is active and the card doesn't match | Whole card at 30% opacity; stays in place |

Cards within a list follow the Sort setting. **Custom**, the default, is the order you arrange by hand:

- Dragging a card over a list shows an Accent insertion line where it will land; dropping puts it there, in the same list or another one.
- New cards, and cards moved by Mark as done, a list delete, or a board move, go to the end of their list.
- In the other sorts (Due date, Date added, Title), dragging only moves a card to another list; it lands at the end of that list's custom order and shows in sort order. Reordering within a list needs Custom.
- The custom order is stored on the server, so it is the same on every device.

## Board view

The Board view shows the selected board's cards in its lists, left to right, with search and tag filtering above them; special tag filtering lives in the sidebar. Filters dim non-matching cards instead of hiding them, so cards never move when a filter changes.

| Element | Interaction | Data shown |
| --- | --- | --- |
| Page title | None | Board's item noun, e.g. "Assignments" (Fall 2026), "Tasks" (Personal) |
| Subtitle | None | Unfiltered: "{board name} · {n} open · {n} overdue" (derived). Filtered: "Showing {matches} of {total} · filtered by {tag names}". |
| Search field | Click or Ctrl K focuses it; typing filters cards by title | Placeholder "Search Cards…", shortcut hint "Ctrl K" |
| + New Card button | Opens the Card Modal in create mode on the current board, in its first open list (create mode not designed). Ctrl N does the same from any screen. | Static, Accent fill; tooltip "Ctrl N" |
| Filter pill | Click opens or closes the Filter popover | Filter icon + "Filter". With ≥1 tag filter on: Accent outline and a count badge of active tag filters. |
| Filter popover | Check or uncheck tags (multi-select). "Match any ▾" switches to "Match all". "Clear" unchecks everything. Closes on outside click or Esc. | TAGS list of the board's regular tags `[{name, color, openCount}]`, each with checkbox, color dot, name, count; match mode; Clear link |
| Sort pill | Click opens the sort menu: Custom, Due date, Date added, Title | Sort icon + current sort, default "Custom" |
| List headers | Done lists only: a round archive button at the right end archives every card on the list after a confirm | List name, e.g. To Do, In Progress, Done, and the count of cards in that list. The archive button is disabled when the list is empty; its tooltip reads "Archive all N". |
| Lists | Drop a card to move it there. While a card hovers, the list gets a faint highlight with padding around its cards, and in Custom sort an insertion line. | Cards in that list, ordered by Sort |

**Filtering rules**

- The sidebar's special tag filter, tag filters, and search combine with AND. Tag filters combine with each other per the Match any/all setting.
- A card that fails any active filter is dimmed to 30%; matches stay at full opacity.
- List counts always show the full list total, not the filtered count.

## Inbox view

The Inbox holds only items that need a human decision before they touch the board, and is built to be cleared to zero with the keyboard. A classifier (e.g. Jev) scores each incoming voice entry; only low-confidence entries land here.

**What lands here**

| Type | Comes from | Example |
| --- | --- | --- |
| Voice | A voice entry the classifier isn't confident about | "uh robotics, start reading the particle filter chapter before thursday" |
| Change | A scraper sees an existing card change on the source site | HW 6 due date moved Fri, Oct 9 → Sun, Oct 11 |
| Duplicate | A new entry likely matches a card already on the board | "laplace homework due thursday" matches HW 6 |

Confident voice entries and newly scraped cards skip the Inbox and go straight to the board's first open list.

**Page elements**

| Element | Interaction | Data shown |
| --- | --- | --- |
| Page title + subtitle | None | "Inbox"; "{n} items to review before they reach the board" |
| Keyboard hints | None (they document the shortcuts) | ↑↓ Move, ↵ Accept, E Edit, X Discard |
| Type chips | Click to show only that type; "All" shows everything | All / Voice / Changes / Duplicates, each with its count |
| Item list | ↑↓ moves the selection. The selected row gets an Accent border and its primary action is the only filled button. | Inbox items, newest first |
| Footnote | None | "Confident voice entries and newly scraped assignments go straight to the board. Only guesses, changes, and conflicts land here." |

**Row layout** (all types): left column = type tag (VOICE / CHANGE / DUPLICATE), source and relative time, and the raw input in mono; middle = parsed fields in aligned Title / Special Tag / Due columns, where the special tag column header uses the board's label (e.g. CLASS); right = action buttons.

| Row type | Fields shown | Actions |
| --- | --- | --- |
| Voice | Raw transcript in quotes. Title, special tag, due. A field the parser was unsure of shows its value in Accent with "?" and a reason underneath, e.g. Due "Wed, Oct 7 ?" from "before thursday"; Class "AI Policy ?" no class named. | Accept (↵) adds it as a card in the board's first open list; Edit (E) makes the fields editable inline; Discard (X) deletes it |
| Change | Description of what changed, e.g. "HW 6: Laplace transforms / due date changed on the course site". Title, special tag, and the changed field as a diff: old value struck through → new value in Accent. | Accept change applies it to the card; Ignore keeps the card as is |
| Duplicate | The new entry's raw text. MATCHES: the existing card's title, with "already on board · {source}". | Merge folds it into the existing card; Keep both creates a separate card |

**Data per Inbox item:** id, type, source, receivedAt, rawText; parsed {title, boardId, specialTagId, dueAt}; per-field uncertainty flag and reason; for changes: cardId, field, oldValue, newValue; for duplicates: the matched cardId.

The empty state (Inbox at zero) is not designed yet.

## Calendar view

The Calendar shows the current board's cards on a month grid by due date. It is the one place where special tag colors are always visible, as the dot on each card pill.

| Element | Interaction | Data shown |
| --- | --- | --- |
| Page title | None | Displayed month, e.g. "October 2026" |
| Subtitle | None | "{board name} · {n} due this month · {n} overdue" (derived) |
| Month nav (‹ Today ›) | ‹ and › go to the previous and next month; Today returns to the current month | Static labels |
| Month / Week toggle | Switches the grid between month and week (week layout not designed) | Selected option is filled |
| + New Card button | Opens the Card Modal in create mode (not designed). Ctrl N does the same. | Static, Accent fill |
| Weekday header | None | SUN–SAT |
| Day cell | None in MVP | Date number. Days outside the month are muted at 45%. Today's number sits in an Accent pill. |
| Card pill | Click opens the Card Modal | One per card due that day: special tag color dot, title truncated to one line |

**Pill states**

| State | Appearance |
| --- | --- |
| Normal | Primary Text title on Card Background |
| Due soon | Title in Accent |
| Overdue | Title in Danger and a Danger outline |
| Done | Title struck through, pill at 60% opacity |

Cards without a due date don't appear on the calendar. Cells with more pills than fit, and dragging a pill to another day, are not designed.

## Card Modal

The Card Modal opens over the current view when a card or calendar pill is clicked. It is the only place a card's source and notes are shown. Every edit saves automatically.

| Element | Interaction | Data shown |
| --- | --- | --- |
| Scrim | Click closes the modal | Black at 60% over the view |
| Special tag chip | Click to change the card's special tag (picker not designed) | Dot in the tag's color + name, e.g. "● Robotics" |
| Regular tag chips | Click to remove or change (picker not designed) | One labeled chip per tag: dot + name, e.g. "● Urgent", "● Group work". The modal is where dot colors get their names. |
| "+ tag" | Opens the tag picker (not designed) | Static |
| List dropdown | Pick any of the board's lists; moves the card there | Current list name, e.g. "In Progress" |
| Close (✕) | Closes the modal; Esc does the same | Static |
| Title | Click to edit inline | Card title, 22px |
| Provenance line | "Open on {source} ↗" opens the original item in the browser | Small mono line under the title: "from {source} · Open on {source} ↗ · added {date} · synced {relative time}". The link appears only when the source has a URL; "synced" only for scraped cards. |
| Due | Click opens a date-and-time picker (not designed) | "DUE" label, date and time, e.g. "Thu, Oct 8 · 11:59 PM", relative subline "in 2 days" (derived) |
| Notes: text block | Click to edit; plain paragraphs. With no notes yet, clicking the empty "Write a note…" area starts a text block there. | Free text written by the user |
| Notes: todo block | Click the checkbox to toggle done; click the text to edit. Editing works like a Markdown list: Enter splits the todo at the cursor (at the end, a new todo); Enter on an empty todo ends the list; Enter at the start of a list's first todo opens a text line above the list; Backspace at the start of a todo turns it into a text line (joined to text around it), and at the start of a text line under a todo joins that line onto the todo. Arrow keys move between blocks at their edges, and clicking below the last block writes after it. Text blocks never sit side by side; they join into one. | Checkbox + text. Done todos show an Accent check, struck-through Muted text. Each unbroken run of todos is its own list with a header "{name} {done}/{total}". Click the name to rename it; it reads "Todos" until named. |
| Notes: link block | Click opens the URL in the browser | Card with ↗ icon, link title, and URL in mono |
| Insert bar | "+ Text", "+ Todo", "+ Link" append a block; typing a whole command alone on a line ("/todo", "/text", or "/link") and pressing Space or Enter turns that line into a new block; "/" alone does nothing | Hint "or type /todo, /text, or /link on a line" |
| Saved status | None | "Saved automatically · edited {relative time}"; "Saving…" while changes are waiting. Notes save 800ms after the last edit, before Mark as done, and when the modal closes. |
| Delete | Deletes the card after a confirmation | Static, Danger text |
| Mark as done | Moves the card to the board's first done-kind list and closes the modal | Static, Accent fill |

**Data per card shown in the modal:** title, list, special tag, regular tags (name and color), dueAt, source name, source URL, createdAt, lastSyncedAt, updatedAt, and the ordered list of note blocks (each a text, todo with done flag, or link with title and URL).

## Managing boards and lists

Boards, lists, and tags are edited from the Manage boards view (built, not designed); these rules hold however it ends up looking. The built view puts the boards on the left (drag to reorder, "+ New board") and the selected board on the right: its name, page title, and special tags label, edited in place; its lists (drag to reorder, rename, Open/Done toggle, delete); its special and regular tags (color dot opens the palette, rename, move between the two groups, delete); and Delete board. Every edit saves straight away.

- **Board order:** the order in the switcher menu. **Deleting the only board** is refused (`LAST_BOARD`), so the button is disabled.
- **Urgent tag:** can be renamed, never recolored, deleted, or made special. It is always Accent yellow, and no other tag can use yellow, so the palette for other tags has five colors.

- **New board:** starts with three lists (To Do and In Progress, both open; Done, done) and one tag, Urgent, which the status bar's urgent count relies on.
- **Lists:** rename, add, remove, and reorder per board. Each list is open or done in kind, and a board always keeps at least one of each. New cards land in the board's first open list.
- **Deleting a list with cards:** the user picks another list on the same board to move them to first.
- **Deleting a board with no cards:** deletes immediately.
- **Deleting a board with cards:** a warning shows the card count and offers two choices: move all cards to another board, or delete them all.
- **Moving cards to another board:** lists map by name, falling back to the target's first list of the same kind. Tags never carry over: special and regular tags are removed automatically, and the move dialog lets the user pick tags from the target board to apply.

## Visual system

The app has one dark theme built from named tokens; every color in the UI comes from this list. They exist as Figma variables in the **Color Palette** collection.

| Token | Hex | Used for |
| --- | --- | --- |
| Background | #212121 | App, sidebar, and modal backgrounds |
| Card Background | #3B3B3B | Cards, pills, active rows, popovers |
| Card Border | #303030 | Card outlines, dividers, outlined buttons |
| Heading Text | #A4EE99 | Page titles, list titles, app name. Text only, never fills or borders. |
| Primary Text | #E5FFCA | Card titles, selected labels |
| Body Text | #F3F3F3 | Sidebar labels, paragraphs, raw input |
| Muted Text | #ABABAB | Metadata, counts, placeholders, icons |
| Accent | #FFDBA1 | Primary buttons, focus/selection, due soon, links |
| Danger | #FF8A80 | Overdue, broken sources, Delete |
| Indicator | #73E462 | Healthy-source status dots only |

**Fixed tag palette** (special and regular tags each pick one): Pink #F28FAD, Blue #8AB4F8, Violet #C3A6FF, Cyan #6FD3E0, Orange #F5A97F, Yellow #E8D27C.

**Rules**

- No color coding by special tag on cards; special tag color shows only on sidebar hover, the modal chip, and calendar pills.
- Regular tag colors show as dots on cards, and labeled in the Filter popover and modal.
- Accent marks what you can act on or what needs attention soon; Danger only for overdue and errors.
- Hover colors fade in and out over about 140 ms instead of snapping; so do cards dimming under a filter.

**Type and shape**

- Fonts: Geist for UI text, Geist Mono for metadata, dates, counts, and raw input.
- Sizes: page title 24 SemiBold; modal title 22 SemiBold; card title 14 Medium; body 13–14; metadata 11–12 mono; section labels 10–11 mono caps.
- Radii: window 12, modal 14, cards 10, buttons and inputs 8, menus and nav rows 6, tag chips 4–6, pills fully rounded.
- Icons: minimal 12–14px line icons in Muted (filter, sort, settings gear).

**Figma reference:** six frames (Board, Board filtered, Personal with switcher open, Inbox, Card Modal, Calendar) and two components: **Sidebar** (variant `Active` = Board / Inbox / Calendar; text properties `Board Name`, `Special Tag Label`) and **Card** (properties Title, Special Tag, Due; tag dots).

## Open decisions

These are still unresolved and can be settled during the build.

- [ ] Are the Inbox and Sources global or per board? Voice entries likely need a parsed Board field so a personal card doesn't land in Fall 2026.
- [ ] What happens on a card with more than 4 regular tags (e.g. first 4 dots plus "+N")?
- [ ] Should Due move into the modal header next to the list dropdown?
- [ ] Does search dim non-matching cards like filters do, or hide them?
- [ ] Special and regular tags share one 5-color palette (yellow is reserved for Urgent), so the same color can still mean two things (e.g. Pink for Robotics and for Shopping). Split the palette, or accept it?

**Not designed yet** (exists as a control or rule, flow undefined): Connect, first-run setup, and Sign in screens; Archive view, Settings (including Sign out, Change password, API tokens), Manage boards (built without a frame: list and tag editing, board delete warning, move-cards dialog with tag picker), create-board flow, create mode of the Card Modal, tag picker, date-time picker, Calendar week view, calendar cell overflow, drag on the calendar, Inbox empty state, re-login from the Sources panel.
