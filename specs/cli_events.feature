Feature: CLI events and prime
  Scenario: The journal lists the board events
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "First"
    Then the response status is 201
    When I run kanban "events --board project"
    Then kanban exits with code 0
    And kanban output contains "card.created"
    And kanban output contains "agent-1"

  Scenario: Events can be filtered by card
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "First"
    Then the response status is 201
    When I add a card titled "Second"
    Then the response status is 201
    When I run kanban "card claim 2 --board project"
    Then kanban exits with code 0
    When I run kanban "events --board project --card 1"
    Then kanban exits with code 0
    And kanban output contains "card.created"
    And kanban output does not contain "card.claimed"
    When I run kanban "events --board project --after 2"
    Then kanban exits with code 0
    And kanban output contains "card.created"
    And kanban output does not contain "board.created"

  Scenario: Prime prints the agent rules
    Given the database server is running
    When I run kanban "prime"
    Then kanban exits with code 0
    And kanban output contains "card next"
    And kanban output contains "4 somebody else won"
