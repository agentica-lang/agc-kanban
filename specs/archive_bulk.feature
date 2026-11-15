Feature: Archive the done cards, list the archived and unarchive
  Scenario: Only the done cards that are old enough are archived, each with its event and one summary
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "Alpha"
    And I add a card titled "Beta"
    And I add a card titled "Gamma"
    And I add a card titled "Delta"
    And I move card 1 to "Done"
    And I move card 2 to "Done"
    And I move card 4 to "Doing"
    And card 1 was done 5 days ago
    And card 2 was done 2 days ago
    And agent "agent-1" archives the done cards of "project" older than 3 days
    Then the response status is 200
    And the response contains "\"archived\":1"
    And the response contains "\"cards\":[1]"
    When I run kanban "card list --board project --all"
    Then kanban output contains "Beta"
    And kanban output contains "Gamma"
    And kanban output contains "Delta"
    And kanban output does not contain "Alpha"
    When I get board events for "project" with query "after=0"
    Then the response contains exactly 1 occurrences of "\"kind\":\"card.archived\""
    And the response contains exactly 1 occurrences of "\"kind\":\"board.done_archived\""
    And the response contains "\"count\":1,\"days\":3"
    When agent "agent-1" archives the done cards of "project" older than 3 days
    Then the response contains "\"archived\":0"
    When I get board events for "project" with query "after=0"
    Then the response contains exactly 1 occurrences of "\"kind\":\"board.done_archived\""
    When agent "agent-1" archives the done cards of "project" older than 0 days
    Then the response contains "\"cards\":[2]"
    When I get board events for "project" with query "after=0"
    Then the response contains exactly 2 occurrences of "\"kind\":\"card.archived\""
    And the response contains exactly 2 occurrences of "\"kind\":\"board.done_archived\""

  Scenario: A bad request changes nothing
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "Alpha"
    And I move card 1 to "Done"
    And card 1 was done 5 days ago
    And agent "agent-1" archives the done cards of "project" older than -1 days
    Then the response status is 400
    And the response contains "INVALID"
    When agent "agent-1" archives the done cards of "nowhere" older than 3 days
    Then the response status is 404
    When I run kanban "board archive-done --board project --days 99999"
    Then kanban exits with code 1
    And kanban stderr contains "INVALID"
    When I run kanban without an agent "board archive-done --board project"
    Then kanban exits with code 2
    When I get card 1
    Then the response does not contain "\"archived_at\":1"
    And the response contains "\"archived_at\":null"

  Scenario: The CLI archives in bulk (3 days by default), lists the archived and unarchives
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "Alpha"
    And I add a card titled "Beta"
    And I add a card titled "Gamma"
    And I move card 1 to "Done"
    And I move card 2 to "Done"
    And card 1 was done 4 days ago
    And card 2 was done 9 days ago
    And I run kanban "board archive-done --board project"
    Then kanban exits with code 0
    And kanban output contains "archived 2 done cards older than 3 days"
    When I run kanban "card list --board project --archived"
    Then kanban exits with code 0
    And kanban output lists "Beta" before "Alpha"
    And kanban output does not contain "Gamma"
    When I run kanban "card list --board project --all"
    Then kanban output contains "Gamma"
    And kanban output does not contain "Alpha"
    When I run kanban "card unarchive 2"
    Then kanban exits with code 0
    And kanban output contains "unarchived"
    And kanban output contains "Beta"
    When I run kanban "card list --board project --all"
    Then kanban output contains "Beta"
    When I run kanban "card list --board project --archived"
    Then kanban output contains "Alpha"
    And kanban output does not contain "Beta"
    When I get card 2
    Then the response contains "\"archived_at\":null"
    And the response contains "\"done\":true"
    And the response contains "\"position\":0"
    When I run kanban "card unarchive 1"
    And I run kanban "card list --board project --column Done --all"
    Then kanban output lists "Alpha" before "Beta"
    When I get card 1
    Then the response contains "\"position\":0"
    When I get card 2
    Then the response contains "\"position\":1"
    When I run kanban "card archive 1"
    When I run kanban "card unarchive 2"
    Then kanban exits with code 0
    When I get board events for "project" with query "after=0&card=2"
    Then the response contains exactly 1 occurrences of "\"kind\":\"card.unarchived\""
    And the response contains "\"actor\":\"agent-1\""
    When I run kanban "card unarchive 999"
    Then kanban exits with code 1
    And kanban stderr contains "NOT_FOUND"
    When I run kanban without an agent "card unarchive 1"
    Then kanban exits with code 2

  Scenario: The archived list refuses the filters that mean nothing for it
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I run kanban "card list --board project --archived --all"
    Then kanban exits with code 2
    And kanban stderr contains "USAGE"
    When I run kanban "card list --board project --archived --ready"
    Then kanban exits with code 2
    When I list project cards with query "archived=1&ready=1"
    Then the response status is 400

  Scenario: An unarchived card goes to the end of its column and works again
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "Alpha"
    And I add a card titled "Beta"
    And agent "agent-1" archives card 1
    And I add a card titled "Gamma"
    And I run kanban "card unarchive 1"
    And I list project cards
    Then the response lists "Beta" before "Gamma"
    And the response lists "Gamma" before "Alpha"
    When agent "bob" claims card 1
    Then the response status is 200

  Scenario: The archived list is an API query
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "Alpha"
    And I add a card titled "Beta"
    And agent "agent-1" archives card 1
    And agent "agent-1" archives card 2
    And I list project cards with query "archived=1"
    Then the response lists "Beta" before "Alpha"
    When I list project cards with query "archived=1&limit=1"
    Then the response contains "Beta"
    And the response does not contain "Alpha"
    When I list project cards with query "archived=1&limit=0"
    Then the response status is 400

  Scenario: The web session archives and unarchives, and nothing else
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "Alpha"
    And I add a card titled "Beta"
    And I move card 1 to "Done"
    And card 1 was done 5 days ago
    And I sign in
    And I post "/api/cards/2/archive" with the session as agent "web" and the body "{}"
    Then the response status is 200
    And the response contains "\"archived_at\":"
    When I post "/api/cards/2/archive" with the session as agent "web" and the body "{\"force\":true}"
    Then the response status is 401
    When I post "/api/cards/2/unarchive" with the session as agent "web" and the body "{}"
    Then the response status is 200
    And the response contains "\"archived_at\":null"
    When I post "/api/boards/project/archive-done" with the session as agent "web" and the body "{\"days\":3}"
    Then the response status is 200
    And the response contains "\"archived\":1"
    When I post "/api/boards/project/archive-done" with the session as agent "" and the body "{\"days\":3}"
    Then the response status is 400
    When I post "/api/cards/2/done" with the session as agent "web" and the body "{}"
    Then the response status is 401
    When I post "/api/cards/2/move" with the session as agent "web" and the body "{\"column\":\"Doing\"}"
    Then the response status is 401
    When I post "/api/boards/project/cards" with the session as agent "web" and the body "{\"title\":\"x\"}"
    Then the response status is 401
    When I post "/api/boards/project/archive-done/extra" with the session as agent "web" and the body "{\"days\":3}"
    Then the response status is 401
    When I get board events for "project" after 0
    Then the response contains "\"actor\":\"web\""
    And the response contains "card.unarchived"

  Scenario: A live board hears the bulk archive and the unarchive
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "First"
    And I move card 1 to "Done"
    And I sign in
    And a live client with the session subscribes to the board "project"
    Then the live client receives a frame containing "confirm_subscription"
    When I run kanban "board archive-done --board project --days 0"
    Then kanban exits with code 0
    And the live client receives a frame containing "board.done_archived"
    When I run kanban "card unarchive 1"
    Then the live client receives a frame containing "card.unarchived"
