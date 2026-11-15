Feature: Card archive
  Scenario: An archived card is gone from the lists, the board, next and the home page, and kept for show and the journal
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "Alpha"
    And I add a card titled "Beta"
    And I run kanban "card archive 1"
    Then kanban exits with code 0
    And kanban output contains "archived"
    And kanban output contains "Alpha"
    When I run kanban "card list --board project --all"
    Then kanban output contains "Beta"
    And kanban output does not contain "Alpha"
    When I run kanban "card next --board project"
    Then kanban output contains "Beta"
    When I get the project snapshot
    Then the response contains "Beta"
    And the response does not contain "Alpha"
    When I run kanban "card show 1"
    Then kanban exits with code 0
    And kanban output contains "Alpha"
    And kanban output contains "archived: true"
    When I get card 1
    Then the response status is 200
    And the response contains "\"archived_at\":"
    And the response does not contain "\"archived_at\":null"
    When I get board events for "project" with query "after=0&card=1"
    Then the response contains "card.created"
    And the response contains "card.archived"
    And the response contains "\"actor\":\"agent-1\""
    When I sign in
    And I get the page "/boards" with the session
    Then the response contains "<b>0</b> <span>Todo</span>"
    And the response contains "<b>1</b> <span>Doing</span>"

  Scenario: Archiving twice is one archive and one event
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "Alpha"
    And agent "agent-1" archives card 1
    Then the response status is 200
    When agent "agent-2" archives card 1
    Then the response status is 200
    And the response contains "\"archived_at\":"
    When I run kanban "card archive 1"
    Then kanban exits with code 0
    And kanban output contains "archived"
    When I get board events for "project" with query "after=0&card=1"
    Then the response contains exactly 1 occurrences of "\"kind\":\"card.archived\""

  Scenario: A card that another agent holds needs force, and the archive drops the claim
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "Alpha"
    And I add a card titled "Beta"
    And agent "bob" claims card 1
    And agent "agent-1" archives card 1
    Then the response status is 409
    And the response contains "CLAIMED"
    And the response contains "bob"
    When I run kanban "card archive 1"
    Then kanban exits with code 4
    And kanban stderr contains "CLAIMED"
    When I run kanban "card list --board project --mine"
    Then kanban output does not contain "Alpha"
    When agent "agent-1" forcibly archives card 1
    Then the response status is 200
    And the response contains "\"claimed_by\":null"
    When agent "bob" claims card 1
    Then the response status is 404
    When agent "bob" claims card 2
    And agent "bob" archives card 2
    Then the response status is 200
    When I get board events for "project" with query "after=0&card=1"
    Then the response contains "\"kind\":\"card.archived\""
    And the response contains "\"forced\":true"
    When I get board events for "project" with query "after=0&card=2"
    Then the response contains "\"forced\":false"

  Scenario: A claim whose lease ran out is free, so another agent archives the card without force
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "Alpha"
    And agent "bob" claims card 1
    And the lease of card 1 has run out
    And agent "agent-1" archives card 1
    Then the response status is 200
    And the response contains "\"claimed_by\":null"

  Scenario: An archived card refuses every write like a missing card
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "Alpha"
    And I add a card titled "Beta"
    And agent "agent-1" archives card 1
    And agent "bob" claims card 1
    Then the response status is 404
    And the response contains "NOT_FOUND"
    When I move card 1 to "Review"
    Then the response status is 404
    When agent "bob" marks card 1 done
    Then the response status is 404
    When agent "bob" comments on card 1 with "late"
    Then the response status is 404
    When I make card 2 depend on card 1
    Then the response status is 404
    When I run kanban "card move 1 Review"
    Then kanban exits with code 1
    And kanban stderr contains "NOT_FOUND"

  Scenario: An unknown card, a bad id and no agent name
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And agent "agent-1" archives card 999
    Then the response status is 404
    And the response contains "NOT_FOUND"
    When agent "agent-1" archives card 0
    Then the response status is 400
    And the response contains "INVALID"
    When I run kanban "card archive 999"
    Then kanban exits with code 1
    And kanban stderr contains "NOT_FOUND"
    When I run kanban without an agent "card archive 1"
    Then kanban exits with code 2
    And kanban stderr contains "USAGE: no agent name"

  Scenario: The cards below an archived card move up, and an emptied column starts again at 0
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "Alpha"
    And I add a card titled "Beta"
    And I add a card titled "Gamma"
    And agent "agent-1" archives card 2
    And I list project cards
    Then the response contains "\"position\":0,\"title\":\"Alpha\""
    And the response contains "\"position\":1,\"title\":\"Gamma\""
    When agent "agent-1" archives card 1
    And agent "agent-1" archives card 3
    And I add a card titled "Delta"
    Then the response contains "\"position\":0,\"title\":\"Delta\""
    When I get card 3
    Then the response status is 200
    And the response contains "\"title\":\"Gamma\""

  Scenario: An archived dependency no longer blocks, and an archived dependent is no longer waiting
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "Alpha"
    And I add a card titled "Beta"
    And I add a card titled "Gamma"
    And I add a card titled "Delta"
    And I make card 2 depend on card 1
    And I make card 3 depend on card 1
    And I make card 4 depend on card 1
    And I run kanban "card list --board project --ready"
    Then kanban output does not contain "Beta"
    When agent "agent-1" claims card 2
    Then the response status is 409
    And the response contains "BLOCKED"
    When agent "agent-1" archives card 1
    And I get card 2
    Then the response contains "\"depends_on\":[1]"
    And the response contains "\"ready\":true"
    When I run kanban "card list --board project --ready"
    Then kanban output contains "Beta"
    When agent "bob" claims card 2
    Then the response status is 200
    When agent "agent-1" archives card 3
    And I get card 1
    Then the response contains "\"blocks\":[2,4]"
    When I remove the dependency of card 4 on card 1
    Then the response status is 200
    And the response contains "\"depends_on\":[]"

  Scenario: Archiving a card on another board changes only that board
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I post a board named "Other" with slug "other" as "agent-1"
    And I add a card titled "Alpha"
    And I add a card titled "Elsewhere" to board "other"
    And agent "agent-1" archives card 2
    And I list project cards
    Then the response contains "Alpha"
    When I get board events for "other" after 0
    Then the response contains "card.archived"
    When I get board events for "project" after 0
    Then the response does not contain "card.archived"
    When I run kanban "card list --board other --all"
    Then kanban output does not contain "Elsewhere"

  Scenario: A column that holds an archived card can still become the done column
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "Alpha"
    And I add a card titled "Beta"
    And agent "agent-1" archives card 1
    And I mark column 1 as done
    Then the response status is 200
    When I get card 2
    Then the response contains "\"done\":true"

  Scenario: The home page does not count an archived dependency as blocking
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "Alpha"
    And I add a card titled "Beta"
    And I make card 2 depend on card 1
    And I sign in
    And I get the page "/boards" with the session
    Then the response contains "1 blocked"
    When agent "agent-1" archives card 1
    And I get the page "/boards" with the session
    Then the response does not contain "blocked"
    And the response contains "<b>1</b> <span>Todo</span>"

  Scenario: A column whose only card is archived can be removed, and the card is still readable
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "Alpha"
    And I add a card titled "Beta"
    And I move card 1 to "Review"
    And I run kanban "column remove Review --board project"
    Then kanban exits with code 1
    And kanban stderr contains "CONFLICT"
    When agent "agent-1" archives card 1
    And I run kanban "column remove Review --board project"
    Then kanban exits with code 0
    When I get the project snapshot
    Then the response does not contain "Review"
    When I run kanban "card show 1"
    Then kanban exits with code 0
    And kanban output contains "Alpha"
    And kanban output contains "archived: true"
    And kanban output contains "Todo"
    When I get board events for "project" with query "after=0&card=1"
    Then the response contains "card.archived"
    And the response contains "\"from\":{\"id\":3,\"name\":\"Review\"}"

  Scenario: Making a column the done column leaves the archived cards alone
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "Alpha"
    And I add a card titled "Beta"
    And I add a card titled "Gamma"
    And I move card 1 to "Done"
    And agent "agent-1" archives card 1
    And agent "agent-1" archives card 2
    And I mark column 1 as done
    Then the response status is 200
    When I get card 1
    Then the response contains "\"version\":3}"
    And the response does not contain "\"done_at\":null"
    When I get card 2
    Then the response contains "\"version\":3}"
    And the response contains "\"done_at\":null"
    When I run kanban "column add Shipped --done --board project"
    Then kanban exits with code 0
    When I get card 1
    Then the response contains "\"version\":3}"
    And the response does not contain "\"done_at\":null"

  Scenario: A live board hears the archive
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "First"
    And I sign in
    And a live client with the session subscribes to the board "project"
    Then the live client receives a frame containing "confirm_subscription"
    When I run kanban "card archive 1"
    Then kanban exits with code 0
    And the live client receives a frame containing "card.archived"
