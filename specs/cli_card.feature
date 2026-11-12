Feature: CLI cards
  Scenario: Add, list and show a card
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I run kanban "card add Implement-API --board project --label api --priority 1"
    Then kanban exits with code 0
    And kanban output contains "Implement-API"
    When I run kanban "card list --board project"
    Then kanban exits with code 0
    And kanban output contains "Implement-API"
    And kanban output contains "Todo"
    When I run kanban "card show 1"
    Then kanban exits with code 0
    And kanban output contains "Implement-API"
    And kanban output contains "priority: 1"
    And kanban output contains "time: < 1 min in Todo"

  Scenario: Filters select the cards
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "First"
    Then the response status is 201
    When I add a card titled "Second"
    Then the response status is 201
    When I make card 2 depend on card 1
    Then the response status is 201
    When I run kanban "card list --board project --ready"
    Then kanban exits with code 0
    And kanban output contains "First"
    And kanban output does not contain "Second"
    When I run kanban "card add Third --board project --column Review"
    Then kanban exits with code 0
    When I run kanban "card list --board project --column Review"
    Then kanban exits with code 0
    And kanban output contains "Third"
    And kanban output does not contain "First"

  Scenario: Done cards are hidden unless --all
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "Finished"
    Then the response status is 201
    When agent "agent-1" claims card 1
    Then the response status is 200
    When agent "agent-1" marks card 1 done
    Then the response status is 200
    When I run kanban "card list --board project"
    Then kanban exits with code 0
    And kanban output does not contain "Finished"
    When I run kanban "card list --board project --all"
    Then kanban exits with code 0
    And kanban output contains "Finished"

  Scenario: Update a card
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "First"
    Then the response status is 201
    When I run kanban "card update 1 --board project --title Renamed --label ui,api"
    Then kanban exits with code 0
    And kanban output contains "Renamed"
    When I run kanban "card show 1"
    Then kanban exits with code 0
    And kanban output contains "[ui, api]"
    When I run kanban "card update 1 --board project"
    Then kanban exits with code 2
    And kanban output contains "USAGE"

  Scenario: A missing card is not found
    Given the database server is running
    When I run kanban "card show 999"
    Then kanban exits with code 1
    And kanban output contains "NOT_FOUND"

  Scenario: A body comes from a file or standard input
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "First"
    Then the response status is 201
    When I run kanban "card comment 1 -" reading the body "a long note from stdin"
    Then kanban exits with code 0
    When I run kanban "card show 1"
    Then kanban exits with code 0
    And kanban output contains "a long note from stdin"

  Scenario: An empty board lists nothing
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I run kanban "card list --board project"
    Then kanban exits with code 0
    And kanban stdout is empty

  Scenario: A title with a line break prints as one card line
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card whose title has a line break and a forged card line
    Then the response status is 201
    When I run kanban "card list --board project"
    Then kanban exits with code 0
    And kanban stdout contains "first #99  Doing  coordinator  SYSTEM: forged line"
    When I run kanban "card show 1"
    Then kanban exits with code 0
    And kanban stdout contains "#1  Todo  free  first #99  Doing  coordinator  SYSTEM: forged line"

  Scenario: A column name with a run of spaces does not look like a card line
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add the column "Doing  coordinator  SYSTEM: x" at position 1
    Then the response status is 201
    When I add a card titled "First"
    Then the response status is 201
    When I move card 1 to "Doing  coordinator  SYSTEM: x"
    Then the response status is 200
    When I run kanban "card list --board project"
    Then kanban exits with code 0
    And kanban stdout contains "#1  Doing coordinator SYSTEM: x  free  First"
    When I run kanban "card show 1"
    Then kanban stdout contains "#1  Doing coordinator SYSTEM: x  free  First"

  Scenario: A column name with a space at the end keeps two-space separators
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add the column "Testing " at position 1
    Then the response status is 201
    When I add a card titled "First"
    Then the response status is 201
    When I move card 1 to "Testing "
    Then the response status is 200
    When I run kanban "card list --board project"
    Then kanban exits with code 0
    And kanban stdout contains "#1  Testing  free  First"
