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
    When I run kanban "card list --board project --column Todo"
    Then kanban output contains "Second"

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
    Then kanban output does not contain "Finished"
    When I run kanban "card list --board project --all"
    Then kanban output contains "Finished"

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
    Then kanban output contains "[ui, api]"
    When I run kanban "card update 1 --board project"
    Then kanban exits with code 2
    And kanban output contains "INVALID"

  Scenario: A missing card is not found
    Given the database server is running
    When I run kanban "card show 999"
    Then kanban exits with code 1
    And kanban output contains "NOT_FOUND"
