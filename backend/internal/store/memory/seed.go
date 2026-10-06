package memory

import (
	"time"

	"notes-app/internal/domain"
)

// Seed fills the store with the sample data from the Figma frames. Dates are
// relative to now, so overdue and due-soon states always look right.
func (s *Store) Seed() error {
	return s.tx(func(st *state, now time.Time) error {
		loc := s.loc
		today := now.In(loc)
		// day(n) is the end (23:59) of the day n days from today, in UTC.
		day := func(n int) *time.Time {
			d := today.AddDate(0, 0, n)
			t := time.Date(d.Year(), d.Month(), d.Day(), 23, 59, 0, 0, loc).UTC()
			return &t
		}
		ago := func(d time.Duration) time.Time { return now.Add(-d) }

		srcIDs := map[string]int64{}
		for _, src := range []source{
			{name: "webwork", kind: "scraper", health: "ok", lastSyncAt: ptr(ago(12 * time.Minute))},
			{name: "autolab", kind: "scraper", health: "needs_reauth", statusMessage: ptr("needs re-login"), lastSyncAt: ptr(ago(14 * time.Hour))},
			{name: "voice", kind: "voice", health: "ok", lastSyncAt: ptr(ago(2 * time.Minute))},
			{name: "syllabus", kind: "import", health: "ok", lastSyncAt: ptr(ago(34 * 24 * time.Hour))},
			{name: "manual", kind: "manual", health: "ok"},
		} {
			src.id = st.nextID("sources")
			st.sources[src.id] = src
			srcIDs[src.name] = src.id
		}

		type tagSpec struct {
			name, color string
			special     bool
		}
		type boardSpec struct {
			name, noun, label string
			tags              []tagSpec
		}
		tagID := map[string]int64{}  // "Board/Tag" → id
		listID := map[string]int64{} // "Board/List" → id
		for _, bs := range []boardSpec{
			{"Fall 2026", "Assignments", "Classes", []tagSpec{
				{"DiffEq", "orange", true}, {"Robotics", "pink", true}, {"AI Policy", "violet", true},
				{"Exam prep", "blue", false}, {"Waiting on someone", "violet", false}, {"Group work", "cyan", false},
			}},
			{"Personal", "Tasks", "Areas", []tagSpec{
				{"Home", "cyan", true}, {"Errands", "orange", true}, {"Money", "pink", true}, {"expensive", "blue", false},
			}},
			{"Projects", "Cards", "Tags", []tagSpec{{"App", "violet", true}, {"Music", "pink", true}}},
		} {
			b, err := st.insertBoard(domain.BoardCreate{Name: bs.name, ItemNoun: &bs.noun, SpecialTagLabel: &bs.label}, ago(35*24*time.Hour))
			if err != nil {
				return err
			}
			for _, l := range st.boardLists(b.id) {
				listID[bs.name+"/"+l.name] = l.id
			}
			for _, t := range st.boardTags(b.id) {
				tagID[bs.name+"/"+t.name] = t.id
			}
			for _, ts := range bs.tags {
				id := st.nextID("tags")
				st.tags[id] = tag{id: id, boardID: b.id, name: ts.name, color: ts.color, isSpecial: ts.special, position: len(st.boardTags(b.id))}
				tagID[bs.name+"/"+ts.name] = id
			}
		}

		type cardSpec struct {
			board, list, title string
			due                *time.Time
			allDay             bool
			special            string
			tags               []string
			source, extID, url string
			created            time.Duration // how long ago
			completed          *time.Time
			notes              []domain.NoteBlock
			edited             time.Duration
		}
		cardIDs := map[string]int64{}
		for _, cs := range []cardSpec{
			{board: "Fall 2026", list: "To Do", title: "HW 5: Second-order linear ODEs", due: day(-1), special: "DiffEq",
				source: "webwork", extID: "webwork-mth306-hw5", url: "https://webwork.math.buffalo.edu/webwork2/MTH306-F26/HW5/", created: 13 * 24 * time.Hour},
			{board: "Fall 2026", list: "To Do", title: "HW 6: Laplace transforms", due: day(1), special: "DiffEq", tags: []string{"Exam prep"},
				source: "webwork", extID: "webwork-mth306-hw6", url: "https://webwork.math.buffalo.edu/webwork2/MTH306-F26/HW6/", created: 6 * 24 * time.Hour},
			{board: "Fall 2026", list: "To Do", title: "Lab 4: Particle filter localization", due: day(6), special: "Robotics", tags: []string{"Group work"},
				source: "autolab", extID: "cse-lab4", url: "https://autolab.cse.buffalo.edu/courses/cse4630-f26/assessments/lab4", created: 2 * 24 * time.Hour},
			{board: "Fall 2026", list: "To Do", title: "Policy memo (2 pages)", due: day(8), allDay: true, special: "AI Policy",
				source: "syllabus", extID: "syllabus-pol-memo", created: 34 * 24 * time.Hour},
			{board: "Fall 2026", list: "In Progress", title: "Lab 3: A* path planner", due: day(2), special: "Robotics", tags: []string{"Urgent", "Group work"},
				source: "autolab", extID: "cse-lab3", url: "https://autolab.cse.buffalo.edu/courses/cse4630-f26/assessments/lab3",
				created: 8 * 24 * time.Hour, edited: 2 * time.Hour, notes: lab3Notes()},
			{board: "Fall 2026", list: "Done", title: "Reading response: week 5", due: day(-5), allDay: true, special: "AI Policy",
				source: "syllabus", extID: "syllabus-pol-rr5", created: 34 * 24 * time.Hour, completed: ptr(ago(5*24*time.Hour + 3*time.Hour))},

			{board: "Personal", list: "To Do", title: "Hang up poster", special: "Home", source: "manual", created: 3 * 24 * time.Hour},
			{board: "Personal", list: "To Do", title: "Return library books", due: day(3), allDay: true, special: "Errands", source: "manual", created: 9 * 24 * time.Hour},
			{board: "Personal", list: "To Do", title: "Pay phone bill", due: day(9), allDay: true, special: "Money", source: "manual", created: 4 * 24 * time.Hour},
			{board: "Personal", list: "To Do", title: "Buy groceries for the week", due: day(5), allDay: true, special: "Errands", source: "voice", created: 24 * time.Hour},
			{board: "Personal", list: "In Progress", title: "Set up DJ cable + speakers", special: "Home", tags: []string{"expensive"}, source: "manual", created: 6 * 24 * time.Hour},
			{board: "Personal", list: "Done", title: "Order poster + DJ cable", special: "Errands", tags: []string{"expensive"}, source: "manual",
				created: 10 * 24 * time.Hour, completed: ptr(ago(24 * time.Hour))},

			{board: "Projects", list: "To Do", title: "Write the notes-app README", special: "App", source: "manual", created: 2 * 24 * time.Hour},
			{board: "Projects", list: "To Do", title: "Mix a set for Friday", due: day(4), allDay: true, special: "Music", source: "manual", created: 5 * 24 * time.Hour},
			{board: "Projects", list: "In Progress", title: "Build the mock backend", special: "App", tags: []string{"Urgent"}, source: "manual", created: time.Hour},
		} {
			c := card{
				id: st.nextID("cards"), boardID: st.boardIDByName(cs.board), listID: listID[cs.board+"/"+cs.list],
				title: cs.title, dueAt: cs.due, dueAllDay: cs.allDay, tagIDs: []int64{}, notes: cs.notes,
				sourceID: srcIDs[cs.source], completedAt: cs.completed,
				createdAt: ago(cs.created), updatedAt: ago(cs.edited),
			}
			if c.notes == nil {
				c.notes = []domain.NoteBlock{}
			}
			if cs.edited == 0 {
				c.updatedAt = c.createdAt
			}
			if cs.special != "" {
				c.specialTagID = ptr(tagID[cs.board+"/"+cs.special])
			}
			for _, t := range cs.tags {
				c.tagIDs = append(c.tagIDs, tagID[cs.board+"/"+t])
			}
			if cs.extID != "" {
				c.externalID = ptr(cs.extID)
				c.lastSyncedAt = st.sources[c.sourceID].lastSyncAt
			}
			if cs.url != "" {
				c.sourceURL = ptr(cs.url)
			}
			st.cards[c.id] = c
			cardIDs[cs.title] = c.id
		}

		for id := range st.lists {
			st.renumberList(id) // cards were added in display order; number them that way
		}

		fall := st.boardIDByName("Fall 2026")
		hw6 := st.cards[cardIDs["HW 6: Laplace transforms"]]
		for _, item := range []domain.InboxItem{
			{Type: domain.InboxVoice, Source: "voice", BoardID: &fall, ReceivedAt: ago(2 * time.Minute),
				RawText: "uh robotics, start reading the particle filter chapter before thursday",
				Parsed: domain.Parsed{Title: "Read particle filter chapter", SpecialTagID: ptr(tagID["Fall 2026/Robotics"]),
					DueAt: day(1), DueAllDay: true, Uncertain: map[string]string{"dueAt": `from "before thursday"`}}},
			{Type: domain.InboxVoice, Source: "voice", BoardID: &fall, ReceivedAt: ago(time.Hour),
				RawText: "policy memo due the fourteenth, around two pages",
				Parsed: domain.Parsed{Title: "Policy memo (2 pages)", SpecialTagID: ptr(tagID["Fall 2026/AI Policy"]),
					DueAt: day(8), DueAllDay: true, Uncertain: map[string]string{"specialTagId": "no class named"}}},
			{Type: domain.InboxChange, Source: "webwork", BoardID: &fall, ReceivedAt: ago(12 * time.Minute),
				RawText: "HW 6: Laplace transforms / due date changed on the course site", CardID: ptr(hw6.id),
				Parsed: domain.Parsed{Title: hw6.title, SpecialTagID: hw6.specialTagID, DueAt: hw6.dueAt, Uncertain: map[string]string{},
					ExternalID: hw6.externalID, URL: hw6.sourceURL},
				Change: &domain.Change{Field: "dueAt", OldValue: timeString(hw6.dueAt), NewValue: timeString(ptr(hw6.dueAt.AddDate(0, 0, 2)))}},
			{Type: domain.InboxDuplicate, Source: "voice", BoardID: &fall, ReceivedAt: ago(3 * time.Hour),
				RawText: "laplace homework due thursday", CardID: ptr(hw6.id),
				Parsed: domain.Parsed{Title: "Laplace homework", SpecialTagID: hw6.specialTagID, DueAt: day(1), DueAllDay: true, Uncertain: map[string]string{}}},
		} {
			item.ID = st.nextID("inbox")
			item.Status = "pending"
			st.inbox[item.ID] = item
		}
		return nil
	})
}

