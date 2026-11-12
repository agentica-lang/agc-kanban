Feature: CLI card lifecycle
  Scenario: Claim and release a card
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "First"
    Then the response status is 201
    When I run kanban "card claim 1 --board project"
    Then kanban exits with code 0
    And kanban output contains "agent-1"
    When I run kanban "card release 1 --board project"
    Then kanban exits with code 0
    And kanban output contains "free"

  Scenario: Claim next picks the first ready card
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "First"
    Then the response status is 201
    When I add a card titled "Second"
    Then the response status is 201
    When I run kanban "card next --board project"
    Then kanban exits with code 0
    And kanban output contains "First"

  Scenario: Move a card to another column
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "First"
    Then the response status is 201
    When I run kanban "card move 1 Done --board project"
    Then kanban exits with code 0
    And kanban output contains "Done"

  Scenario: A finished card cannot be finished twice
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "First"
    Then the response status is 201
    When I run kanban "card claim 1 --board project"
    Then kanban exits with code 0
    When I run kanban "card done 1 --board project"
    Then kanban exits with code 0
    And kanban output contains "Done"
    When I run kanban "card done 1 --board project"
    Then kanban exits with code 4
    And kanban stderr is "kanban: DONE: card is done"

  Scenario: Comment on a card
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "First"
    Then the response status is 201
    When I run kanban "card comment 1 hello --board project"
    Then kanban exits with code 0
    And kanban output contains "agent-1"
    When I run kanban "card show 1"
    Then kanban output contains "hello"

  Scenario: A dependency blocks a claim until it is removed
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "First"
    Then the response status is 201
    When I add a card titled "Second"
    Then the response status is 201
    When I run kanban "card dep add 2 1 --board project"
    Then kanban exits with code 0
    When I run kanban "card claim 2 --board project"
    Then kanban exits with code 4
    And kanban stderr is "kanban: BLOCKED: card is blocked by #1"
    When I run kanban "card dep remove 2 1 --board project"
    Then kanban exits with code 0
    When I run kanban "card claim 2 --board project"
    Then kanban exits with code 0

  Scenario: Releasing a card nobody holds is a no-op
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "First"
    Then the response status is 201
    When I run kanban "card release 1 --board project"
    Then kanban exits with code 0
    And kanban output contains "already free"
