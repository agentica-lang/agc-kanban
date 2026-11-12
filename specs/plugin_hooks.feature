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
    And kanban stdout contains "This session is the coordinator"
    And kanban stdout contains "#1  Doing  worker"
    And kanban stdout contains "#2  Doing  worker"

  Scenario: A subagent start says the name comes from the brief and lists every card in Doing
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I put 1 cards in Doing for agent "worker"
    And I put 1 cards in Doing for agent "other"
    And I run the "subagent" hook as agent "worker"
    Then kanban exits with code 0
    And kanban stdout contains "SubagentStart"
    And kanban stdout contains "name comes from its coordinator's brief"
    And kanban stdout contains "This session's KANBAN_AGENT is worker"
    And kanban output does not contain "Your cards"
    And kanban output lists "In progress (Doing)" before "#1  Doing  worker"
    And kanban output lists "#1  Doing  worker" before "#2  Doing  other"

  Scenario: A coordinator that names itself sees its own cards first, then the others
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I put 1 cards in Doing for agent "worker"
    And I put 1 cards in Doing for agent "other"
    And I run the "session" hook as agent "other"
    Then kanban exits with code 0
    And kanban output lists "Your cards" before "#2  Doing  other"
    And kanban output lists "#2  Doing  other" before "In progress by other agents"
    And kanban output lists "In progress by other agents" before "#1  Doing  worker"

  Scenario: A title with a quote, a backslash and non-ASCII text stays valid JSON
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card whose title has a quote, a backslash and non-ASCII text
    And I run the "subagent" hook
    Then kanban exits with code 0
    And kanban stdout is a JSON document
    And the hook context contains the quoted title

  Scenario: Exactly 15 cards in Doing are all listed
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I put 15 cards in Doing for agent "worker"
    And I run the "session" hook
    Then kanban exits with code 0
    And kanban stdout contains "#15  Doing  worker"
    And kanban output does not contain "more"

  Scenario: Without kanban on PATH the hook prints nothing
    Given the database server is running
    When I run the "session" hook without kanban on PATH
    Then kanban exits with code 0
    And kanban stdout is empty

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