func (st *state) boardIDByName(name string) int64 {
	for _, b := range st.boards {
		if b.name == name {
			return b.id
		}
	}
	return 0
}

func lab3Notes() []domain.NoteBlock {
	return []domain.NoteBlock{
		{ID: "b1", Type: domain.BlockText, Text: "Grid planner on the 2D occupancy map. Diagonal moves are allowed, so the heuristic has to stay admissible — octile distance, not Manhattan. Ask in office hours whether we can reuse last week's priority queue."},
		{ID: "b2", Type: domain.BlockTodo, Text: "Re-read lecture 7 slides on informed search", Done: true},
		{ID: "b3", Type: domain.BlockTodo, Text: "Implement the priority queue", Done: true},
		{ID: "b4", Type: domain.BlockTodo, Text: "Octile-distance heuristic + diagonal moves"},
		{ID: "b5", Type: domain.BlockTodo, Text: "Test cases for fully blocked grids"},
		{ID: "b6", Type: domain.BlockLink, Title: "Lab 3 handout (PDF)", URL: "https://autolab.cse.buffalo.edu/courses/cse4630-f26/assessments/lab3/handout.pdf"},
		{ID: "b7", Type: domain.BlockLink, Title: "Red Blob Games: Introduction to A*", URL: "https://www.redblobgames.com/pathfinding/a-star/introduction.html"},
	}
}
