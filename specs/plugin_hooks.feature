Feature: Claude Code plugin hooks
  Scenario: A session start with no server prints one notice and exits 0
    When I run the "session" hook without a server
    Then kanban exits with code 0
    And kanban stdout contains "SessionStart"
    And kanban stdout contains "the board could not be read"

  Scenario: A project with no board configured gets nothing
    Given the database server is running
    When I run the "session" hook without a board
    Then kanban exits with code 0
    And kanban stdout is empty

  Scenario: A session start tells the coordinator to name itself and lists the cards in Doing
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I put 2 cards in Doing for agent "worker"
    And I run the "session" hook
    Then kanban exits with code 0
    And kanban stdout contains "SessionStart"
    And kanban stdout contains "You are the coordinator"
    And kanban stdout contains "#1  Doing  worker"
    And kanban stdout contains "#2  Doing  worker"

  Scenario: A subagent start tells the subagent to ask for its name and lists the cards after its own
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I put 1 cards in Doing for agent "worker"
    And I put 1 cards in Doing for agent "other"
    And I run the "subagent" hook as agent "worker"
    Then kanban exits with code 0
    And kanban stdout contains "SubagentStart"
    And kanban stdout contains "Ask your coordinator for your agent name"
    And kanban output lists "Your cards" before "In progress by other agents"
    And kanban output lists "#1  Doing  worker" before "#2  Doing  other"

  Scenario: More than 15 cards in Doing are cut at 15 lines
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I put 17 cards in Doing for agent "worker"
    And I run the "session" hook
    Then kanban exits with code 0
    And kanban stdout contains "#15  Doing  worker"
    And kanban output does not contain "#16  Doing"
    And kanban stdout contains "and 2 more"
