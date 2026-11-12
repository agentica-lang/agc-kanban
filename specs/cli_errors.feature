Feature: CLI failures
  Scenario: A missing key is refused
    Given the database server is running
    When I run kanban without a key "board list"
    Then kanban exits with code 3
    And kanban output contains "UNAUTHORIZED"

  Scenario: A write without an agent is a usage error
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I run kanban without an agent "card add First --board project"
    Then kanban exits with code 2
    And kanban output contains "INVALID"

  Scenario: An unknown board is not found
    Given the database server is running
    When I run kanban "board show nope"
    Then kanban exits with code 1
    And kanban output contains "NOT_FOUND"

  Scenario: A card claimed by another agent is a lost race
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "First"
    Then the response status is 201
    When agent "agent-2" claims card 1
    Then the response status is 200
    When I run kanban "card claim 1 --board project"
    Then kanban exits with code 4
    And kanban output contains "CLAIMED"

  Scenario: Two agents claiming one card end with one 0 and one 4
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "First"
    Then the response status is 201
    When two agents run kanban "card claim 1 --board project"
    Then kanban exit codes are "0,4"
    And kanban output contains "agent-"
